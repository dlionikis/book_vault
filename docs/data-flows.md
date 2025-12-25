# Data Flow Patterns

> Shows how data moves through the app. Use this to understand where to fetch/modify data.

## Flow 1: Playing an Audiobook (Full Flow)

```
User clicks "Play" on BookCard
  ↓
BookCard → router.push(`/books/${book.id}/play`)
  ↓
app/books/[id]/play/page.tsx (Server Component)
  → Fetches book from DB: prisma.book.findUnique()
  → Passes to PlaybackClient as props
  ↓
PlaybackClient (Client Component)
  → On mount: Fetches progress via GET /api/progress?bookId=X
  → Sets initialPosition from API response
  → Renders AudioPlayer with initialPosition
  ↓
AudioPlayer
  → Plays audio from audioUrl
  → Every 10s: Saves progress via POST /api/progress
  → On unmount: Final progress save
```

**Files involved**:

- [components/BookCard.tsx](../components/BookCard.tsx) (trigger)
- [app/books/[id]/play/page.tsx](../app/books/[id]/play/page.tsx) (data fetch)
- [components/PlaybackClient.tsx](../components/PlaybackClient.tsx) (state management)
- [components/AudioPlayer.tsx](../components/AudioPlayer.tsx) (playback)
- [app/api/progress/route.ts](../app/api/progress/route.ts) (persistence)

**To modify playback**: Usually edit `PlaybackClient.tsx` or `AudioPlayer.tsx`
**To modify progress tracking**: Edit `app/api/progress/route.ts`

## Flow 2: Searching for Books

```
User types in SearchBar
  ↓
SearchBar (Client Component)
  → Syncs input with URL via searchParams
  → On submit: router.push(`/search?q=${query}`)
  ↓
app/search/page.tsx (Server Component)
  → Reads query from searchParams
  → Fetches results: GET /api/search?q=query&page=1&limit=20
  → Renders BookGrid with results
  ↓
BookGrid → Maps books to BookCard components
```

**Files involved**:

- [components/SearchBar.tsx](../components/SearchBar.tsx) (input)
- [app/search/page.tsx](../app/search/page.tsx) (results page)
- [app/api/search/route.ts](../app/api/search/route.ts) (search logic)
- [components/BookGrid.tsx](../components/BookGrid.tsx) (display)

**Search features**:

- Searches across: title, description, publisherSummary, author names, narrator names, series titles
- Case-insensitive matching
- Pagination support
- Includes all book relations (authors, narrators, series)

## Flow 3: Adding Book to Library

```
User clicks "Add to Library" button
  ↓
AddToLibraryButton (Client Component)
  → If showSeriesOption && seriesId: Show dialog (entire series or just book?)
  → POST /api/library { bookId }
  → On success: setInLibrary(true) + onSuccess?.()
  ↓
app/api/library/route.ts
  → Get or create "My Library" UserList
  → Check if book already in library (UserListBook)
  → Create UserListBook record
  → Returns 201 Created
  ↓
Component updates state, shows "In Library"
```

**Files involved**:

- [components/AddToLibraryButton.tsx](../components/AddToLibraryButton.tsx) (trigger)
- [app/api/library/route.ts](../app/api/library/route.ts) (persistence)

**Library features**:

- Auto-creates "My Library" list on first add
- Checks library status on component mount via GET /api/library/check
- Series option: Can add entire series at once
- Remove option: DELETE /api/library/[bookId]

## Flow 4: Checking Library Status

```
Component mounts (e.g., AddToLibraryButton, BookCard)
  ↓
useEffect(() => {
  fetch(`/api/library/check?bookId=${bookId}`)
}, [bookId])
  ↓
app/api/library/check/route.ts (if it exists)
  OR
AddToLibraryButton handles check internally
  ↓
Returns { inLibrary: boolean }
  ↓
Component updates UI (show "In Library" vs "Add to Library")
```

**Pattern**: Components check library status independently to avoid prop drilling

## Database Query Patterns

### Fetching a book with relations:

```typescript
const book = await prisma.book.findUnique({
  where: { id: bookId },
  include: {
    authors: { include: { author: true } },
    narrators: { include: { narrator: true } },
    series: { include: { series: true } },
    chapters: { orderBy: { chapterNumber: 'asc' } },
  },
});
```

### Fetching user progress:

```typescript
const progress = await prisma.userProgress.findUnique({
  where: {
    userId_bookId: { userId: session.user.id, bookId },
  },
});

// Returns: { positionSeconds: number, completed: boolean, lastPlayed: Date }
// Or null if no progress
```

### Searching books (multi-field):

```typescript
const books = await prisma.book.findMany({
  where: {
    OR: [
      { title: { contains: query, mode: 'insensitive' } },
      { description: { contains: query, mode: 'insensitive' } },
      { publisherSummary: { contains: query, mode: 'insensitive' } },
      { authors: { some: { author: { name: { contains: query, mode: 'insensitive' } } } } },
      { narrators: { some: { narrator: { name: { contains: query, mode: 'insensitive' } } } } },
      { series: { some: { series: { title: { contains: query, mode: 'insensitive' } } } } },
    ],
  },
  include: {
    authors: { include: { author: true } },
    narrators: { include: { narrator: true } },
    series: { include: { series: true } },
  },
  take: limit,
  skip: (page - 1) * limit,
});
```

### Adding book to library (with auto-list creation):

```typescript
// Get or create "My Library" list
let library = await prisma.userList.findFirst({
  where: { userId: session.user.id, name: 'My Library' },
});

if (!library) {
  library = await prisma.userList.create({
    data: {
      userId: session.user.id,
      name: 'My Library',
      description: 'Your personal audiobook library',
    },
  });
}

// Add book to library (if not already there)
await prisma.userListBook.create({
  data: { listId: library.id, bookId },
});
```

### Upserting progress (create or update):

```typescript
const progress = await prisma.userProgress.upsert({
  where: {
    userId_bookId: { userId: session.user.id, bookId },
  },
  update: {
    positionSeconds: positionSeconds,
    lastPlayed: new Date(),
  },
  create: {
    userId: session.user.id,
    bookId: bookId,
    positionSeconds: positionSeconds,
    completed: false,
  },
});
```

## Authentication Flow

All API routes requiring authentication:

```typescript
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';

const session = await getServerSession(authOptions);
if (!session?.user) {
  return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
}

// Use session.user.id for database queries
```

**Protected routes**: `/api/progress`, `/api/library`, `/api/search`

## Error Handling Pattern

All API routes follow this pattern:

```typescript
try {
  // Database operation
  const result = await prisma...
  return NextResponse.json({ data: result });
} catch (error) {
  console.error('Error description:', error);
  return NextResponse.json({ error: 'User-friendly message' }, { status: 500 });
}
```

**Client-side handling**:

```typescript
try {
  const res = await fetch('/api/endpoint');
  if (!res.ok) {
    throw new Error('Failed to fetch');
  }
  const data = await res.json();
} catch (error) {
  console.error('Error:', error);
  // Show error UI
}
```
