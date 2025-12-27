# OpenAPI Audit - Phase 4: Manual Edge Cases

**Date:** December 27, 2025
**Plan Reference:** [docs/openapi-mismatch-audit-plan.md](../openapi-mismatch-audit-plan.md)
**Goal:** Validate edge cases difficult to automate using manual curl testing

---

## Test Results

### 1. ✅ POST /api/auth/register - Weak Password

**Test:** Register with password < 8 characters
**Command:**

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test-weak@example.com","password":"weak"}'
```

**Expected:** HTTP 400 with error message
**Received:**

```json
HTTP Status: 400
{"error":"Password must be at least 8 characters long"}
```

**Spec Compliance:**

- ✅ Status code: 400 (matches spec)
- ✅ Error schema: `{error: string}` (matches spec)
- ✅ Description: "Invalid input (bad email format or weak password)" (semantically correct)

---

### 2. ✅ POST /api/auth/register - Duplicate Email

**Test:** Register with existing email
**Command:**

```bash
# First registration
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"duplicate-test@example.com","password":"password123"}'

# Duplicate attempt
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"duplicate-test@example.com","password":"password123"}'
```

**Expected:** HTTP 409 with error message
**Received:**

```json
HTTP Status: 409
{"error":"User with this email already exists"}
```

**Spec Compliance:**

- ✅ Status code: 409 (matches spec)
- ✅ Error schema: `{error: string}` (matches spec)
- ✅ Description: "User already exists" (semantically correct)

---

### 3. ✅ DELETE /api/library/{bookId} - Remove and Verify

**Test:** Delete book from library and verify removal
**Commands:**

```bash
# Get authentication token
curl -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Delete book
curl -X DELETE http://localhost:3000/api/library/67acc505-3e59-432e-944a-2250c6d72e4d \
  -H "Authorization: Bearer {token}"

# Verify removal
curl -X GET http://localhost:3000/api/library \
  -H "Authorization: Bearer {token}"
```

**Expected:** HTTP 200 with success message, book removed from library
**Received:**

```json
HTTP Status: 200
{"message":"Book removed from library"}
```

**Verification:**

- ✅ Library count before: 2 books
- ✅ Library count after: 1 book
- ✅ Deleted book no longer appears in GET /api/library

**Spec Compliance:**

- ✅ Status code: 200 (matches spec)
- ✅ Response schema: `{message: string}` (matches spec)
- ✅ Message: "Book removed from library" (exact match with spec example)
- ✅ Functional behavior: Book actually removed from library

---

### 4. ✅ Error Message Wording Validation

**Verification Results:**

| Endpoint                                | Status | Expected Schema     | Actual Schema       | Match |
| --------------------------------------- | ------ | ------------------- | ------------------- | ----- |
| POST /api/auth/register (weak password) | 400    | `{error: string}`   | `{error: string}`   | ✅    |
| POST /api/auth/register (duplicate)     | 409    | `{error: string}`   | `{error: string}`   | ✅    |
| DELETE /api/library/{bookId}            | 200    | `{message: string}` | `{message: string}` | ✅    |

**Code Review:**

1. **Register endpoint** ([app/api/auth/register/route.ts](../../app/api/auth/register/route.ts))
   - ✅ Returns `{error: string}` for 400 responses
   - ✅ Returns `{error: string}` for 409 responses
   - ✅ Returns `{message: string, user: User}` for 201 responses

2. **Library DELETE endpoint** ([app/api/library/[bookId]/route.ts](../../app/api/library/%5BbookId%5D/route.ts))
   - ✅ Returns `{message: string}` for 200 responses
   - ✅ Returns `{error: string}` for 404 responses
   - ✅ Returns `{error: string}` for 500 responses

---

## Summary

**All edge cases validated successfully:**

- ✅ Weak password validation returns correct 400 status
- ✅ Duplicate email validation returns correct 409 status
- ✅ Library deletion works and verifies correctly
- ✅ All error messages match OpenAPI spec schema
- ✅ All success messages match OpenAPI spec schema
- ✅ Response structures comply with spec definitions

**No issues found.** The API implementation correctly handles all tested edge cases according to the OpenAPI specification.

---

## Implementation Files Verified

- [app/api/auth/register/route.ts](../../app/api/auth/register/route.ts) - User registration endpoint
- [app/api/library/[bookId]/route.ts](../../app/api/library/%5BbookId%5D/route.ts) - Library management endpoint
- [docs/api/openapi.yaml](openapi.yaml) - OpenAPI specification (source of truth)

---

## Next Steps

Phase 4 is complete. All manual edge cases have been validated and documented.

**Recommendation:** No changes needed. All endpoints comply with the OpenAPI specification.
