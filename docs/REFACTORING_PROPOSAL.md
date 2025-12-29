# API Refactoring Proposal: DRY Book Transformations

## Problem

Currently, we have 4+ endpoints that all return arrays of books with identical structure:

- `/api/books` (GET list)
- `/api/books/{id}` (GET single - includes chapters optionally)
- `/api/authors/{id}` (returns author + books array)
- `/api/series/{id}` (returns series + books array)
- `/api/narrators/{id}` (returns narrator + books array)
- `/api/categories/{id}` (returns category + books array)

**Issues:**

1. **Repetitive transformation code** - Same book transformation logic copied 5+ times
2. **Easy to miss fields** - Just discovered all browse endpoints were missing `categories` field
3. **Inconsistent changes** - When we added categories to `/api/books`, we forgot all the browse endpoints
4. **No type safety** - Each endpoint manually maps Prisma results to JSON

## Why Tests Didn't Catch It

The OpenAPI contract tests use `jest-openapi` which validates:

- ✅ Required fields are present
- ✅ Field types match spec
- ❌ **BUT**: Optional fields can be missing without failing validation

Since `categories` is optional in the Book schema, responses without it pass validation. However:

- **Swift's Codable** expects ALL fields defined in the struct (even optionals)
- Missing optional fields cause: `"The data couldn't be read because it isn't in the correct format"`

## Proposed Solutions

### Option 1: Shared Book Transformation Helper (Recommended)

Create a centralized function that handles all book transformations.

```typescript
// lib/book-transformer.ts

import { Prisma } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from './media';

/**
 * Standard book include for Prisma queries
 * Use this in all queries that return books
 */
export const BOOK_INCLUDE = {
  authors: {
    include: { author: true },
  },
  narrators: {
    include: { narrator: true },
  },
  series: {
    include: { series: true },
  },
  categories: {
    include: { category: true },
  },
} as const;

/**
 * Book type with all includes
 */
export type BookWithIncludes = Prisma.BookGetPayload<{
  include: typeof BOOK_INCLUDE;
}>;

/**
 * Transform a Prisma book to API response format
 * Ensures consistency across all endpoints
 */
export function transformBook(book: BookWithIncludes) {
  return {
    id: book.id,
    asin: book.asin,
    title: book.title,
    description: book.description,
    runtimeMinutes: book.runtimeMinutes,
    releaseDate: book.releaseDate,
    publisher: book.publisher,
    coverUrl: getCoverUrl(book.coverUrl),
    audioUrl: getAudioUrl(book.audioUrl),
    authors: book.authors.map((ba) => ({
      id: ba.author.id,
      name: ba.author.name,
      asin: ba.author.asin,
    })),
    narrators: book.narrators.map((bn) => ({
      id: bn.narrator.id,
      name: bn.narrator.name,
      asin: bn.narrator.asin,
    })),
    series: book.series.map((bs) => ({
      id: bs.series.id,
      title: bs.series.title,
      asin: bs.series.asin,
      sequence: bs.sequence,
    })),
    categories: book.categories.map((bc) => ({
      id: bc.category.id,
      name: bc.category.name,
    })),
  };
}
```

**Usage in endpoints:**

```typescript
// Before (duplicated everywhere)
const booksWithUrls = bookAuthorEntries.map((entry) => {
  const book = entry.book;
  return {
    id: book.id,
    // ... 40+ lines of transformation
  };
});

// After (DRY)
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';

const bookAuthorEntries = await prisma.bookAuthor.findMany({
  include: {
    book: {
      include: BOOK_INCLUDE, // Centralized include
    },
  },
});

const booksWithUrls = bookAuthorEntries.map((entry) => transformBook(entry.book));
```

**Benefits:**

- ✅ Single source of truth for book transformation
- ✅ Add a field once, all endpoints get it
- ✅ Type-safe with Prisma's generated types
- ✅ Easy to test in isolation

### Option 2: Stricter OpenAPI Validation

Make contract tests validate that **all defined fields** (not just required ones) are present:

```typescript
// __tests__/api/openapi-contract.test.ts

function validateAllSchemaFields(data: any, schema: SchemaDefinition) {
  const errors: string[] = [];

  // Check that ALL schema fields are present (even optionals)
  for (const [field, spec] of Object.entries(schema)) {
    if (!(field in data)) {
      errors.push(`Missing field: ${field} (${spec.required ? 'required' : 'optional'})`);
    }
  }

  return errors;
}
```

This would catch missing optional fields, but doesn't solve the DRY problem.

### Option 3: GraphQL Migration (Future)

Long-term, consider GraphQL which:

- Auto-generates resolvers from schema
- Avoids field duplication
- Clients request only needed fields

But this is a major architectural change.

## Recommendation

**Implement Option 1 immediately** (shared transformation helper):

1. Create `lib/book-transformer.ts` with `BOOK_INCLUDE` and `transformBook()`
2. Refactor all 6 endpoints to use it
3. Add unit test for `transformBook()` to ensure all fields are included
4. Optionally enhance contract tests (Option 2) to catch this in future

**Estimated effort:** 2-3 hours
**Risk:** Low (can test each endpoint individually)
**Benefit:** Prevents this entire class of bugs going forward

## Implementation Checklist

- [ ] Create `lib/book-transformer.ts`
- [ ] Add unit tests for transformer
- [ ] Refactor `/api/books/route.ts`
- [ ] Refactor `/api/books/[id]/route.ts`
- [ ] Refactor `/api/authors/[id]/route.ts`
- [ ] Refactor `/api/series/[id]/route.ts`
- [ ] Refactor `/api/narrators/[id]/route.ts`
- [ ] Refactor `/api/categories/[id]/route.ts`
- [ ] Run contract tests to verify
- [ ] Update documentation

## Questions for Discussion

1. Should we also create transformers for Author, Series, Narrator, Category?
2. Should we add a pre-commit hook that validates all endpoints use the transformer?
3. Should we make `categories` required in the Book schema (non-nullable)?
