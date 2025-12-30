# API Refactoring Proposal: DRY Book Transformations

## Status: ✅ COMPLETE (December 2025)

All items in the implementation checklist have been completed. This document is preserved for historical reference.

---

## Problem (Original)

We had 6+ endpoints that all returned arrays of books with identical structure, but each had its own transformation logic:

- `/api/books` (GET list)
- `/api/books/{id}` (GET single - includes chapters optionally)
- `/api/authors/{id}` (returns author + books array)
- `/api/series/{id}` (returns series + books array)
- `/api/narrators/{id}` (returns narrator + books array)
- `/api/categories/{id}` (returns category + books array)

**Issues that motivated this refactoring:**

1. **Repetitive transformation code** - Same book transformation logic copied 5+ times
2. **Easy to miss fields** - Discovered all browse endpoints were missing `categories` field
3. **Inconsistent changes** - When categories were added to `/api/books`, browse endpoints were forgotten
4. **No type safety** - Each endpoint manually mapped Prisma results to JSON

## Solution Implemented

### 1. Centralized Book Transformer (`lib/book-transformer.ts`)

```typescript
// Standard Prisma includes for all book queries
export const BOOK_INCLUDE = {
  authors: { include: { author: true } },
  narrators: { include: { narrator: true } },
  series: { include: { series: true } },
  categories: { include: { category: true } },
} as const;

// Type-safe book with includes
export type BookWithIncludes = Prisma.BookGetPayload<{ include: typeof BOOK_INCLUDE }>;

// Single transformation function used everywhere
export function transformBook(book: BookWithIncludes) { ... }

// Library book variant (includes addedAt)
export function transformLibraryBook(libraryBook: { book: BookWithIncludes; addedAt: Date }) { ... }
```

### 2. Generic Entity Detail Handler (`lib/api-helpers.ts`)

Created `handleEntityDetailWithBooks()` to consolidate the browse endpoints pattern:

```typescript
// Example: Authors endpoint reduced to ~10 lines
export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.author,
    joinTableModel: prisma.bookAuthor,
    idFieldName: 'authorId',
    entityName: 'Author',
    getResponseFields: (author) => ({
      id: author.id,
      name: author.name,
      asin: author.asin,
    }),
  });
}
```

### 3. Unit Tests (`__tests__/lib/book-transformer.test.ts`)

Comprehensive tests ensure all OpenAPI fields are present:

- Required fields validation
- Field transformation correctness
- Relationship arrays (authors, narrators, series, categories)
- Empty array handling
- Prisma metadata exclusion

## Implementation Checklist (Completed)

- [x] Create `lib/book-transformer.ts`
- [x] Add unit tests for transformer
- [x] Refactor `/api/books/route.ts`
- [x] Refactor `/api/books/[id]/route.ts`
- [x] Refactor `/api/authors/[id]/route.ts` (via `handleEntityDetailWithBooks`)
- [x] Refactor `/api/series/[id]/route.ts` (via `handleEntityDetailWithBooks`)
- [x] Refactor `/api/narrators/[id]/route.ts` (via `handleEntityDetailWithBooks`)
- [x] Refactor `/api/categories/[id]/route.ts` (via `handleEntityDetailWithBooks`)
- [x] Refactor `/api/library/route.ts` (uses `transformLibraryBook`)
- [x] Refactor `/api/search/route.ts`
- [x] Run contract tests to verify
- [x] Update documentation

## Files Changed

| File                                     | Change                                       |
| ---------------------------------------- | -------------------------------------------- |
| `lib/book-transformer.ts`                | **NEW** - Centralized transformation logic   |
| `lib/api-helpers.ts`                     | **NEW** - Generic entity detail handler      |
| `__tests__/lib/book-transformer.test.ts` | **NEW** - Unit tests                         |
| `app/api/books/route.ts`                 | Uses `BOOK_INCLUDE` + `transformBook`        |
| `app/api/books/[id]/route.ts`            | Uses `BOOK_INCLUDE` + `transformBook`        |
| `app/api/library/route.ts`               | Uses `BOOK_INCLUDE` + `transformLibraryBook` |
| `app/api/search/route.ts`                | Uses `BOOK_INCLUDE` + `transformBook`        |
| `app/api/authors/[id]/route.ts`          | Simplified via `handleEntityDetailWithBooks` |
| `app/api/series/[id]/route.ts`           | Simplified via `handleEntityDetailWithBooks` |
| `app/api/narrators/[id]/route.ts`        | Simplified via `handleEntityDetailWithBooks` |
| `app/api/categories/[id]/route.ts`       | Simplified via `handleEntityDetailWithBooks` |

## Benefits Achieved

1. **Single source of truth** - All book transformations go through one function
2. **Consistency guaranteed** - Add a field once, all endpoints get it
3. **Type safety** - `BookWithIncludes` type catches missing includes at compile time
4. **Easier testing** - Transformer tested in isolation
5. **Reduced code** - Browse endpoints went from ~80 lines to ~15 lines each
6. **Swift/iOS compatibility** - All optional fields now present (fixes Codable errors)

## Why Tests Didn't Catch the Original Bug

The OpenAPI contract tests use `jest-openapi` which validates:

- ✅ Required fields are present
- ✅ Field types match spec
- ❌ **BUT**: Optional fields can be missing without failing validation

Since `categories` is optional in the Book schema, responses without it passed validation. However:

- **Swift's Codable** expects ALL fields defined in the struct (even optionals)
- Missing optional fields cause: `"The data couldn't be read because it isn't in the correct format"`

The new centralized transformer ensures all fields are always present, regardless of whether they're required or optional in the OpenAPI spec.

---

## Future Considerations (Not Implemented)

These were discussed but not prioritized:

1. **Transformers for other entities** - Author, Series, Narrator, Category could have their own transformers if they become complex
2. **Pre-commit hook** - Could validate that all book-returning endpoints use the transformer
3. **Make categories required** - Could change from optional to required in OpenAPI spec
4. **Stricter contract tests** - Could add custom validation that checks ALL fields (not just required ones)
5. **GraphQL migration** - Long-term consideration for avoiding this class of problems entirely

These remain as potential future improvements but are not necessary given the current implementation.
