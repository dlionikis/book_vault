# Lib Utilities Index

> Utility modules and helpers for Book Vault backend logic

**Last Updated**: January 6, 2026

---

## API Helpers & Infrastructure

### Core API Utilities

- **api-helpers.ts** - Reusable API route handlers and entity detail endpoints. Includes `handleEntityDetailWithBooks()` for authors/narrators/series pages with pagination. Used by: browse API routes.

### Shared Query Modules (`lib/queries/`)

Book list queries shared by an API route **and** the page rendering the same
data. The pages are server components that query Prisma directly rather than
calling the API, so a query duplicated between the two will silently diverge —
which is exactly how hidden books kept appearing on the web UI after the API was
fixed. Add new list surfaces here, not as a fresh `prisma.book.findMany` in a page.

- **queries/search-books.ts** - Book search (`buildSearchWhere`, `searchBooks`). Used by: `/api/search`, `/search`.
- **queries/catalog-books.ts** - Catalog and personal-library listings (`getCatalogBooks`, `getLibraryListBooks`). Used by: `/api/books`, `/`, `/api/library`, `/library`.
- **queries/entity-books.ts** - One page of an entity's books by kind (`getEntityBooksPage`). Used by: `api-helpers.ts` and the author/narrator/series/category detail pages.
- **queries/browse-entities.ts** - Browse-by-entity listings with visible book counts (`getBrowseEntities`, `getCategoryParentPaths`). Used by: `/api/browse/*`, `/browse/*`.
- **api-types.ts** - TypeScript interfaces for API contracts. Matches OpenAPI specification. Used by: components, API routes, transformers.
- **api-utils.ts** - API utility functions including pagination builder, UUID normalization, and field parsing. Used by: API routes.

### Database & Authentication

- **db.ts** (or `prisma.ts`) - Prisma client singleton. Ensures single database connection pool. Used by: all database access.
- **auth.ts** - NextAuth configuration, session helpers, and auth utilities. Includes mobile JWT token generation. Used by: API routes, middleware.
- **jwt.ts** - JWT token creation and verification for mobile apps. Used by: mobile auth endpoints.

---

## Data Transformation

- **book-transformer.ts** - Transforms Prisma Book objects to API response format. Handles progress enrichment, library status, and nested relations. Key functions: `transformBook()`, `transformLibraryBook()`. Used by: book API routes.
- **audio-metadata.ts** - Extracts audio metadata and chapters from audio files and `.metadata.json`. Functions: `extractChaptersFromMetadata()`, `getAudioMetadata()`. Used by: book detail and chapter endpoints.
- **html-to-markdown.ts** - Converts HTML descriptions to Markdown for cleaner display. Used by: book import/sync scripts.

---

## Media & Storage

- **media.ts** - Media file URL generation and path validation. Handles local filesystem vs S3 detection. Functions: `getMediaPath()`, `validateMediaPath()`, `getBookAudioUrl()`, `getBookCoverUrl()`. Used by: audio/image API routes.
- **s3.ts** - AWS S3 client singleton and streaming utilities. Generates presigned URLs, streams files from S3. Functions: `getS3Client()`, `streamFromS3()`, `generatePresignedUrl()`, `isS3Enabled()`. Used by: production media serving.

---

## Utilities

- **logger.ts** - Structured logging utility with different log levels. Wraps console with timestamps and context. Used by: API routes, error handling.
- **rate-limit.ts** - Rate limiting middleware using in-memory store. Prevents API abuse. Used by: sensitive API routes (auth, etc.).
- **types.ts** - Shared TypeScript types not specific to API. General-purpose type definitions. Used by: multiple modules.

### Utils Subdirectory

Additional utility modules in `lib/utils/`:

- Check contents with: `ls lib/utils/`

---

## Common Patterns

### Using API Helpers

```typescript
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';

// Standardized entity detail endpoint with books
export async function GET(request: NextRequest, { params }) {
  return handleEntityDetailWithBooks(request, params.id, {
    entityModel: prisma.author,
    joinTableModel: prisma.bookAuthor,
    idFieldName: 'authorId',
    entityName: 'Author',
    getResponseFields: (author) => ({
      id: author.id,
      name: author.name,
    }),
  });
}
```

### Transforming Books

```typescript
import { transformBook, BOOK_INCLUDE } from '@/lib/book-transformer';

// Fetch with standard includes
const book = await prisma.book.findUnique({
  where: { id },
  include: BOOK_INCLUDE,
});

// Transform to API format with progress
const apiBook = await transformBook(book, userId);
```

### Media URLs

```typescript
import { getBookAudioUrl, getBookCoverUrl } from '@/lib/media';

// Get appropriate URL (S3 presigned or local)
const audioUrl = await getBookAudioUrl(book.audioUrl);
const coverUrl = await getBookCoverUrl(book.coverUrl);
```

### Database Access

```typescript
import { prisma } from '@/lib/db';

const books = await prisma.book.findMany({
  where: { ... },
  include: { authors: true }
});
```

---

## Configuration

Most modules respect environment variables:

- `DATABASE_URL` - PostgreSQL connection (db.ts)
- `AWS_S3_BUCKET`, `AWS_REGION` - S3 configuration (s3.ts)
- `MEDIA_DATA_PATH` - Local media storage path (media.ts)
- `NEXTAUTH_SECRET`, `NEXTAUTH_URL` - Auth configuration (auth.ts)
- `JWT_SECRET` - Mobile JWT signing (jwt.ts)

See `.env.example` for full list.

---

## Related Documentation

- [Data Validation Overview](../docs/data-validation-overview.md) - How schemas and types work together
- [Data Validation Layers](../docs/data-validation-layers.md) - Full validation architecture
- [API Security](../docs/API_SECURITY.md) - Auth patterns and security
- [Media Configuration](../docs/media-configuration.md) - S3 vs local setup
- [Architecture](../docs/architecture.md) - Overall system design
