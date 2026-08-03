# API Endpoints Quick Reference

> **Full API Documentation**: See [api/api-reference.html](api/api-reference.html) (auto-generated from OpenAPI spec)

This is a quick cheat sheet for common endpoints. For complete documentation with request/response schemas, authentication details, and examples, view the generated API reference.

## Quick Endpoints Cheat Sheet

## Books

### GET /api/books

**Query params**: `page?: number`, `limit?: number`, `sortBy?: string`

**Response**:

```typescript
{
  books: Book[],
  total: number,
  page: number,
  totalPages: number
}
```

### GET /api/books/[id]

**Response**:

```typescript
{
  book: Book; // includes authors, narrators, series
}
```

### GET /api/books/[id]/chapters

**Response**:

```typescript
{
  chapters: Chapter[]  // ordered by chapterNumber
}
```

## Progress (Authenticated)

### GET /api/progress?bookId=[id]

**Query params**: `bookId: string` (required)

**Response**:

```typescript
{
  positionSeconds: number,
  completed: boolean,
  lastPlayed: string | null  // ISO date
}
```

**Returns default values if no progress**:

```typescript
{
  positionSeconds: 0,
  completed: false,
  lastPlayed: null
}
```

**Auth**: Returns 401 if not authenticated

### POST /api/progress

**Body**:

```typescript
{
  bookId: string,
  positionSeconds: number
}
```

**Response**:

```typescript
{
  positionSeconds: number,
  completed: boolean,
  lastPlayed: string  // ISO date
}
```

**Behavior**: Creates new progress record or updates existing (upsert)

### PUT /api/progress

**Body**:

```typescript
{
  bookId: string,
  status: 'completed' | 'not-started'
}
```

**Response** (if status = 'completed'):

```typescript
{
  positionSeconds: number,  // current position preserved
  completed: true,
  lastPlayed: string
}
```

**Response** (if status = 'not-started'):

```typescript
{
  positionSeconds: 0,
  completed: false,
  lastPlayed: null
}
```

**Behavior**:

- `'completed'`: Marks book as completed (upsert)
- `'not-started'`: Deletes progress record entirely

## Library (Authenticated)

### GET /api/library

**Response**:

```typescript
{
  books: Book[],  // user's library books with full details
  total: number
}
```

**Includes**: `authors`, `narrators`, `series` relations
**Ordered by**: `addedAt DESC`

### POST /api/library

**Body**:

```typescript
{
  bookId: string;
}
```

**Response** (201 Created):

```typescript
{
  message: 'Book added to library';
}
```

**Response** (200 if already exists):

```typescript
{
  message: 'Book already in library';
}
```

**Behavior**:

- Auto-creates "My Library" list if doesn't exist
- Idempotent (safe to call multiple times)

### DELETE /api/library/[bookId]

**Response** (200):

```typescript
{
  message: 'Book removed from library';
}
```

### GET /api/library/check?bookId=[id]

**Query params**: `bookId: string` (required)

**Response**:

```typescript
{
  inLibrary: boolean;
}
```

### POST /api/library/series/[seriesId]

**Response** (201 Created):

```typescript
{
  message: 'Series added to library',
  count: number  // number of books added
}
```

**Behavior**: Adds all books in series to library

### DELETE /api/library/series/[seriesId]

**Response** (200):

```typescript
{
  message: 'Series removed from library',
  count: number  // number of books removed
}
```

## Search

### GET /api/search?q=[query]&page=[page]&limit=[limit]

**Query params**:

- `q: string` (required) - Search query
- `page?: number` (default: 1)
- `limit?: number` (default: 20)

**Response**:

```typescript
{
  query: string,
  books: Book[],
  pagination: {
    page: number,
    limit: number,
    total: number,
    pages: number
  }
}
```

**Search fields**: title, description, publisherSummary, author names, narrator names, series titles
**Case sensitivity**: Insensitive
**Auth**: Requires authentication (401 if not logged in)

## Browse

### GET /api/browse/authors

**Query params**: `page?: number`, `limit?: number`

**Response**:

```typescript
{
  authors: Author[],
  total: number
}
```

### GET /api/browse/series

**Query params**: `page?: number`, `limit?: number`

**Response**:

```typescript
{
  series: Series[],
  total: number
}
```

### GET /api/browse/narrators

**Query params**: `page?: number`, `limit?: number`

**Response**:

```typescript
{
  narrators: Narrator[],
  total: number
}
```

## Authentication

> **No registration endpoint.** Self-service signup was removed — it let anyone
> create an account on the public production site. Create accounts with
> `npm run user:create <local|prod> <username> [password]`.

### NextAuth Endpoints (handled by NextAuth.js)

- `POST /api/auth/signin` - Sign in with credentials
- `POST /api/auth/signout` - Sign out
- `GET /api/auth/session` - Get current session
- `GET /api/auth/csrf` - Get CSRF token

## Common Response Formats

### Error Response

```typescript
{
  error: string; // User-friendly error message
}
```

**Status codes**:

- `400` - Bad Request (missing/invalid params)
- `401` - Unauthorized (not logged in)
- `404` - Not Found
- `500` - Internal Server Error

### Success Response (mutations)

```typescript
{
  message: string,      // Success message
  data?: any,          // Optional data
}
```
