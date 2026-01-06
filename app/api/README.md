# API Routes Index

> Complete reference for all API endpoints in Book Vault

**Last Updated**: January 6, 2026

---

## Authentication

### NextAuth Routes

- `GET/POST /api/auth/[...nextauth]` - NextAuth.js authentication handlers. Public.

### Mobile Authentication

- `POST /api/auth/mobile/login` - Mobile JWT-based login. Returns access and refresh tokens. Public.
- `POST /api/auth/mobile/refresh` - Refresh expired access token using refresh token. Auth: Refresh token required.
- `POST /api/auth/mobile/logout` - Invalidate refresh token. Auth: Required.
- `GET /api/auth/mobile/verify` - Verify JWT token validity. Auth: Required.

### User Registration

- `POST /api/auth/register` - Register new user account. Public.

---

## Books

### Book List & Detail

- `GET /api/books` - List all books with pagination, filtering, and sorting. Supports query params: `page`, `limit`, `sort`, `authorId`, `narratorId`, `categoryId`, `seriesId`. Auth: Optional (returns library status if authenticated).
- `GET /api/books/[id]` - Get single book details with full metadata, chapters, authors, narrators, series. Auth: Optional (returns progress if authenticated).

### Book Chapters

- `GET /api/books/[id]/chapters` - Get chapters for a book with timestamps. Returns from metadata or database. Auth: Optional.
- `POST /api/books/[id]/chapters` - Admin: Update or create chapters for a book. Auth: Required (admin).

---

## Browse & Discovery

### Browse Aggregations

- `GET /api/browse/authors` - List all authors with book counts. Auth: Optional.
- `GET /api/browse/narrators` - List all narrators with book counts. Auth: Optional.
- `GET /api/browse/series` - List all series with book counts. Auth: Optional.
- `GET /api/browse/categories` - List all categories with book counts. Auth: Optional.

### Entity Details

- `GET /api/authors/[id]` - Get author details with paginated books. Query params: `page`, `limit`, `sort`. Auth: Optional.
- `GET /api/narrators/[id]` - Get narrator details with paginated books. Query params: `page`, `limit`, `sort`. Auth: Optional.
- `GET /api/series/[id]` - Get series details with books in sequence order. Query params: `page`, `limit`. Auth: Optional.
- `GET /api/categories/[id]` - Get category details with paginated books. Query params: `page`, `limit`, `sort`. Auth: Optional.

---

## Search

- `GET /api/search` - Full-text search across books, authors, narrators, categories, descriptions. Query param: `q` (required). Returns grouped results. Auth: Optional.
- `GET /api/search/suggestions` - Get search suggestions/autocomplete. Query param: `q`. Returns top matches. Auth: Optional.

---

## Library Management

### User Library

- `GET /api/library` - Get user's library books with progress. Query params: `page`, `limit`, `sort`. Auth: Required.
- `POST /api/library` - Add book to user's library. Body: `{ bookId }`. Auth: Required.
- `DELETE /api/library/[bookId]` - Remove book from library. Auth: Required.
- `GET /api/library/check` - Check if books are in library. Query param: `bookIds` (comma-separated). Returns object mapping IDs to boolean. Auth: Required.

### Library Lists (Custom Playlists)

- `GET /api/library/lists` - Get user's custom lists. Auth: Required.
- `POST /api/library/lists` - Create new list. Body: `{ name, description? }`. Auth: Required.
- `PUT /api/library/lists/[id]` - Update list details. Body: `{ name?, description? }`. Auth: Required.
- `DELETE /api/library/lists/[id]` - Delete list. Auth: Required.
- `POST /api/library/lists/[id]/books` - Add books to list. Body: `{ bookIds: string[] }`. Auth: Required.
- `DELETE /api/library/lists/[id]/books` - Remove books from list. Body: `{ bookIds: string[] }`. Auth: Required.
- `PUT /api/library/lists/[id]/reorder` - Reorder books in list. Body: `{ bookIds: string[] }` in desired order. Auth: Required.

### Series Library Management

- `POST /api/library/series/[seriesId]` - Add all books in series to library. Auth: Required.
- `DELETE /api/library/series/[seriesId]` - Remove all books in series from library. Auth: Required.

---

## Progress Tracking

- `GET /api/progress` - Get user's progress for all books or specific books. Query param: `bookIds` (optional, comma-separated). Auth: Required.
- `POST /api/progress` - Save playback position. Body: `{ bookId, positionSeconds }`. Auto-completes if >95%. Auth: Required.
- `PUT /api/progress` - Manual progress update (mark finished/reset). Body: `{ bookId, completed, positionSeconds? }`. Auth: Required.
- `POST /api/progress/batch` - Batch update progress for multiple books. Body: `{ updates: [{ bookId, positionSeconds, completed? }] }`. Auth: Required.

---

## Media Streaming

### Audio Streaming

- `GET /api/audio/[...path]` - Stream audio files with range request support. Path segments form file path. Returns audio stream. Auth: Required.

### Images

- `GET /api/images/[...path]` - Serve book cover images and other static images. Path segments form file path. Auth: Optional.

---

## Downloads (Offline)

- `GET /api/downloads` - List user's downloaded books for offline access. Auth: Required.
- `POST /api/downloads/[bookId]` - Mark book as downloaded. Auth: Required.
- `GET /api/downloads/[bookId]/check` - Check if book is downloaded. Auth: Required.

---

## User Account

- `PUT /api/user/password` - Change user password. Body: `{ currentPassword, newPassword }`. Auth: Required.

---

## System

- `GET /api/health` - Health check endpoint. Returns system status and database connectivity. Public.

---

## Common Patterns

### Pagination

Most list endpoints support:

- `page` - Page number (default: 1)
- `limit` - Items per page (default: 20, max: 100)

Response format:

```json
{
  "data": [...],
  "pagination": {
    "currentPage": 1,
    "totalPages": 5,
    "totalItems": 87,
    "itemsPerPage": 20
  }
}
```

### Authentication

- **Required**: Must include session cookie (web) or `Authorization: Bearer <token>` (mobile)
- **Optional**: Returns additional data if authenticated
- **Public**: No authentication needed

### Error Responses

Standard error format:

```json
{
  "error": "Error message"
}
```

Common status codes:

- `400` - Bad request (validation error)
- `401` - Unauthorized
- `404` - Not found
- `500` - Server error

---

## Related Documentation

- [API Quick Reference](../docs/api-quick-ref.md) - Condensed API reference
- [OpenAPI Spec](../docs/api/openapi.yaml) - Complete API specification
- [API Security](../docs/API_SECURITY.md) - Authentication and authorization patterns
- [Data Flows](../docs/data-flows.md) - How API routes interact with database
