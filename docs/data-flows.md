# Data Flow Patterns

> Shows how data moves through the app. Use this to understand where to fetch/modify data.

## Flow 1: Playing an Audiobook (Full Flow)

```
User clicks "Play" on BookCard
  ↓
BookCard → router.push(`/books/${book.id}/play`)
  ↓
app/books/[id]/play/page.tsx (Server Component)
  → Fetches book: prisma.book.findUnique({ where: { id }, include: BOOK_INCLUDE })
  → Passes to PlaybackClient as props
  ↓
PlaybackClient (Client Component) - components/PlaybackClient.tsx
  → On mount: Fetches progress via GET /api/progress?bookId=X
  → API route: app/api/progress/route.ts GET handler
  → DB query: prisma.userProgress.findUnique({ where: { userId_bookId: { userId, bookId } } })
  → Sets initialPosition from API response
  → Renders AudioPlayer with initialPosition
  ↓
AudioPlayer - components/AudioPlayer.tsx
  → Plays audio from audioUrl (streaming via /api/audio/[...path])
  → Every 10s: Saves progress via POST /api/progress
  → API route: app/api/progress/route.ts POST handler
  → DB query: prisma.userProgress.upsert({ where: { userId_bookId }, update: { positionSeconds } })
  → On unmount: Final progress save
```

**Files involved**:

- [components/BookCard.tsx](../components/BookCard.tsx) - Renders book with play link
- [app/books/[id]/play/page.tsx](../app/books/[id]/play/page.tsx) - Server page, fetches book data
- [components/PlaybackClient.tsx](../components/PlaybackClient.tsx) - Client wrapper, manages progress state
- [components/AudioPlayer.tsx](../components/AudioPlayer.tsx) - Audio player UI, auto-save logic
- [app/api/progress/route.ts](../app/api/progress/route.ts) - GET/POST progress endpoints
- [app/api/audio/[...path]/route.ts](../app/api/audio/[...path]/route.ts) - Audio streaming with range support
- [lib/book-transformer.ts](../lib/book-transformer.ts) - `transformBook()` enriches with progress

**Key Functions**:

- `PlaybackClient.useEffect()` - Fetches initial progress on mount
- `AudioPlayer.saveProgress()` - POST /api/progress with { bookId, positionSeconds }
- `prisma.userProgress.upsert()` - Create or update progress record
- `transformBook()` - Adds progressPercentage to book object

**To modify playback**: Usually edit `PlaybackClient.tsx` or `AudioPlayer.tsx`
**To modify progress tracking**: Edit `app/api/progress/route.ts`

## Flow 2: Searching for Books

```
User types in SearchBar
  ↓
SearchBar (Client Component) - components/SearchBar.tsx
  → Syncs input with URL via searchParams
  → On submit: router.push(`/search?q=${query}`)
  ↓
app/search/page.tsx (Server Component)
  → Reads query from searchParams.get('q')
  → Fetches results: fetch(`/api/search?q=${query}&page=${page}&limit=20`)
  → API route: app/api/search/route.ts GET handler
  → DB query: prisma.book.findMany({ where: { OR: [multi-field search] }, include: BOOK_INCLUDE })
  → Renders BookGrid with results
  ↓
BookGrid - components/BookGrid.tsx
  → Maps books to BookCard components
  → Shows empty state if no results
```

**Files involved**:

- [components/SearchBar.tsx](../components/SearchBar.tsx) - Search input with URL state sync
- [app/search/page.tsx](../app/search/page.tsx) - Server page renders results
- [app/api/search/route.ts](../app/api/search/route.ts) - Multi-field search logic
- [components/BookGrid.tsx](../components/BookGrid.tsx) - Grid display
- [components/BookCard.tsx](../components/BookCard.tsx) - Individual book cards

**Database Query**:

```typescript
// In app/api/search/route.ts
const books = await prisma.book.findMany({
  where: {
    OR: [
      { title: { contains: query, mode: 'insensitive' } },
      { description: { contains: quer - components/AddToLibraryButton.tsx
  → If showSeriesOption && seriesId: Show dialog (entire series or just book?)
  → POST /api/library { bookId }
  → API route: app/api/library/route.ts POST handler
  → On success: setInLibrary(true) + onSuccess?.()
  ↓
app/api/library/route.ts POST
  → Get or create "My Library" UserList
  → DB query: prisma.userList.findFirst({ where: { userId, name: 'My Library' } })
  → If not exists: prisma.userList.create({ data: { userId, name: 'My Library' } })
  → Check if book already in library
  → DB query: prisma.userListBook.findFirst({ where: { listId, bookId } })
  → If not exists: prisma.userListBook.create({ data: { listId, bookId, addedAt: new Date() } })
  → Returns 201 Created with { success: true, addedAt }
  ↓
Component updates state, shows "In Library" badge
```

**Files involved**:

- [components/AddToLibraryButton.tsx](../components/AddToLibraryButton.tsx) - Button with click handler
- [app/api/library/route.ts](../app/api/library/route.ts) - POST handler, creates UserListBook
- [app/api/library/series/[seriesId]/route.ts](../app/api/library/series/[seriesId]/route.ts) - Batch add series

**Key Database Operations**:

```typescript
// Get or create library
let library = await prisma.userList.findFirst({
  where: { userId: user.id, name: 'My Library' },
});
if (!library) {
  library = await prisma.userList.create({
    data: { userId: user.id, name: 'My Library', description: 'Your personal audiobook library' },
  });
}

// Add book to library
await prisma.userListBook.create({
  data: { listId: library.id, bookId, position: 0 },
});
```

**Library features**:

- Auto-creates "My Library" list on first add
- Checks library status on component mount via GET /api/library/check?bookIds=x,y,z
- Series option: Can add entire series at once via POST /api/library/series/[seriesId]
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
fetch(`/api/library/check?bookIds=${bookId1},${bookId2}`)
}, [bookIds])
↓
app/api/library/check/route.ts GET handler
→ Parses comma-separated bookIds from query params
→ DB query: prisma.userListBook.findMany({ where: { listId: library.id, bookId: { in: bookIds } } })
→ Returns { [bookId]: boolean } mapping
↓
Component updates UI:

- If inLibrary: Show "In Library" badge or checkmark
- If !inLibrary: Show "Add to Library" button

````

**Files involved**:
- [components/AddToLibraryButton.tsx](../components/AddToLibraryButton.tsx) - Checks status on mount
- [app/api/library/check/route.ts](../app/api/library/check/route.ts) - Batch status check
- [app/books/[id]/page.tsx](../app/books/[id]/page.tsx) - Book detail page checks library status

**Database Query**:
```typescript
// Get user's library
const library = await prisma.userList.findFirst({
  where: { userId: user.id, name: 'My Library' },
});

// Check which books are in library
const libraryBooks = await prisma.userListBook.findMany({
  where: { listId: library.id, bookId: { in: bookIds } },
  select: { bookId: true },
});

// Return mapping { bookId: true/false }
const statusMap = bookIds.reduce((acc, id) => {
  acc[id] = libraryBooks.some(lb => lb.bookId === id);
  return acc;
}, {});
````

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
