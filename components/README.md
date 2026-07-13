# Components Index

> Quick reference for all React components in the Book Vault application

**Last Updated**: January 6, 2026

---

## Audio & Playback

- **AudioPlayer** - Full-featured audio player with play/pause, seek, speed controls, and volume. Auto-saves position. Props: `audioUrl`, `title`, `author`, `bookId`, `coverUrl`, `initialPosition`. Used in: book detail pages.
- **PlaybackClient** - Client-side playback state management wrapper. Handles audio element lifecycle and position persistence. Used in: book pages that need playback.
- **ChapterList** - Displays book chapters with timestamps and titles. Allows jumping to specific chapters. Props: chapter data. Used in: book detail pages.

## Book Display

- **BookCard** - Single book card with cover image, title, author, series, and runtime. Links to book detail page. Props: `book`. Used in: grids, lists, search results.
- **BookGrid** - Responsive grid layout for displaying multiple books. Handles empty states. Props: `books`, `emptyMessage`. Used in: browse pages, search, library.
- **ContinueListening** - Server component that displays carousel of in-progress books. Shows progress bars and last played time. Fetches user's recent listening activity. Used in: home page.
- **ContinueListeningButton** - Client-side button to resume playback from saved position. Props: `bookId`, `position`. Used in: book cards with progress.

## Navigation & Controls

- **BackButton** - Browser back navigation button with arrow icon. Used in: detail pages, nested views.
- **Pagination** - Page navigation controls with current page display and next/prev buttons. Props: `currentPage`, `totalPages`, `baseUrl`. Used in: all paginated lists.
- **SearchBar** - Full-text search input with URL sync and clear button. Submits to `/search` route. Props: none (uses URL params). Used in: header/navbar.
- **SortDropdown** - Dropdown for sorting options. Props: `currentSort`, `onSortChange`, `options`. Used in: browse pages with multiple sort options.

## Progress & Status

- **ProgressControls** - Manual controls to mark books as finished or reset progress. Props: `bookId`, `currentStatus`. Used in: book detail pages.
- **ProgressStatus** - Displays current playback position and total duration in human-readable format. Props: `positionSeconds`, `durationSeconds`. Used in: AudioPlayer.
- **AddToLibraryButton** - Toggle button to add/remove books from user's library. Shows different states for in/out of library. Props: `bookId`, `initialState`. Used in: book detail pages, book cards.

## User Interface

- **UserMenu** - User account dropdown menu with profile and logout options. Displays username. Used in: header/navbar.
- **ThemeToggle** - Toggle between light and dark themes with icon indicator. Persists preference. Used in: header/navbar, settings.
- **ThemeProvider** - Client-side theme context provider. Wraps app to enable theme switching. Used in: root layout.
- **SessionProvider** - NextAuth session context provider wrapper. Used in: root layout.

---

## Storybook Stories

Most components have corresponding `.stories.tsx` files for isolated development and testing:

- AudioPlayer, BackButton, BookCard, BookGrid, ChapterList
- ContinueListening, Pagination, SearchBar, ThemeToggle

See [storybook.md](../docs/storybook.md) for running Storybook.

---

## Usage Patterns

### Fetching and Displaying Books

```tsx
// Server component pattern
const books = await fetchBooks();
<BookGrid books={books} />;
```

### Audio Playback

```tsx
// Client component pattern
<PlaybackClient bookId={bookId} initialPosition={progress.positionSeconds}>
  <AudioPlayer audioUrl={audioUrl} title={title} author={author} bookId={bookId} />
</PlaybackClient>
```

### Progress Tracking

```tsx
// Show progress on book cards
<BookCard book={book} />
```

---

## Component Organization

- All components are in `/components` directory
- Client components use `'use client'` directive
- Server components fetch data directly
- Storybook stories use `.stories.tsx` suffix
- Each component is a single file (no component folders)

---

## Related Documentation

- [Component Guide](../docs/component-guide.md) - Component selection decision tree
- [Data Flows](../docs/data-flows.md) - How components interact with APIs
- [Storybook](../docs/storybook.md) - Running and adding stories
