# Entity Detail Endpoints DRY Refactor - Implementation Plan

**Created**: December 28, 2024
**Status**: Planning
**Complexity**: Medium
**Estimated Effort**: 2-3 hours
**Risk Level**: Low (high test coverage exists)

---

## Executive Summary

Refactor four nearly-identical "entity detail with books" endpoints to use a shared generic helper function, reducing ~230 lines of duplicated code while maintaining 100% backward compatibility and OpenAPI compliance.

### Affected Endpoints

- `GET /api/authors/{id}` - [app/api/authors/\[id\]/route.ts](../app/api/authors/[id]/route.ts) (82 lines → ~15 lines)
- `GET /api/narrators/{id}` - [app/api/narrators/\[id\]/route.ts](../app/api/narrators/[id]/route.ts) (82 lines → ~15 lines)
- `GET /api/series/{id}` - [app/api/series/\[id\]/route.ts](../app/api/series/[id]/route.ts) (78 lines → ~15 lines)
- `GET /api/categories/{id}` - [app/api/categories/\[id\]/route.ts](../app/api/categories/[id]/route.ts) (84 lines → ~15 lines)

### Success Criteria

- ✅ All existing tests pass (110 contract tests + 262 unit tests)
- ✅ No changes to OpenAPI spec required
- ✅ No changes to API responses (100% backward compatible)
- ✅ Code reduction: ~70% (330 lines → ~100 lines total)
- ✅ Type-safe with full TypeScript inference
- ✅ Self-documenting configuration-based approach

---

## Phase 1: Preparation & Analysis

### 1.1 Create Planning Document ✅

**Status**: Complete
**File**: `docs/refactoring/entity-detail-endpoints-dry-plan.md`

### 1.2 Snapshot Current Test Results

**Goal**: Establish baseline to ensure no regressions

**Tasks**:

- [ ] Run full test suite: `npm test`
- [ ] Run contract tests: `npm run test:contract`
- [ ] Document current passing test count
- [ ] Save test output for comparison

**Expected Results**:

```
Contract Tests: 110/110 passing
Unit Tests: 262/262 passing (56 skipped)
Total: 372 tests passing
```

### 1.3 Document Current Behavior

**Goal**: Capture exact behavior to replicate

**Tasks**:

- [ ] Document pagination calculation logic
- [ ] Document response field mapping for each endpoint
- [ ] Document orderBy differences (series uses `sequence`, others use `book.title`)
- [ ] Document any endpoint-specific includes (categories has `parent`)
- [ ] List all error messages and status codes

**Reference**: See "Current Implementation Analysis" section below

---

## Phase 2: Create Generic Helper

### 2.1 Design Type-Safe Helper Interface

**File**: `lib/api-helpers.ts` (new file)

**Tasks**:

- [ ] Define `EntityDetailConfig<TEntity>` interface
- [ ] Define `handleEntityDetailWithBooks()` function signature
- [ ] Add JSDoc documentation with examples
- [ ] Import required dependencies

**Key Design Decisions**:

1. **Generic over entity type** - Type-safe entity access
2. **Configuration object** - Declarative, self-documenting
3. **Return type inference** - TypeScript infers response type
4. **OpenAPI type integration** - Optional strict typing with generated types

**Interface Design**:

```typescript
interface EntityDetailConfig<TEntity> {
  // Prisma models
  entityModel: any; // e.g., prisma.author
  joinTableModel: any; // e.g., prisma.bookAuthor

  // Field names
  idFieldName: string; // e.g., 'authorId'
  entityName: string; // e.g., 'Author' (for error messages)

  // Response mapping
  getResponseFields: (entity: TEntity) => Record<string, any>;

  // Optional customization
  orderBy?: any; // Default: { book: { title: 'asc' } }
  entityInclude?: any; // Default: undefined
}
```

### 2.2 Implement Core Helper Logic

**File**: `lib/api-helpers.ts`

**Tasks**:

- [ ] Implement auth checking (session + mobile)
- [ ] Implement UUID normalization & validation
- [ ] Implement pagination parsing
- [ ] Implement entity fetching with optional includes
- [ ] Implement 404 handling
- [ ] Implement join table query with pagination
- [ ] Implement book transformation
- [ ] Implement pagination calculation (use `pages`, not `totalPages`)
- [ ] Implement response construction
- [ ] Implement error handling with proper logging

**Algorithm**:

```typescript
1. Check authentication (session OR mobile bearer token)
   - Return 401 if not authenticated

2. Normalize & validate UUID
   - Return 400 if invalid format

3. Parse pagination params (page, limit)
   - Default: page=1, limit=20
   - Calculate skip = (page - 1) * limit

4. Fetch main entity
   - Use config.entityModel.findUnique()
   - Include config.entityInclude if provided
   - Return 404 if not found

5. Fetch related books via join table
   - Use config.joinTableModel.findMany()
   - Filter by config.idFieldName
   - Include BOOK_INCLUDE for all book relations
   - Apply pagination (skip, take)
   - Use config.orderBy (default: book.title asc)
   - Count total with config.joinTableModel.count()

6. Transform books
   - Map join entries to books
   - Apply transformBook() to each

7. Calculate pagination
   - pages = Math.ceil(total / limit)

8. Build response
   - Spread config.getResponseFields(entity)
   - Add books array
   - Add pagination object { page, limit, total, pages }

9. Error handling
   - Catch all errors
   - Log with entity name
   - Return 500 with generic error message
```

### 2.3 Add Helper Tests

**File**: `__tests__/lib/api-helpers.test.ts` (new file)

**Tasks**:

- [ ] Test auth validation (401 for unauthenticated)
- [ ] Test UUID normalization (400 for invalid UUID)
- [ ] Test entity not found (404)
- [ ] Test successful response with all fields
- [ ] Test pagination calculation
- [ ] Test custom orderBy
- [ ] Test custom entityInclude
- [ ] Test book transformation
- [ ] Test error handling (500 on database error)

**Test Strategy**:

- Use mock Prisma client
- Test with multiple entity configurations (author, series)
- Verify response structure matches OpenAPI spec
- Test edge cases (empty results, page beyond total)

**Estimated Tests**: 15-20 unit tests

---

## Phase 3: Refactor Endpoints (One at a Time)

**Strategy**: Refactor one endpoint at a time, run tests after each, commit separately. This allows easy rollback if issues arise.

### 3.1 Refactor Authors Endpoint

**File**: `app/api/authors/[id]/route.ts`

**Tasks**:

- [ ] Import `handleEntityDetailWithBooks` from `@/lib/api-helpers`
- [ ] Replace entire GET function body with helper call
- [ ] Configure helper with author-specific settings
- [ ] Remove unused imports
- [ ] Run tests: `npm run test:contract -- -t "author"`
- [ ] Run full test suite: `npm test`
- [ ] Commit: `refactor(api): use DRY helper for authors/{id} endpoint`

**Before** (82 lines):

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
import { normalizeUuid } from '@/lib/api-utils';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // ... 75 lines of logic ...

  return NextResponse.json({
    id: author.id,
    name: author.name,
    asin: author.asin,
    books: booksWithUrls,
    pagination: { page, limit, total, pages: totalPages },
  });
}
```

**After** (~15 lines):

```typescript
import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

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

**Validation**:

- [ ] `npm run test:contract -- -t "GET /api/authors/{id}"` passes
- [ ] Response structure unchanged
- [ ] Error responses (401, 404) unchanged

### 3.2 Refactor Narrators Endpoint

**File**: `app/api/narrators/[id]/route.ts`

**Tasks**: Same as 3.1, but for narrators

**After** (~15 lines):

```typescript
import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.narrator,
    joinTableModel: prisma.bookNarrator,
    idFieldName: 'narratorId',
    entityName: 'Narrator',
    getResponseFields: (narrator) => ({
      id: narrator.id,
      name: narrator.name,
      asin: narrator.asin,
    }),
  });
}
```

**Validation**:

- [ ] `npm run test:contract -- -t "GET /api/narrators/{id}"` passes
- [ ] Commit: `refactor(api): use DRY helper for narrators/{id} endpoint`

### 3.3 Refactor Series Endpoint

**File**: `app/api/series/[id]/route.ts`

**Tasks**: Same as 3.1, but with custom `orderBy`

**After** (~15 lines):

```typescript
import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.series,
    joinTableModel: prisma.bookSeries,
    idFieldName: 'seriesId',
    entityName: 'Series',
    getResponseFields: (series) => ({
      id: series.id,
      title: series.title,
      asin: series.asin,
    }),
    // Custom: Sort by sequence instead of book title
    orderBy: [{ sequence: 'asc' }],
  });
}
```

**Special Considerations**:

- Series uses `title` field, not `name`
- Series sorts by `sequence` instead of `book.title`

**Validation**:

- [ ] `npm run test:contract -- -t "GET /api/series/{id}"` passes
- [ ] Books are ordered by sequence (1, 2, 3), not title
- [ ] Commit: `refactor(api): use DRY helper for series/{id} endpoint`

### 3.4 Refactor Categories Endpoint

**File**: `app/api/categories/[id]/route.ts`

**Tasks**: Same as 3.1, but with custom `entityInclude`

**After** (~15 lines):

```typescript
import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.category,
    joinTableModel: prisma.bookCategory,
    idFieldName: 'categoryId',
    entityName: 'Category',
    getResponseFields: (category) => ({
      id: category.id,
      name: category.name,
    }),
    // Categories include parent for breadcrumbs (though not currently used)
    entityInclude: { parent: true },
  });
}
```

**Special Considerations**:

- Categories don't return `asin` (nullable field not in response)
- Categories include `parent` relation (though not exposed in response yet)

**Validation**:

- [ ] `npm run test:contract -- -t "GET /api/categories/{id}"` passes
- [ ] Parent relationship loads but doesn't appear in response
- [ ] Commit: `refactor(api): use DRY helper for categories/{id} endpoint`

---

## Phase 4: Comprehensive Testing

### 4.1 Run Full Test Suite

**Tasks**:

- [ ] Run all unit tests: `npm test`
- [ ] Run all contract tests: `npm run test:contract`
- [ ] Compare results with Phase 1.2 baseline
- [ ] Verify identical pass/fail counts
- [ ] Verify no new warnings or errors

**Expected Results**:

```
Contract Tests: 110/110 passing (unchanged)
Unit Tests: 262/262 passing + 15-20 new helper tests
Total: 387+ tests passing
```

### 4.2 Manual API Testing

**Tasks**:

- [ ] Start dev server: `npm run dev`
- [ ] Test each endpoint with curl/Postman
- [ ] Verify response structure matches OpenAPI spec
- [ ] Test edge cases:
  - Invalid UUID format
  - Non-existent ID (404)
  - Unauthenticated request (401)
  - Pagination (page=2, limit=5)
  - Empty results (entity with no books)

**Test Script**:

```bash
# Get auth token
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq -r '.accessToken')

# Test authors endpoint
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/authors/{author-id}?page=1&limit=10"

# Test narrators endpoint
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/narrators/{narrator-id}"

# Test series endpoint
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/series/{series-id}"

# Test categories endpoint
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/categories/{category-id}"

# Test error cases
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/authors/invalid-uuid" # Should return 400

curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/authors/00000000-0000-0000-0000-000000000000" # Should return 404

curl "http://localhost:3000/api/authors/{author-id}" # No auth, should return 401
```

### 4.3 Performance Verification

**Tasks**:

- [ ] Compare response times before/after refactor
- [ ] Verify no performance regression
- [ ] Check database query counts (should be identical)

**Hypothesis**: Performance should be **identical** since helper just reorganizes existing logic.

### 4.4 Type Safety Verification

**Tasks**:

- [ ] Run TypeScript compiler: `npm run type-check`
- [ ] Verify no new type errors
- [ ] Verify IDE autocomplete works for helper config
- [ ] Verify response types are correctly inferred

---

## Phase 5: Documentation & Cleanup

### 5.1 Update API Documentation

**Files to Update**:

- [ ] [docs/architecture.md](../architecture.md) - Add section on API helper patterns
- [ ] [docs/api-quick-ref.md](../api-quick-ref.md) - No changes needed (external API unchanged)
- [ ] [docs/data-flows.md](../data-flows.md) - Update entity detail flow diagram

**New Section for architecture.md**:

```markdown
### API Helper Patterns

#### Entity Detail with Books Pattern

Browse detail endpoints (authors, narrators, series, categories) use a shared
helper function to reduce duplication:

**Helper**: `lib/api-helpers.ts` - `handleEntityDetailWithBooks()`

**Benefits**:

- Single implementation for auth, pagination, error handling
- Type-safe configuration-based approach
- Consistent behavior across all detail endpoints
- ~70% code reduction (330 lines → 100 lines)

**Usage Example**: See `app/api/authors/[id]/route.ts`
```

### 5.2 Add Code Comments

**Tasks**:

- [ ] Add JSDoc to `handleEntityDetailWithBooks()` with usage examples
- [ ] Add inline comments for complex logic in helper
- [ ] Add comments in endpoint files explaining the configuration

**Example JSDoc**:

```typescript
/**
 * Generic handler for entity detail endpoints that return paginated books.
 * Handles authentication, validation, entity fetching, book fetching, and pagination.
 *
 * @example
 * // Authors endpoint
 * return handleEntityDetailWithBooks(request, params, {
 *   entityModel: prisma.author,
 *   joinTableModel: prisma.bookAuthor,
 *   idFieldName: 'authorId',
 *   entityName: 'Author',
 *   getResponseFields: (author) => ({ id: author.id, name: author.name, asin: author.asin }),
 * });
 *
 * @example
 * // Series endpoint with custom sort
 * return handleEntityDetailWithBooks(request, params, {
 *   entityModel: prisma.series,
 *   joinTableModel: prisma.bookSeries,
 *   idFieldName: 'seriesId',
 *   entityName: 'Series',
 *   getResponseFields: (series) => ({ id: series.id, title: series.title, asin: series.asin }),
 *   orderBy: [{ sequence: 'asc' }], // Sort by series sequence
 * });
 */
```

### 5.3 Update CHANGELOG

**File**: `CHANGELOG.md` (if exists) or create refactoring summary

**Entry**:

```markdown
## [Unreleased]

### Refactored

- **API Endpoints**: Consolidated entity detail endpoints (authors, narrators, series, categories)
  into shared generic helper, reducing code duplication by ~70% (230 lines eliminated)
- **Backwards Compatible**: No changes to API contracts, responses, or OpenAPI spec
- **Maintainability**: Bug fixes and improvements now apply to all detail endpoints
```

### 5.4 Update STATUS.md

**File**: [docs/STATUS.md](../STATUS.md)

**Tasks**:

- [ ] Add refactoring to "Recent Work" section
- [ ] Note code quality improvements

---

## Phase 6: Final Validation & Merge

### 6.1 Pre-Merge Checklist

- [ ] All tests passing (unit + contract)
- [ ] TypeScript compilation successful
- [ ] No ESLint warnings
- [ ] Manual API testing complete
- [ ] Documentation updated
- [ ] Code reviewed (self-review or peer review)
- [ ] Git history clean (meaningful commits)

### 6.2 Run Full Validation Pipeline

**Tasks**:

- [ ] Run: `npm run validate:full`
- [ ] Verify all checks pass:
  - Prettier formatting
  - ESLint
  - TypeScript type-check
  - All tests
  - API contract validation

### 6.3 Create Pull Request (Optional)

**If using PR workflow**:

**Title**: `refactor: consolidate entity detail endpoints with DRY helper`

**Description**:

```markdown
## Summary

Refactors four nearly-identical entity detail endpoints to use a shared generic helper function.

## Changes

- **New**: `lib/api-helpers.ts` - Generic helper for entity detail endpoints
- **New**: `__tests__/lib/api-helpers.test.ts` - Helper unit tests
- **Modified**: `app/api/authors/[id]/route.ts` - Uses helper (82 lines → 15 lines)
- **Modified**: `app/api/narrators/[id]/route.ts` - Uses helper (82 lines → 15 lines)
- **Modified**: `app/api/series/[id]/route.ts` - Uses helper (78 lines → 15 lines)
- **Modified**: `app/api/categories/[id]/route.ts` - Uses helper (84 lines → 15 lines)
- **Updated**: Documentation (architecture.md, STATUS.md)

## Metrics

- Code reduction: ~70% (330 lines → 100 lines)
- New tests: +15-20 unit tests
- API compatibility: 100% backward compatible
- OpenAPI spec: No changes required

## Testing

- ✅ All 110 contract tests passing
- ✅ All 282+ unit tests passing
- ✅ Manual API testing complete
- ✅ Type-check passing
- ✅ No performance regression

## Breaking Changes

None - fully backward compatible

## Validation

Closes #XXX (if tracking as issue)
```

### 6.4 Merge Strategy

**Options**:

1. **Squash merge** - Single commit (recommended for clean history)
2. **Merge commit** - Preserve individual commits (good for rollback)
3. **Direct commit to main** - If not using PR workflow

**Recommended**: Squash merge with comprehensive commit message

---

## Current Implementation Analysis

### Common Code Pattern (95% identical)

**Lines 8-28** (Identical across all endpoints):

```typescript
// Auth check
const session = await getServerSession(authOptions);
const mobileUser = await getAuthUserFromRequest(request);
const user = session?.user || mobileUser;
if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

// UUID validation
const entityId = normalizeUuid(params.id);
if (!entityId) return NextResponse.json({ error: 'Invalid {entity} ID format' }, { status: 400 });

// Pagination
const searchParams = request.nextUrl.searchParams;
const page = parseInt(searchParams.get('page') || '1');
const limit = parseInt(searchParams.get('limit') || '20');
const skip = (page - 1) * limit;
```

**Lines 30-58** (90% identical, minor variations):

```typescript
// Fetch entity
const entity = await prisma.{entity}.findUnique({
  where: { id: entityId },
  include: /* optional - categories has { parent: true } */
});
if (!entity) return NextResponse.json({ error: '{Entity} not found' }, { status: 404 });

// Fetch books
const [joinEntries, total] = await Promise.all([
  prisma.{joinTable}.findMany({
    where: { {entityId}: entityId },
    skip, take: limit,
    include: { book: { include: BOOK_INCLUDE } },
    orderBy: /* varies: series uses [{ sequence: 'asc' }], others use { book: { title: 'asc' } } */
  }),
  prisma.{joinTable}.count({ where: { {entityId}: entityId } }),
]);
```

**Lines 60-76** (Identical):

```typescript
// Transform and respond
const booksWithUrls = joinEntries.map((entry) => transformBook(entry.book));
const pages = Math.ceil(total / limit);

return NextResponse.json({
  /* entity fields - varies slightly */
  books: booksWithUrls,
  pagination: { page, limit, total, pages },
});
```

### Variation Matrix

| Endpoint   | Entity Field | Join Table     | ID Field     | Sort Order   | Includes           |
| ---------- | ------------ | -------------- | ------------ | ------------ | ------------------ |
| Authors    | `name`       | `bookAuthor`   | `authorId`   | `book.title` | none               |
| Narrators  | `name`       | `bookNarrator` | `narratorId` | `book.title` | none               |
| Series     | `title`      | `bookSeries`   | `seriesId`   | `sequence`   | none               |
| Categories | `name`       | `bookCategory` | `categoryId` | `book.title` | `{ parent: true }` |

### Response Structure Differences

**Authors & Narrators**:

```json
{
  "id": "uuid",
  "name": "string",
  "asin": "string | null",
  "books": [...],
  "pagination": {...}
}
```

**Series**:

```json
{
  "id": "uuid",
  "title": "string",  ← Different field name
  "asin": "string | null",
  "books": [...],
  "pagination": {...}
}
```

**Categories**:

```json
{
  "id": "uuid",
  "name": "string",
  "books": [...],  ← No asin field
  "pagination": {...}
}
```

---

## Risk Assessment

### Risks & Mitigation

| Risk                       | Probability | Impact | Mitigation                                         |
| -------------------------- | ----------- | ------ | -------------------------------------------------- |
| **Breaking API contract**  | Low         | High   | Run contract tests after each endpoint refactor    |
| **Type safety loss**       | Low         | Medium | Use TypeScript generics, verify with type-check    |
| **Performance regression** | Very Low    | Low    | Logic unchanged, just reorganized                  |
| **Test failures**          | Low         | Medium | Refactor one endpoint at a time, commit separately |
| **Hard to understand**     | Low         | Low    | Add comprehensive JSDoc and examples               |
| **Difficult rollback**     | Very Low    | Low    | Each endpoint commits separately, easy to revert   |

### Rollback Plan

If issues arise:

1. **Single endpoint issue**: Revert specific commit for that endpoint
2. **Helper issue**: Fix helper, all endpoints benefit
3. **Critical issue**: Revert entire feature branch before merge

**Advantage**: Each endpoint refactored in separate commit makes rollback granular.

---

## Success Metrics

### Quantitative Metrics

- [ ] Code reduction: Target 70% (230 lines eliminated)
- [ ] Test coverage: Maintain or increase (currently 372 tests passing)
- [ ] New helper tests: 15-20 unit tests
- [ ] Response time: ±5% variance (no performance regression)
- [ ] Type errors: 0 new errors

### Qualitative Metrics

- [ ] Easier to understand (configuration vs. procedural code)
- [ ] Easier to maintain (single point of change)
- [ ] Easier to extend (add new entity types)
- [ ] Better developer experience (less boilerplate)

---

## Timeline Estimate

| Phase                       | Tasks                           | Time Estimate |
| --------------------------- | ------------------------------- | ------------- |
| Phase 1: Preparation        | Baseline tests, analysis        | 15 minutes    |
| Phase 2: Create Helper      | Design, implement, test         | 60 minutes    |
| Phase 3: Refactor Endpoints | 4 endpoints × 15 min each       | 60 minutes    |
| Phase 4: Testing            | Full suite, manual, performance | 30 minutes    |
| Phase 5: Documentation      | Update docs, comments           | 20 minutes    |
| Phase 6: Final Validation   | Checklist, PR, merge            | 15 minutes    |
| **Total**                   |                                 | **~3 hours**  |

**Note**: Actual time may vary based on unexpected issues. Add 50% buffer for safety → **4.5 hours total**.

---

## Post-Refactor Opportunities

### Future Enhancements (Not in Scope)

Once the helper is in place, consider these improvements:

1. **Add OpenAPI Type Validation** (Low effort)
   - Import generated types from `lib/api-types.ts`
   - Add type parameter to helper for strict response typing
   - Example: `handleEntityDetailWithBooks<AuthorDetailResponse>(...)`

2. **Add Response Caching** (Medium effort)
   - Add optional `cacheControl` config option
   - Set Cache-Control headers for immutable entities

3. **Add Filter Support** (Medium effort)
   - Extend config to support query filters
   - Example: Filter authors by genre, narrators by language

4. **Extract Other Common Patterns** (High effort)
   - Browse list endpoints (`/api/browse/*`) have similar duplication
   - Consider similar helper for list views

5. **Add Request Validation** (Medium effort)
   - Validate pagination params (max limit, valid page numbers)
   - Return 400 for invalid query params

6. **Add Telemetry/Logging** (Low effort)
   - Add optional logging for request/response
   - Track slow queries

---

## Questions & Decisions Log

### Decision 1: Use Configuration Object vs. Class Hierarchy

**Options**:

1. Configuration object (chosen)
2. Abstract base class with subclasses
3. Higher-order function factory

**Decision**: Configuration object
**Rationale**:

- More functional, less OOP boilerplate
- Easier to test (pure functions)
- Better TypeScript inference
- Simpler to understand

### Decision 2: Helper Location

**Options**:

1. `lib/api-helpers.ts` (chosen)
2. `lib/api/entity-detail-helper.ts`
3. `app/api/_helpers/entity-detail.ts`

**Decision**: `lib/api-helpers.ts`
**Rationale**:

- Consistent with existing `lib/` organization
- Can add more API helpers to same file
- Simple, flat structure

### Decision 3: Pagination Field Naming

**Options**:

1. `pages` (chosen)
2. `totalPages`

**Decision**: `pages`
**Rationale**:

- Matches OpenAPI spec validation in tests
- Shorter, clearer
- Consistent with other pagination responses

---

## References

- [CLAUDE.md](../CLAUDE.md) - Project overview
- [docs/architecture.md](../architecture.md) - System architecture
- [docs/data-validation-layers.md](../data-validation-layers.md) - OpenAPI integration
- [docs/api-quick-ref.md](../api-quick-ref.md) - API reference
- Current test suite: `npm test` and `npm run test:contract`

---

## Appendix A: Full Helper Implementation

See Phase 2.2 for detailed implementation. Key points:

**File**: `lib/api-helpers.ts`

**Exports**:

- `EntityDetailConfig<TEntity>` interface
- `handleEntityDetailWithBooks<TEntity>()` function

**Dependencies**:

- `next/server` - NextRequest, NextResponse
- `next-auth` - getServerSession
- `@/lib/auth` - authOptions, getAuthUserFromRequest
- `@/lib/db` - prisma singleton
- `@/lib/book-transformer` - BOOK_INCLUDE, transformBook
- `@/lib/api-utils` - normalizeUuid

**Lines of Code**: ~75 lines

---

## Appendix B: Test Coverage Plan

### Helper Unit Tests (`__tests__/lib/api-helpers.test.ts`)

**Test Categories**:

1. **Authentication** (3 tests)
   - Returns 401 when no session and no bearer token
   - Accepts valid session auth
   - Accepts valid bearer token auth

2. **Validation** (3 tests)
   - Returns 400 for invalid UUID format
   - Returns 400 for malformed UUID
   - Accepts valid UUID

3. **Entity Fetching** (2 tests)
   - Returns 404 when entity not found
   - Returns entity when found

4. **Book Fetching** (4 tests)
   - Fetches books with correct join table filter
   - Applies pagination correctly (skip, take)
   - Transforms books with transformBook()
   - Counts total books correctly

5. **Pagination** (3 tests)
   - Calculates pages correctly (ceil division)
   - Handles page beyond total (returns empty array)
   - Uses custom limit from query params

6. **Customization** (3 tests)
   - Uses custom orderBy when provided
   - Uses default orderBy (book.title) when not provided
   - Includes custom entity relations when provided

7. **Response Structure** (2 tests)
   - Returns correct response shape
   - Omits fields not in getResponseFields()

8. **Error Handling** (2 tests)
   - Returns 500 on database error
   - Logs error with entity name

**Total**: ~20 tests

### Contract Tests (No changes needed)

Existing contract tests already validate:

- Request/response structure
- Field validation
- OpenAPI compliance

These will continue to pass as response structure is unchanged.

---

**END OF IMPLEMENTATION PLAN**
