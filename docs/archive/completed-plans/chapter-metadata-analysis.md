# Chapter Metadata Analysis

## Summary

Audible audiobooks exported via Libation contain **embedded chapter markers** in the MP3 files. These chapters are encoded as standard MP3 chapter metadata that can be read using tools like ffmpeg/ffprobe.

## Technical Details

### Metadata Structure

Each MP3 file contains:

- **Chapter markers** with precise timestamps (millisecond accuracy)
- **Chapter titles** (though often just the book title repeated)
- **Format metadata**: title, artist, album, copyright, genre, etc.
- **Audible-specific tags**: ASIN, version, series information
- **Cuesheet data**: Complete chapter listing with titles in CUESHEET tag

### Example Data

**File**: "A Binding of Blood"

- **Total Chapters**: 56 chapters
- **Duration**: ~23.4 hours (84,347 seconds)
- **Chapter Info**: Each chapter includes:
  - `id`: Chapter number (0-based index)
  - `start_time`: Start position in seconds
  - `end_time`: End position in seconds
  - `title`: Chapter title (embedded in tags)

**Sample Chapter**:

```json
{
  "id": 10,
  "time_base": "1/1000",
  "start": 13466291,
  "start_time": "13466.291000",
  "end": 14950301,
  "end_time": "14950.301000",
  "tags": {
    "title": "A Binding of Blood"
  }
}
```

### Cuesheet Data

The files also contain a `CUESHEET` tag with detailed chapter information including actual chapter titles:

```
TRACK 1 AUDIO
  TITLE "Opening Credits"
  INDEX 01 0:00:00
TRACK 2 AUDIO
  TITLE "A Practical Guide to Sorcery Recap"
  INDEX 01 0:08:72
TRACK 3 AUDIO
  TITLE "Chapter 1. Competing for Points"
  INDEX 01 7:58:21
...
```

## Implementation Opportunities

### 1. Chapter Navigation API

Create an API endpoint to extract and serve chapter information:

```typescript
// app/api/books/[id]/chapters/route.ts
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // Get book from database with audioUrl
  const book = await prisma.book.findUnique({
    where: { id: params.id },
    select: { audioUrl: true },
  });

  if (!book?.audioUrl) {
    return NextResponse.json({ error: 'No audio file' }, { status: 404 });
  }

  // Build full path to audio file
  const audioPath = join(getAbsoluteMediaPath(), book.audioUrl);

  // Extract chapters using ffprobe
  const { stdout } = await execAsync(
    `ffprobe -v quiet -print_format json -show_chapters "${audioPath}"`
  );

  const data = JSON.parse(stdout);

  // Parse cuesheet for better chapter titles
  const chapters = parseChapters(data);

  return NextResponse.json({ chapters });
}
```

### 2. Enhanced Audio Player

Update AudioPlayer component to include:

- **Chapter list sidebar/dropdown**
- **Jump to chapter functionality**
- **Current chapter indicator**
- **Previous/Next chapter buttons**

```typescript
interface Chapter {
  id: number;
  title: string;
  startTime: number;
  endTime: number;
  duration: number;
}

// In AudioPlayer component
const [chapters, setChapters] = useState<Chapter[]>([]);
const [currentChapter, setCurrentChapter] = useState<number>(0);

// Fetch chapters on mount
useEffect(() => {
  fetch(`/api/books/${bookId}/chapters`)
    .then((res) => res.json())
    .then((data) => setChapters(data.chapters));
}, [bookId]);

// Update current chapter based on playback time
useEffect(() => {
  if (audioRef.current && chapters.length > 0) {
    const time = audioRef.current.currentTime;
    const chapter = chapters.findIndex((ch) => time >= ch.startTime && time < ch.endTime);
    if (chapter !== -1) setCurrentChapter(chapter);
  }
}, [currentTime, chapters]);

// Jump to chapter
const jumpToChapter = (chapterIndex: number) => {
  if (audioRef.current && chapters[chapterIndex]) {
    audioRef.current.currentTime = chapters[chapterIndex].startTime;
  }
};
```

### 3. Progress Tracking by Chapter

Store which chapters have been completed:

```prisma
model UserProgress {
  id              String   @id @default(cuid())
  userId          String
  bookId          String
  position        Float    // Current playback position
  completedChapters Int[]  // Array of completed chapter IDs
  lastChapter     Int      // Last chapter reached
  updatedAt       DateTime @updatedAt

  @@unique([userId, bookId])
}
```

### 4. Chapter-based Bookmarks

Allow users to bookmark specific chapters:

```prisma
model Bookmark {
  id          String   @id @default(cuid())
  userId      String
  bookId      String
  chapterId   Int
  position    Float    // Position within chapter
  note        String?  // Optional user note
  createdAt   DateTime @default(now())
}
```

## Parsing Considerations

### Cuesheet Format

The CUESHEET tag contains the most detailed chapter information:

- Track numbers (1-based)
- Descriptive chapter titles
- Timestamps in `MM:SS:FF` format (frames)

**Parsing Strategy**:

1. Extract CUESHEET from format tags
2. Parse track entries with regex
3. Convert MM:SS:FF to seconds
4. Match with chapter markers for precise timestamps

### Chapter Title Extraction

Two sources for chapter titles:

1. **Chapter tags**: Often just book title (less useful)
2. **CUESHEET data**: Contains actual chapter titles (preferred)

Recommend parsing CUESHEET for better user experience.

## Benefits

### User Experience

- **Easy navigation** through long audiobooks
- **Resume from last chapter** instead of precise position
- **See progress** by chapters completed
- **Bookmark favorite chapters**
- **Share** specific chapters with friends

### Data Insights

- Track which chapters users skip/repeat
- Identify popular chapters
- Measure engagement by chapter
- Recommend books with similar chapter structures

## Next Steps

1. **Create chapters API endpoint** - Extract and serve chapter data
2. **Update AudioPlayer** - Add chapter navigation UI
3. **Implement chapter-aware progress** - Track by chapter not just timestamp
4. **Add chapter bookmarks** - Let users save favorite parts
5. **Chapter-based recommendations** - "If you liked Chapter 5, try..."

## Testing

Files confirmed to have chapter metadata:

- ✅ "A Binding of Blood" (56 chapters)
- ✅ "Nice Dragons Finish Last" (chapters confirmed)
- Expected: All Audible audiobooks have chapters

## Technical Requirements

- **ffmpeg/ffprobe** - Already installed for audio streaming
- **Child process execution** - Available in Node.js
- **Cuesheet parser** - Need to implement or find library
- **Database updates** - Add chapter-related fields to UserProgress

## Security Considerations

- Validate book ownership before serving chapter data
- Sanitize file paths to prevent directory traversal
- Cache chapter data to avoid repeated ffprobe calls
- Consider storing chapter data in database on import
