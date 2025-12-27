# OpenAPI Mismatch Audit Plan

**Last Updated**: December 27, 2025
**Purpose**: Systematically identify and fix mismatches between OpenAPI spec and backend implementation

## Known Fixed Mismatches

The following mismatches have been identified and fixed:

1. **POST /api/auth/mobile/logout** - Returned `{success: true}` instead of `{message: "..."}`
2. **GET /api/books/{id}** - Author objects included `createdAt` field not in spec (line 89)
3. **GET /api/library** - Missing `total` field when library is empty (line 27)

## Mismatch Classification

When a mismatch is found, determine resolution using this decision tree:

1. **Spec is wrong** → Update spec to match implementation
   - Implementation is widely used
   - Changing implementation would break mobile app or existing clients
   - Implementation is more correct/complete

2. **Implementation is wrong** → Fix implementation to match spec
   - Spec was intentionally designed this way
   - Implementation missed a requirement
   - Spec represents the contract we want to maintain

3. **Both need adjustment** → Update both
   - Found a better approach
   - Security or performance issue with current design

**Default rule**: Prefer fixing implementation to preserve API contract stability.

---

## Testing Approach

**Primary strategy**: Automated contract validation using existing `jest-openapi` infrastructure

**Why jest-openapi**:

- Already integrated and working (23 tests passing)
- Minimal setup required
- Validates responses against OpenAPI schemas automatically
- Compatible with current stack (Jest + TypeScript)

**Limitations**:

- Requires server running (integration tests)
- Can't test destructive operations safely
- Limited to response validation (not request validation)

**For uncovered cases**: Manual testing with curl + careful inspection

---

## Phase 1: Expand Automated Coverage (Core CRUD)

**Objective**: Add contract tests for endpoints missing automated validation

**Endpoints in scope**:

- ✅ Covered: `/api/books`, `/api/books/{id}`, `/api/books/{id}/chapters`
- ✅ Covered: `/api/progress` (GET, POST, PUT)
- ✅ Covered: `/api/search`, `/api/browse/*`, `/api/authors/{id}`
- ✅ Covered: `/api/library` (GET, POST, DELETE)
- ✅ Covered: `/api/auth/mobile/*`
- ⚠️ **Missing**: `/api/series/{id}`, `/api/narrators/{id}`, `/api/categories/{id}`
- ⚠️ **Missing**: `/api/auth/register`

**Method**: Extend `__tests__/api/openapi-contract.test.ts` with new test cases

**Commands**:

```bash
# 1. Add test cases to openapi-contract.test.ts for missing endpoints
# 2. Run contract tests
npm run test:contract

# 3. Review failures
npm test -- openapi-contract --verbose
```

**Output/Evidence**:

- Jest test results showing pass/fail for each endpoint
- Failed assertion details (schema violations)
- Coverage report (which endpoints tested vs. spec)

**Acceptance criteria**:

- All endpoints in OpenAPI spec have at least one success case test
- All documented error codes (400, 401, 404) have tests
- Zero schema validation failures

**Stop point**: Commit when all tests pass or all failures documented

---

## Phase 2: Field-Level Validation (Deep Inspection)

**Objective**: Verify response objects don't include extra fields not in spec

**Context**: The `authors.createdAt` bug (Phase 1 fix #2) was missed because jest-openapi allows **extra fields** by default. We need to catch these.

**Endpoints in scope**: All endpoints that return complex objects

- `/api/books/{id}` - Book with nested authors/narrators/series/categories
- `/api/authors/{id}` - Author with books
- `/api/series/{id}` - Series with books
- `/api/browse/*` - List endpoints with nested objects

**Method**: Write custom field validators in tests

**Example test pattern**:

```typescript
// Add to each test that validates complex objects
const allowedBookFields = [
  'id',
  'asin',
  'title',
  'description',
  'runtimeMinutes',
  'releaseDate',
  'publisher',
  'coverUrl',
  'audioUrl',
  'authors',
  'narrators',
  'series',
  'categories',
];

expect(Object.keys(response.data)).toEqual(expect.arrayContaining(allowedBookFields));

// Check no extra fields
const extraFields = Object.keys(response.data).filter((key) => !allowedBookFields.includes(key));
expect(extraFields).toEqual([]);
```

**Commands**:

```bash
# 1. Update tests with field validators
# 2. Run contract tests
npm run test:contract

# 3. Generate OpenAPI types and compare
npm run api:generate:ts
# Inspect lib/api-types.ts for expected fields
```

**Output/Evidence**:

- List of endpoints with extra fields (field name, endpoint, example value)
- Updated test assertions
- Git diff showing field removals in implementation

**Acceptance criteria**:

- Zero extra fields in any response object
- All nested objects validated (authors, narrators, series, categories)
- Tests document expected fields explicitly

**Stop point**: Commit when all extra fields removed and tests pass

---

## Phase 3: Unspecified Endpoints (Implementation Drift)

**Objective**: Find endpoints implemented but not in OpenAPI spec

**Context**: Found several endpoints in `app/api/` not in spec:

- `/api/downloads/*` (3 endpoints)
- `/api/health`
- `/api/library/check`
- `/api/library/lists/*` (4 endpoints)
- `/api/library/series/{seriesId}`
- `/api/progress/batch`
- `/api/search/suggestions`
- `/api/user/password`
- `/api/audio/[...path]` (media streaming, not REST)
- `/api/images/[...path]` (media streaming, not REST)

**Method**: Compare route files vs. OpenAPI paths

**Commands**:

```bash
# 1. Extract all paths from OpenAPI spec
grep "^  /api/" docs/api/openapi.yaml | sort > /tmp/spec-paths.txt

# 2. Extract all route paths from app/api
find app/api -type f -name "route.ts" | \
  sed 's|app/api/||; s|/route.ts||; s|\[id\]|{id}|g; s|\[bookId\]|{bookId}|g; s|\[seriesId\]|{seriesId}|g' | \
  sed 's|^|/api/|' | sort > /tmp/impl-paths.txt

# 3. Compare
comm -13 /tmp/spec-paths.txt /tmp/impl-paths.txt
# Output = endpoints in implementation but not spec
```

**Decision matrix for each unspecified endpoint**:

| Endpoint                         | Used by?        | Action                         |
| -------------------------------- | --------------- | ------------------------------ |
| `/api/downloads/*`               | iOS app         | Add to spec                    |
| `/api/health`                    | Monitoring      | Add to spec (simple)           |
| `/api/library/check`             | Web/iOS         | Add to spec                    |
| `/api/library/lists/*`           | Web             | Add to spec                    |
| `/api/library/series/{seriesId}` | Web             | Add to spec                    |
| `/api/progress/batch`            | iOS app         | Add to spec                    |
| `/api/search/suggestions`        | Web             | Add to spec                    |
| `/api/user/password`             | Web             | Add to spec                    |
| `/api/audio/*`, `/api/images/*`  | Media streaming | Document separately (not REST) |

**Output/Evidence**:

- List of unspecified endpoints with usage notes
- Updated OpenAPI spec with new endpoints
- Contract tests for newly added endpoints

**Acceptance criteria**:

- All REST endpoints documented in OpenAPI spec
- Non-REST endpoints (media streaming) noted in separate doc
- Contract tests pass for newly documented endpoints

**Stop point**: Commit when spec is complete and tests pass

---

## Phase 4: Manual Edge Cases (Auth & Side Effects)

**Objective**: Test scenarios difficult to automate (session state, destructive operations)

**Endpoints in scope**:

- `/api/auth/register` - Can't repeat with same email
- `/api/library` DELETE - Side effects on user state
- `/api/progress` PUT - Idempotency checks
- Any endpoint with complex validation (password strength, etc.)

**Method**: Manual curl tests with fresh test users

**Example curl tests**:

```bash
# Test 1: Register user with weak password
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"weak@test.com","password":"123"}' \
  | jq .

# Expected: 400 with error about password length (per spec: minLength: 8)

# Test 2: Register duplicate email
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq .

# Expected: 409 with "User already exists" error

# Test 3: Delete book from library, verify removal
TOKEN="..." # Get from login
curl -X DELETE http://localhost:3000/api/library/{bookId} \
  -H "Authorization: Bearer $TOKEN" \
  | jq .

# Expected: 200 with message "Book removed from library"

# Then verify it's gone
curl -X GET http://localhost:3000/api/library \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.books[] | select(.id == "bookId")'

# Expected: No output (book not in results)
```

**Output/Evidence**:

- Markdown checklist of manual tests with results
- Screenshots or curl output for each test
- List of mismatches found (status codes, error messages, response shapes)

**Acceptance criteria**:

- All edge cases tested manually
- Error messages match spec wording
- HTTP status codes correct per spec
- Side effects verified (state changes persist)

**Stop point**: Document results and commit any fixes

---

## Phase 5: Generated Types Validation (TypeScript Contract)

**Objective**: Ensure `lib/api-types.ts` matches actual responses

**Context**: Types are auto-generated from OpenAPI spec. If implementations don't match, TypeScript won't catch it at runtime.

**Method**: Add runtime type validation in tests

**Approach**:

```typescript
// Use zod to create runtime validators from OpenAPI schemas
import { paths } from '@/lib/api-types';
import { z } from 'zod';

// Example: Validate book response matches generated types
type BookResponse =
  paths['/api/books/{id}']['get']['responses']['200']['content']['application/json'];

const bookSchema = z.object({
  id: z.string().uuid(),
  asin: z.string(),
  title: z.string(),
  // ... full schema matching generated type
});

test('book response matches generated types', () => {
  const response = await fetch('/api/books/123');
  const data = await response.json();

  // This will throw if data doesn't match schema
  bookSchema.parse(data);
});
```

**Commands**:

```bash
# 1. Generate types from spec
npm run api:generate:ts

# 2. Create zod validators matching generated types
# (Manual coding in test file)

# 3. Run validation tests
npm test -- api-types-validation
```

**Output/Evidence**:

- Zod schema validators for key response types
- Test results showing type mismatches (if any)
- List of endpoints where responses don't match generated types

**Acceptance criteria**:

- All tested endpoints pass runtime type validation
- No mismatches between OpenAPI types and actual responses
- Critical endpoints (books, progress, auth) have runtime validators

**Stop point**: Commit when validators pass for all tested endpoints

---

## Phase 6: CI/CD Integration (Prevent Future Drift)

**Objective**: Automate mismatch detection in CI pipeline

**Tasks**:

1. Add contract tests to PR checks (already done via `.github/workflows/api.yml`)
2. Add field validation tests (from Phase 2)
3. Add spec coverage check (fail if endpoints missing from spec)
4. Add generated types drift check (fail if `lib/api-types.ts` stale)

**Method**: Update CI workflow

**Commands**:

```bash
# 1. Update .github/workflows/api.yml to include:
npm run api:check-drift  # Already included
npm run test:contract    # Already included

# 2. Add new check: endpoint coverage
npm run api:check-coverage  # New script to create

# 3. Test CI locally
act -j api-validation  # If using 'act' to test GitHub Actions
```

**New script to add to `package.json`**:

```json
{
  "scripts": {
    "api:check-coverage": "tsx scripts/check-endpoint-coverage.ts"
  }
}
```

**Script pseudocode** (`scripts/check-endpoint-coverage.ts`):

```typescript
// 1. Parse OpenAPI spec to extract all paths
// 2. Scan app/api for all route.ts files
// 3. Compare: fail if routes exist without spec entry
// 4. Compare: warn if spec entries without route files
// 5. Exit 1 if any uncovered endpoints found
```

**Output/Evidence**:

- Updated CI workflow file
- New coverage check script
- Green CI checks on test PR

**Acceptance criteria**:

- CI fails if contract tests fail
- CI fails if generated types are stale
- CI fails if new endpoints added without spec update
- Local `npm run validate:full` mirrors CI checks

**Stop point**: Commit when CI checks are comprehensive and passing

---

## Estimated Effort

| Phase     | Estimated Time | Complexity                  |
| --------- | -------------- | --------------------------- |
| Phase 1   | 1-2 hours      | Low (extend existing tests) |
| Phase 2   | 2-3 hours      | Medium (custom validators)  |
| Phase 3   | 1-2 hours      | Low (spec updates)          |
| Phase 4   | 1 hour         | Low (manual testing)        |
| Phase 5   | 2-3 hours      | Medium (zod schemas)        |
| Phase 6   | 1 hour         | Low (CI config)             |
| **Total** | **8-12 hours** | -                           |

---

## Success Metrics

At completion, we will have:

✅ Contract tests for 100% of OpenAPI spec endpoints
✅ Zero extra fields in response objects (strict mode)
✅ All implemented endpoints documented in spec
✅ Manual validation of edge cases complete
✅ Runtime type validation for critical endpoints
✅ CI enforcement preventing future drift
✅ Documentation of mismatch resolution decisions

---

## Notes

- **Incremental approach**: Each phase is independently valuable and committable
- **No big rewrites**: Fixes are surgical (remove fields, update specs)
- **Automation-first**: Only manual testing where automation is infeasible
- **CI enforcement**: Prevents regressions after cleanup
- **Token-efficient**: Minimal codebase scanning, targeted file reads only
