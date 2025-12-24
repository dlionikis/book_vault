# Component Selection Guide

> Quick reference for choosing the right component. Read this FIRST before exploring components.

## "I need to show a book" → Which component?

- **Grid/list of books** → `BookGrid` (handles layout + responsive grid)
  - Props: `books: Book[]`, `showProgress?: boolean`
  - Use when: Home page, search results, browse pages

- **Single book card** → `BookCard` (individual book display)
  - Props: `book: Book`, `showProgress?: boolean`
  - Use when: Inside BookGrid or custom layouts

- **Book with play button** → `BookCard` + `ContinueListeningButton`
  - Only if user has progress on this book
  - ContinueListeningButton handles routing to playback

## "I need audio playback"

- **Full playback page** → `PlaybackClient` (full-featured player)
  - Location: `app/books/[id]/play/page.tsx`
  - Handles: Progress tracking, chapter nav, Media Session API
  - Props: `audioUrl: string`, `title: string`, `author: string`, `bookId: string`, `coverUrl?: string`
  - Features: Fetches user progress on mount, auto-saves every 10s, chapter list integration

- **Embedded player only** → `AudioPlayer` (needs external state)
  - Requires: Parent to manage progress saving
  - Props: `audioUrl: string`, `title: string`, `author: string`, `bookId: string`, `coverUrl?: string`, `initialPosition?: number`, `onTimeUpdate?: (time: number) => void`, `onAudioRef?: (ref: HTMLAudioElement | null) => void`

## "I need navigation/UI controls"

- **Back button** → `BackButton` (uses router.back())
- **Pagination** → `Pagination` (handles page state)
- **Search input** → `SearchBar` (client component with URL sync)
  - Features: Syncs with URL params, clear button, form submission
- **Theme toggle** → `ThemeToggle` (dark/light mode)
- **User menu** → `UserMenu` (dropdown with logout)

## "I need to show progress/status"

- **Progress badge on book** → `ProgressBadge` (shows % or "Completed")
- **Progress controls** → `ProgressControls` (mark complete/reset buttons)
- **Progress status text** → `ProgressStatus` (human-readable text)

## "I need library management"

- **Add/remove from library** → `AddToLibraryButton`
  - Features: Checks library status on mount, handles series option, loading states
  - Props: `bookId: string`, `seriesId?: string`, `size?: 'small' | 'medium' | 'large'`, `showSeriesOption?: boolean`, `onSuccess?: () => void`
  - Behavior: Shows dialog for series books if `showSeriesOption` is true

## Server vs Client Components Quick Ref

**Client Components** (have 'use client'):

- `AudioPlayer`, `PlaybackClient`, `SearchBar`, `ThemeToggle`
- `AddToLibraryButton`, `ContinueListeningButton`, `UserMenu`
- `SessionProvider`, `ThemeProvider`

**Can be either** (no interactivity):

- `BookCard`, `BookGrid`, `Pagination`, `ProgressBadge`
- `BackButton`, `ChapterList`, `SortDropdown`

**Rule**: Only add 'use client' if component uses hooks (useState, useEffect, useRouter, etc.)

## Common Patterns

### Fetching data in Server Component, passing to Client Component

```typescript
// app/books/[id]/play/page.tsx (Server Component)
export default async function PlaybackPage({ params }: { params: { id: string } }) {
  const book = await prisma.book.findUnique({
    where: { id: params.id },
    include: { authors: { include: { author: true } } }
  });

  return (
    <PlaybackClient
      audioUrl={book.audioUrl}
      title={book.title}
      author={book.authors[0]?.author.name || 'Unknown'}
      bookId={book.id}
      coverUrl={book.coverUrl}
    />
  );
}
```

### Client component managing state, calling API

```typescript
// components/AddToLibraryButton.tsx (Client Component)
const handleAddBook = async () => {
  const res = await fetch('/api/library', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ bookId }),
  });

  if (res.ok) {
    setInLibrary(true);
    onSuccess?.();
  }
};
```
