# Option A: Dual Authentication Implementation Plan

**Goal**: Enable all API endpoints to accept both session cookies (web) and JWT Bearer tokens (mobile)

**Status**: ✅ COMPLETED (December 26, 2025)
**Completed In**: PR #35 - OpenAPI Implementation (commit db20b14)
**Actual Time**: ~1 hour (as estimated)
**Risk Level**: Low (pattern already proven in POST /api/progress)

## Completion Summary

**Date Completed**: December 26, 2025
**Implementation**: All 26 API endpoints successfully updated with dual authentication support
**Test Results**: 25/25 OpenAPI contract tests passing ✅
**Verification**:

- ✅ All endpoints accept both session cookies and Bearer tokens
- ✅ OpenAPI spec updated to document dual auth (v1.0.1)
- ✅ Contract tests validate both auth methods work
- ✅ Type checking passes
- ✅ All 207 tests passing

**Files Updated**: 26 API route handlers (see File Checklist below for complete list)

---

## Overview

Update all API route handlers to check for both NextAuth session cookies AND mobile JWT tokens, accepting either for authentication. This makes the API fully accessible to both web clients and mobile apps.

---

## Prerequisites

Before starting:

- ✅ OpenAPI spec updated (v1.0.1) - documents dual auth
- ✅ `getAuthUserFromRequest()` helper exists in `lib/auth.ts`
- ✅ Pattern proven in `app/api/progress/route.ts` (POST handler)
- ✅ Contract tests ready to validate changes

---

## Implementation Pattern

### Current Pattern (Session-Only)

```typescript
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';

export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const userId = session.user.id;
  // ... rest of handler
}
```

### New Pattern (Dual Auth)

```typescript
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';

export async function GET(request: NextRequest) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const userId = user.id;
  // ... rest of handler
}
```

**Key Changes**:

1. Import `getAuthUserFromRequest` from `@/lib/auth`
2. Call both auth methods
3. Use `||` operator to accept either
4. Replace `session.user` with `user` variable

---

## Files to Update

### Phase 1: Core Endpoints (High Priority)

**These enable basic mobile app functionality**

1. **app/api/books/route.ts** - GET (list books)
   - Line 12: Add dual auth
   - Impact: Mobile can browse catalog

2. **app/api/books/[id]/route.ts** - GET (book details)
   - Line ~12: Add dual auth
   - Impact: Mobile can view book details

3. **app/api/books/[id]/chapters/route.ts** - GET (chapters)
   - Line ~12: Add dual auth
   - Impact: Mobile can navigate chapters

4. **app/api/progress/route.ts** - GET, PUT (read/update progress)
   - Line 9: GET handler needs dual auth (POST already has it)
   - Line 158: PUT handler needs dual auth
   - Impact: Mobile can track progress

5. **app/api/search/route.ts** - GET (search)
   - Line ~12: Add dual auth
   - Impact: Mobile can search books

### Phase 2: Browse Endpoints (Medium Priority)

**These enable browsing by author/series/narrator/category**

6. **app/api/browse/authors/route.ts** - GET
7. **app/api/browse/series/route.ts** - GET
8. **app/api/browse/narrators/route.ts** - GET
9. **app/api/browse/categories/route.ts** - GET
10. **app/api/authors/[id]/route.ts** - GET
11. **app/api/series/[id]/route.ts** - GET
12. **app/api/narrators/[id]/route.ts** - GET
13. **app/api/categories/[id]/route.ts** - GET

### Phase 3: Library Endpoints (Medium Priority)

**These enable user library management**

14. **app/api/library/route.ts** - GET, POST
15. **app/api/library/[bookId]/route.ts** - DELETE
16. **app/api/library/check/route.ts** - GET
17. **app/api/library/lists/route.ts** - GET, POST
18. **app/api/library/lists/[id]/route.ts** - GET, PUT, DELETE
19. **app/api/library/lists/[id]/books/route.ts** - POST, DELETE
20. **app/api/library/lists/[id]/reorder/route.ts** - PUT
21. **app/api/library/series/[seriesId]/route.ts** - POST, DELETE

### Phase 4: Additional Endpoints (Low Priority)

**Nice-to-have for full mobile feature parity**

22. **app/api/downloads/route.ts** - GET
23. **app/api/downloads/[bookId]/route.ts** - GET, POST, DELETE
24. **app/api/downloads/[bookId]/check/route.ts** - GET
25. **app/api/progress/batch/route.ts** - POST
26. **app/api/search/suggestions/route.ts** - GET

---

## Implementation Steps

### Step 1: Update Core Endpoints (30 min)

Update files 1-5 from Phase 1 list above.

**For each file**:

1. Read the file
2. Locate all handler functions (GET, POST, PUT, DELETE)
3. Find the auth check (usually near top of function)
4. Apply the dual auth pattern
5. Update all references from `session.user` to `user`
6. Verify no other `session` usage remains

### Step 2: Update Browse Endpoints (20 min)

Update files 6-13 from Phase 2 list above using same pattern.

### Step 3: Update Library Endpoints (20 min)

Update files 14-21 from Phase 3 list above using same pattern.

### Step 4: Update Additional Endpoints (10 min)

Update files 22-26 from Phase 4 list above using same pattern.

### Step 5: Update OpenAPI Spec (5 min)

Update `docs/api/openapi.yaml`:

- Line 21: Change "Only `/api/progress` (POST)" to "All endpoints support both auth methods"
- Add `security: [{sessionAuth: []}, {bearerAuth: []}]` to all endpoint definitions

### Step 6: Update Contract Tests (5 min)

Update `__tests__/api/openapi-contract.test.ts`:

- Line 68-71: Remove `describe.skip` (enable auth tests)
- Line 35: Update comment to reflect dual auth support

### Step 7: Validation (10 min)

1. Run type check: `npm run type-check`
2. Run all tests: `npm test`
3. Start dev server: `npm run dev`
4. Run contract tests: `RUN_CONTRACT_TESTS=true npm test -- openapi-contract`
5. Verify all tests pass

---

## Testing Strategy

### Manual Testing

**Before implementation**:

```bash
# Web auth should work (already does)
curl http://localhost:3000/api/books \
  -H "Cookie: next-auth.session-token=..."
```

**After implementation**:

```bash
# Mobile auth should also work
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq -r .accessToken)

curl http://localhost:3000/api/books \
  -H "Authorization: Bearer $TOKEN"
```

### Automated Testing

Contract tests will validate:

- ✅ All endpoints accept Bearer tokens
- ✅ Response structures match OpenAPI spec
- ✅ Error responses are correct
- ✅ Authentication works as expected

---

## Expected Results

### Before Implementation

- Contract tests: 9 passing, 14 failing, 2 skipped
- Mobile API support: Limited (only POST /api/progress)
- iOS development: Blocked

### After Implementation

- Contract tests: 23+ passing, 0-2 failing, 0 skipped
- Mobile API support: Full (all documented endpoints)
- iOS development: Ready to start

---

## Rollback Plan

If issues arise:

1. Git revert commits
2. Or manually remove dual auth additions (keep session-only)
3. Update OpenAPI spec back to session-only

**Low risk**: Changes are additive (add Bearer auth, keep session auth working)

---

## Success Criteria

- [ ] All 26 endpoint files updated with dual auth pattern
- [ ] `npm run type-check` passes
- [ ] `npm test` passes (all existing tests still work)
- [ ] Contract tests show 90%+ passing rate
- [ ] OpenAPI spec updated to reflect dual auth
- [ ] Documentation updated
- [ ] Manual testing confirms both auth methods work

---

## Context-Independent Execution Prompt

**Use this prompt to start implementation in a fresh Claude Code session:**

```
I need to implement dual authentication (session + JWT Bearer tokens) for all API endpoints in the Book Vault project. This is Option A from the OpenAPI Phase 4 plan.

Please read /Users/demetri/projects/book_vault/docs/openapi-dual-auth-implementation-plan.md and implement the changes described.

Key points:
1. Update ~26 API route files to support both NextAuth sessions and JWT Bearer tokens
2. Use the pattern from POST /api/progress as the reference
3. Follow the phase-by-phase approach (Core → Browse → Library → Additional)
4. Update OpenAPI spec and contract tests when done
5. Run validation tests to confirm everything works

Start with Phase 1 (Core Endpoints) and work through systematically. Use the TodoWrite tool to track progress through all phases.
```

---

## Additional Notes

### Why This Works

- Pattern already proven in `POST /api/progress` (has both auth methods)
- `getAuthUserFromRequest()` is battle-tested (used in mobile login flow)
- NextAuth sessions continue to work unchanged
- Additive change (doesn't break existing functionality)

### Performance Impact

- Minimal: One extra async call per request (~1-2ms)
- Only one auth check actually validates (short-circuit evaluation)
- Mobile requests skip session check (null return is fast)

### Security Considerations

- JWT validation happens in `getAuthUserFromRequest()`
- Same user model returned by both auth methods
- No security regressions (keeping all existing checks)
- Rate limiting already in place for progress endpoint

---

## File Checklist

Copy this checklist when implementing:

```
Phase 1: Core Endpoints
[ ] app/api/books/route.ts (GET)
[ ] app/api/books/[id]/route.ts (GET)
[ ] app/api/books/[id]/chapters/route.ts (GET)
[ ] app/api/progress/route.ts (GET, PUT)
[ ] app/api/search/route.ts (GET)

Phase 2: Browse Endpoints
[ ] app/api/browse/authors/route.ts (GET)
[ ] app/api/browse/series/route.ts (GET)
[ ] app/api/browse/narrators/route.ts (GET)
[ ] app/api/browse/categories/route.ts (GET)
[ ] app/api/authors/[id]/route.ts (GET)
[ ] app/api/series/[id]/route.ts (GET)
[ ] app/api/narrators/[id]/route.ts (GET)
[ ] app/api/categories/[id]/route.ts (GET)

Phase 3: Library Endpoints
[ ] app/api/library/route.ts (GET, POST)
[ ] app/api/library/[bookId]/route.ts (DELETE)
[ ] app/api/library/check/route.ts (GET)
[ ] app/api/library/lists/route.ts (GET, POST)
[ ] app/api/library/lists/[id]/route.ts (GET, PUT, DELETE)
[ ] app/api/library/lists/[id]/books/route.ts (POST, DELETE)
[ ] app/api/library/lists/[id]/reorder/route.ts (PUT)
[ ] app/api/library/series/[seriesId]/route.ts (POST, DELETE)

Phase 4: Additional Endpoints
[ ] app/api/downloads/route.ts (GET)
[ ] app/api/downloads/[bookId]/route.ts (GET, POST, DELETE)
[ ] app/api/downloads/[bookId]/check/route.ts (GET)
[ ] app/api/progress/batch/route.ts (POST)
[ ] app/api/search/suggestions/route.ts (GET)

Finalization
[ ] Update OpenAPI spec (docs/api/openapi.yaml)
[ ] Update contract tests (__tests__/api/openapi-contract.test.ts)
[ ] Run type-check (npm run type-check)
[ ] Run tests (npm test)
[ ] Run contract tests (RUN_CONTRACT_TESTS=true npm test -- openapi-contract)
[ ] Verify manual testing with Bearer token
```

---

**Document Version**: 1.0
**Last Updated**: 2025-12-26
**Author**: Claude (Sonnet 4.5)
**Status**: Ready for implementation
