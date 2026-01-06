# Code Relationship Map

> Comprehensive map of how features, components, APIs, database models, and utilities connect together.

**Last Updated**: January 6, 2026

---

## Feature: Audio Playback

**User Flow**: User navigates to book detail page and clicks play

**Components**:

- [PlaybackClient.tsx](../components/PlaybackClient.tsx) → Client component managing audio state and progress fetching
- [AudioPlayer.tsx](../components/AudioPlayer.tsx) → Renders audio controls and handles playback
- [ChapterList.tsx](../components/ChapterList.tsx) → Displays chapters and allows seeking
- [ProgressStatus.tsx](../components/ProgressStatus.tsx) → Shows current time and duration

**API Routes**:

- GET /api/books/[id] → [app/api/books/[id]/route.ts](../app/api/books/[id]/route.ts) - Fetches book metadata
- GET /api/books/[id]/chapters → [app/api/books/[id]/chapters/route.ts](../app/api/books/[id]/chapters/route.ts) - Gets chapter list
- GET /api/audio/[...path] → [app/api/audio/[...path]/route.ts](../app/api/audio/[...path]/route.ts) - Streams audio file with range support
- GET /api/progress → [app/api/progress/route.ts](../app/api/progress/route.ts) - Fetches saved position
- POST /api/progress → [app/api/progress/route.ts](../app/api/progress/route.ts) - Saves playback position (auto-save every 10s)

**Database Models** (Prisma):

- `Book` → Audio file path, metadata
- `UserProgress` → Current position in seconds, completion status, last played timestamp
- `Chapter` → Chapter markers with timestamps

**Utility Files**:

- [lib/audio-metadata.ts](../lib/audio-metadata.ts) → `extractChaptersFromMetadata()`, `getAudioMetadata()`
- [lib/media.ts](../lib/media.ts) → `getAudioUrl()` - Generates presigned S3 URLs or local paths
- [lib/book-transformer.ts](../lib/book-transformer.ts) → `transformBook()` - Enriches book with progress

**Page Entry Point**:

- [app/books/[id]/play/page.tsx](../app/books/[id]/play/page.tsx) - Server component that fetches book and renders PlaybackClient

---

## Feature: Book Discovery & Browsing

**User Flow**: User browses books by author, narrator, series, or category

**Components**:

- [BookCard.tsx](../components/BookCard.tsx) → Single book display with cover and metadata
- [BookGrid.tsx](../components/BookGrid.tsx) → Responsive grid of book cards
- [Pagination.tsx](../components/Pagination.tsx) → Page navigation controls
- [SortDropdown.tsx](../components/SortDropdown.tsx) → Sort options (title, author, etc.)

**API Routes**:

- GET /api/books → [app/api/books/route.ts](../app/api/books/route.ts) - List all books with filters
- GET /api/browse/authors → [app/api/browse/authors/route.ts](../app/api/browse/authors/route.ts) - Author list with counts
- GET /api/browse/narrators → [app/api/browse/narrators/route.ts](../app/api/browse/narrators/route.ts) - Narrator list
- GET /api/browse/series → [app/api/browse/series/route.ts](../app/api/browse/series/route.ts) - Series list
- GET /api/browse/categories → [app/api/browse/categories/route.ts](../app/api/browse/categories/route.ts) - Category list
- GET /api/authors/[id] → [app/api/authors/[id]/route.ts](../app/api/authors/[id]/route.ts) - Author detail with books
- GET /api/narrators/[id] → [app/api/narrators/[id]/route.ts](../app/api/narrators/[id]/route.ts) - Narrator detail with books
- GET /api/series/[id] → [app/api/series/[id]/route.ts](../app/api/series/[id]/route.ts) - Series detail with books in order
- GET /api/categories/[id] → [app/api/categories/[id]/route.ts](../app/api/categories/[id]/route.ts) - Category detail with books

**Database Models**:

- `Book` → Core book data
- `Author`, `BookAuthor` → Author relationships (many-to-many)
- `Narrator`, `BookNarrator` → Narrator relationships (many-to-many)
- `Series`, `BookSeries` → Series relationships with sequence numbers
- `Category`, `BookCategory` → Category/genre relationships (many-to-many)

**Utility Files**:

- [lib/api-helpers.ts](../lib/api-helpers.ts) → `handleEntityDetailWithBooks()` - Standardized entity pages with pagination
- [lib/book-transformer.ts](../lib/book-transformer.ts) → `transformBook()` - Converts Prisma models to API format
- [lib/api-utils.ts](../lib/api-utils.ts) → `buildPagination()` - Creates pagination metadata

**Page Entry Points**:

- [app/authors/[id]/page.tsx](../app/authors/[id]/page.tsx) - Author detail pages
- [app/narrators/[id]/page.tsx](../app/narrators/[id]/page.tsx) - Narrator detail pages
- [app/series/[id]/page.tsx](../app/series/[id]/page.tsx) - Series detail pages
- [app/categories/[id]/page.tsx](../app/categories/[id]/page.tsx) - Category detail pages
- [app/browse/page.tsx](../app/browse/page.tsx) - Browse landing page

---

## Feature: Search

**User Flow**: User types in search bar, submits query, views results

**Components**:

- [SearchBar.tsx](../components/SearchBar.tsx) → Search input with URL sync
- [BookGrid.tsx](../components/BookGrid.tsx) → Results display
- [Pagination.tsx](../components/Pagination.tsx) → Navigate result pages

**API Routes**:

- GET /api/search → [app/api/search/route.ts](../app/api/search/route.ts) - Full-text search across books
- GET /api/search/suggestions → [app/api/search/suggestions/route.ts](../app/api/search/suggestions/route.ts) - Autocomplete suggestions

**Database Models**:

- `Book` → title, description, publisherSummary (searched fields)
- `Author` → name (searched)
- `Narrator` → name (searched)
- `Series` → title (searched)
- `Category` → name (searched)

**Utility Files**:

- [lib/book-transformer.ts](../lib/book-transformer.ts) → `transformBook()` - Formats search results

**Page Entry Point**:

- [app/search/page.tsx](../app/search/page.tsx) - Search results page

**Search Logic**:

- Case-insensitive matching using Prisma `contains` mode
- Searches across: book title, description, summary, author names, narrator names, series titles, categories
- Returns paginated results with full book metadata

---

## Feature: Library Management

**User Flow**: User adds/removes books from personal library, creates custom lists

**Components**:

- [AddToLibraryButton.tsx](../components/AddToLibraryButton.tsx) → Add/remove book button with series option
- [BookGrid.tsx](../components/BookGrid.tsx) → Display library books
- [BookCard.tsx](../components/BookCard.tsx) → Individual book display

**API Routes**:

- GET /api/library → [app/api/library/route.ts](../app/api/library/route.ts) - Get user's library books
- POST /api/library → [app/api/library/route.ts](../app/api/library/route.ts) - Add book to library
- DELETE /api/library/[bookId] → [app/api/library/[bookId]/route.ts](../app/api/library/[bookId]/route.ts) - Remove book
- GET /api/library/check → [app/api/library/check/route.ts](../app/api/library/check/route.ts) - Check if books in library
- POST /api/library/series/[seriesId] → [app/api/library/series/[seriesId]/route.ts](../app/api/library/series/[seriesId]/route.ts) - Add entire series
- DELETE /api/library/series/[seriesId] → [app/api/library/series/[seriesId]/route.ts](../app/api/library/series/[seriesId]/route.ts) - Remove entire series

**Custom Lists API**:

- GET /api/library/lists → [app/api/library/lists/route.ts](../app/api/library/lists/route.ts) - Get user's custom lists
- POST /api/library/lists → [app/api/library/lists/route.ts](../app/api/library/lists/route.ts) - Create new list
- PUT /api/library/lists/[id] → [app/api/library/lists/[id]/route.ts](../app/api/library/lists/[id]/route.ts) - Update list
- DELETE /api/library/lists/[id] → [app/api/library/lists/[id]/route.ts](../app/api/library/lists/[id]/route.ts) - Delete list
- POST /api/library/lists/[id]/books → [app/api/library/lists/[id]/books/route.ts](../app/api/library/lists/[id]/books/route.ts) - Add books to list
- DELETE /api/library/lists/[id]/books → [app/api/library/lists/[id]/books/route.ts](../app/api/library/lists/[id]/books/route.ts) - Remove books
- PUT /api/library/lists/[id]/reorder → [app/api/library/lists/[id]/reorder/route.ts](../app/api/library/lists/[id]/reorder/route.ts) - Reorder books in list

**Database Models**:

- `UserList` → Custom lists (playlists), includes default "My Library"
- `UserListBook` → Books in lists with position and added timestamp
- `Book` → Referenced books

**Utility Files**:

- [lib/book-transformer.ts](../lib/book-transformer.ts) → `transformLibraryBook()` - Adds addedAt timestamp

**Page Entry Point**:

- [app/library/page.tsx](../app/library/page.tsx) - User's library page

---

## Feature: Progress Tracking

**User Flow**: System automatically tracks listening progress, user can manually mark complete/reset

**Components**:

- [AudioPlayer.tsx](../components/AudioPlayer.tsx) → Auto-saves position every 10 seconds
- [ProgressBadge.tsx](../components/ProgressBadge.tsx) → Visual progress indicator
- [ProgressControls.tsx](../components/ProgressControls.tsx) → Manual controls (mark finished/reset)
- [ContinueListening.tsx](../components/ContinueListening.tsx) → Server component showing in-progress books

**API Routes**:

- GET /api/progress → [app/api/progress/route.ts](../app/api/progress/route.ts) - Get progress for book(s)
- POST /api/progress → [app/api/progress/route.ts](../app/api/progress/route.ts) - Save position (auto-completes at >95%)
- PUT /api/progress → [app/api/progress/route.ts](../app/api/progress/route.ts) - Manual status update
- POST /api/progress/batch → [app/api/progress/batch/route.ts](../app/api/progress/batch/route.ts) - Batch progress updates

**Database Models**:

- `UserProgress` → Composite key (userId + bookId), stores positionSeconds, completed flag, lastPlayed timestamp

**Utility Files**:

- [lib/book-transformer.ts](../lib/book-transformer.ts) → Enriches books with progress percentage
- [lib/rate-limit.ts](../lib/rate-limit.ts) → Rate limits progress saves (100/minute)

**Logic**:

- Auto-save: Every 10 seconds while playing (if position changed by >5 seconds)
- Auto-complete: Marks book complete when position > 95% of total runtime
- Rate limiting: Prevents excessive API calls during continuous playback

---

## Feature: Authentication

**User Flow**: User logs in via web or mobile app

**Components**:

- [SessionProvider.tsx](../components/SessionProvider.tsx) → NextAuth session context wrapper
- [UserMenu.tsx](../components/UserMenu.tsx) → User account dropdown

**API Routes (Web)**:

- GET/POST /api/auth/[...nextauth] → [app/api/auth/[...nextauth]/route.ts](../app/api/auth/[...nextauth]/route.ts) - NextAuth handlers
- POST /api/auth/register → [app/api/auth/register/route.ts](../app/api/auth/register/route.ts) - New user registration

**API Routes (Mobile)**:

- POST /api/auth/mobile/login → [app/api/auth/mobile/login/route.ts](../app/api/auth/mobile/login/route.ts) - JWT token generation
- POST /api/auth/mobile/refresh → [app/api/auth/mobile/refresh/route.ts](../app/api/auth/mobile/refresh/route.ts) - Token refresh
- POST /api/auth/mobile/logout → [app/api/auth/mobile/logout/route.ts](../app/api/auth/mobile/logout/route.ts) - Invalidate refresh token
- GET /api/auth/mobile/verify → [app/api/auth/mobile/verify/route.ts](../app/api/auth/mobile/verify/route.ts) - Verify token validity

**Database Models**:

- `User` → email, passwordHash, name, role
- `RefreshToken` → Mobile refresh tokens with expiry

**Utility Files**:

- [lib/auth.ts](../lib/auth.ts) → NextAuth configuration, `getAuthUserFromRequest()` for dual auth
- [lib/jwt.ts](../lib/jwt.ts) → JWT token generation/verification for mobile
- [middleware.ts](../middleware.ts) → Route protection

**Auth Patterns**:

- Web: Session-based using NextAuth with cookies
- Mobile: JWT access tokens (15min) + refresh tokens (7 days)
- Dual support: Most API routes check both session and Bearer token

---

## Feature: Media Delivery (Images & Audio)

**User Flow**: System serves cover images and audio files from local storage or S3

**API Routes**:

- GET /api/images/[...path] → [app/api/images/[...path]/route.ts](../app/api/images/[...path]/route.ts) - Serve images
- GET /api/audio/[...path] → [app/api/audio/[...path]/route.ts](../app/api/audio/[...path]/route.ts) - Stream audio with range support

**Utility Files**:

- [lib/media.ts](../lib/media.ts) → URL generation, path validation
  - `getCoverUrl()` → Presigned S3 URL (prod) or local URL (dev)
  - `getAudioUrl()` → Presigned S3 URL (prod) or local URL (dev)
  - `validateMediaPath()` → Prevents directory traversal attacks
- [lib/s3.ts](../lib/s3.ts) → S3 client, streaming, presigned URL generation
  - `getS3Client()` → Singleton S3 client
  - `streamFromS3()` → Stream file from S3 bucket
  - `generatePresignedUrl()` → Time-limited URLs (1 hour)
  - `isS3Enabled()` → Check if S3 is configured

**Environment Configuration**:

- Development: Serves from local filesystem at `MEDIA_DATA_PATH`
- Production: Uses AWS S3 with presigned URLs for security

---

## Cross-Cutting Concerns

### Type Safety & Validation

**Files**:

- [lib/api-types.ts](../lib/api-types.ts) → TypeScript interfaces (generated from OpenAPI)
- [lib/api-schemas.ts](../lib/api-schemas.ts) → Zod validation schemas
- [lib/types.ts](../lib/types.ts) → Shared type definitions

**Pattern**: API routes validate with Zod, transform to TypeScript types, return OpenAPI-compliant responses

### Database Access

**Files**:

- [lib/db.ts](../lib/db.ts) → Prisma client singleton
- [prisma/schema.prisma](../prisma/schema.prisma) → Database schema

**Pattern**: All database access uses Prisma ORM with connection pooling

### Logging

**Files**:

- [lib/logger.ts](../lib/logger.ts) → Structured logging with `withLogging()` wrapper

**Pattern**: Wrap API route handlers with `withLogging()` for automatic request/response logging

### Error Handling

**Pattern**:

- API routes return `{ error: string }` with appropriate HTTP status codes
- Client components use try/catch and display error messages
- Server components handle errors with error boundaries

---

## Quick Reference: File → Purpose

| File                                                        | Purpose                         |
| ----------------------------------------------------------- | ------------------------------- |
| [app/api/books/route.ts](../app/api/books/route.ts)         | List all books with filtering   |
| [app/api/progress/route.ts](../app/api/progress/route.ts)   | Progress tracking (get/save)    |
| [components/AudioPlayer.tsx](../components/AudioPlayer.tsx) | Audio playback UI and controls  |
| [components/BookCard.tsx](../components/BookCard.tsx)       | Individual book display         |
| [lib/book-transformer.ts](../lib/book-transformer.ts)       | Transform Prisma → API format   |
| [lib/media.ts](../lib/media.ts)                             | Media URL generation (S3/local) |
| [lib/api-helpers.ts](../lib/api-helpers.ts)                 | Reusable API patterns           |

---

## Related Documentation

- [API Routes Index](../app/api/README.md) - Complete API endpoint reference
- [Components Index](../components/README.md) - All components with descriptions
- [Lib Utilities](../lib/README.md) - Utility module reference
- [Data Flows](data-flows.md) - Step-by-step flow diagrams
- [Architecture](architecture.md) - System design overview
