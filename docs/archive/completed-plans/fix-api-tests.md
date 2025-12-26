# API Tests Fix Plan

**Date**: December 25, 2025
**Status**: Investigation Complete
**Priority**: Medium (184 passing tests, 8 API tests skipped)

---

## Executive Summary

Currently, **8 API route tests** (450+ test cases) are being skipped due to Next.js Edge Runtime compatibility issues with Jest. The tests are well-written and comprehensive but fail during import because Next.js API routes use Web APIs (`Request`, `Response`, `Headers`) that aren't available in the default Jest jsdom environment.

### Current Test Status

- ✅ **200 tests passing** (components, pages, lib, scripts)
- ⏭️ **8 test suites skipped** (all API routes)
- 📊 **Test coverage**: ~450 additional test cases ready when API tests are enabled

---

## Problem Analysis

### Root Cause

Next.js 14 API routes use the **Web Fetch API** (`Request`, `Response`, `Headers`, etc.) which are:

1. Native in Edge Runtime and Node 18+
2. **NOT available in Jest's jsdom environment by default**
3. Imported at the module level when API route files load

**Error Example:**

```
ReferenceError: Request is not defined
  at Object.Request (node_modules/next/src/server/web/spec-extension/request.ts:15:34)
  at Object.<anonymous> (app/api/progress/route.ts:22:17)
```

### Why This Happens

When Jest imports an API route file for testing:

```typescript
import { GET, POST } from '@/app/api/progress/route';
```

The route file executes top-level code that references `Request`, `Response`, etc., but jsdom doesn't provide these globals.

### Current Workaround

```javascript
// jest.config.js line 28
testPathIgnorePatterns: [
  '/node_modules/',
  '/.next/',
  '__tests__/api/', // Skip API tests for now (edge runtime issues)
],
```

---

## Skipped Test Suites

### API Routes Being Skipped

1. **`__tests__/api/progress/route.test.ts`** (24 tests)
   - GET /api/progress
   - POST /api/progress
   - PUT /api/progress (clear progress)

2. **`__tests__/api/progress/batch.test.ts`** (15 tests)
   - POST /api/progress/batch (offline sync)
   - Conflict resolution tests
   - Transaction atomicity tests

3. **`__tests__/api/auth/mobile/login.test.ts`** (12 tests)
   - POST /api/auth/mobile/login
   - JWT token generation
   - Refresh token creation

4. **`__tests__/api/auth/mobile/logout.test.ts`** (8 tests)
   - POST /api/auth/mobile/logout
   - Refresh token invalidation

5. **`__tests__/api/auth/mobile/refresh.test.ts`** (10 tests)
   - POST /api/auth/mobile/refresh
   - Access token rotation

6. **`__tests__/api/auth/mobile/verify.test.ts`** (6 tests)
   - GET /api/auth/mobile/verify
   - Token validation

7. **`__tests__/api/books/chapters-performance.test.ts`** (5 tests)
   - GET /api/books/[id]?include=chapters
   - Performance benchmarks

8. **`__tests__/api/downloads/route.test.ts`** (30 tests) ⭐ **NEW**
   - GET /api/downloads (download history)
   - GET /api/downloads/[bookId]/check (eligibility)
   - POST /api/downloads/[bookId] (generate pre-signed URL)
   - Rate limiting tests (10/day, 24hr reset)

**Total**: ~110 test cases covering critical API functionality

---

## Solution Options

### Option 1: Add Web Fetch API Polyfills (Recommended) ⭐

Add polyfills for Web APIs to the Jest environment.

**Pros:**

- Minimal configuration changes
- Works with existing test code
- Most compatible with Next.js patterns
- Industry standard approach

**Cons:**

- Adds test dependencies
- Slight overhead at test startup

**Implementation:**

1. **Install packages:**

   ```bash
   npm install --save-dev whatwg-fetch node-fetch@2
   ```

2. **Update `jest.setup.js`:**

   ```javascript
   import '@testing-library/jest-dom';

   // Polyfill Web Fetch API for API route tests
   import 'whatwg-fetch';

   // Polyfill additional Web APIs
   global.Request = global.Request || require('node-fetch').Request;
   global.Response = global.Response || require('node-fetch').Response;
   global.Headers = global.Headers || require('node-fetch').Headers;
   ```

3. **Remove skip rule from `jest.config.js`:**

   ```javascript
   testPathIgnorePatterns: [
     '/node_modules/',
     '/.next/',
     // '__tests__/api/', // REMOVE THIS LINE
   ],
   ```

4. **Run tests:**
   ```bash
   npm test
   ```

**Estimated effort**: 15 minutes
**Risk**: Low

---

### Option 2: Use Edge Runtime Jest Environment

Use Next.js's experimental edge runtime environment for tests.

**Pros:**

- Exact runtime parity with production
- Native Web API support

**Cons:**

- Experimental/unstable
- Requires per-test environment configuration
- May have compatibility issues with other tests
- More complex setup

**Implementation:**

1. **Install package:**

   ```bash
   npm install --save-dev @edge-runtime/jest-environment
   ```

2. **Add environment directive to each API test:**

   ```javascript
   /**
    * @jest-environment @edge-runtime/jest-environment
    */
   import { GET, POST } from '@/app/api/progress/route';
   ```

3. **Or configure in jest.config.js:**
   ```javascript
   {
     testMatch: ['**/__tests__/api/**/*.[jt]s?(x)'],
     testEnvironment: '@edge-runtime/jest-environment',
   }
   ```

**Estimated effort**: 30-45 minutes
**Risk**: Medium (experimental package)

---

### Option 3: Mock Next.js Server Dependencies

Mock the Web APIs at the module level.

**Pros:**

- No additional dependencies
- Full control over mock behavior

**Cons:**

- Complex mock setup
- Requires maintaining mocks as Next.js evolves
- Tests may diverge from runtime behavior
- Brittle (breaks when Next.js internals change)

**Implementation:**

Update each test file to mock globals before imports:

```javascript
// Mock Web APIs before importing Next.js
global.Request = jest.fn();
global.Response = jest.fn();
global.Headers = jest.fn();

import { GET, POST } from '@/app/api/progress/route';
```

**Estimated effort**: 1-2 hours
**Risk**: High (maintenance burden)

---

### Option 4: Node Test Environment (Simple but Limited)

Switch from jsdom to node environment.

**Pros:**

- Node 18+ has native Web Fetch API
- No polyfills needed
- Fast test execution

**Cons:**

- Can't test any component/page tests
- Requires splitting test suites
- Two separate Jest configs

**Implementation:**

1. **Create `jest.config.api.js`:**

   ```javascript
   module.exports = {
     testEnvironment: 'node',
     testMatch: ['**/__tests__/api/**/*.[jt]s?(x)'],
     // ... other config
   };
   ```

2. **Add npm script:**
   ```json
   {
     "test:api": "jest --config jest.config.api.js",
     "test:ui": "jest --config jest.config.js"
   }
   ```

**Estimated effort**: 30 minutes
**Risk**: Medium (fragmented test setup)

---

## Recommended Solution

**Use Option 1: Add Web Fetch API Polyfills**

### Why This is Best

1. **Proven approach**: Used by thousands of Next.js projects
2. **Minimal changes**: Only modify 2 files
3. **Low risk**: Polyfills are stable and well-maintained
4. **Easy rollback**: Simply remove polyfills if issues arise
5. **Best compatibility**: Works with all existing tests

### Implementation Steps

Follow the steps in **Option 1** above.

### Testing the Fix

After implementing:

```bash
# Run all tests (should now include API tests)
npm test

# Verify API tests specifically
npm test -- __tests__/api/

# Check coverage
npm run test:coverage
```

Expected output:

```
Test Suites: 29 passed, 29 total  (21 current + 8 API)
Tests:       310+ passed, 310+ total (200 current + 110+ API)
```

---

## Additional Improvements

### 1. Add Test Environment Logging

Add to `jest.setup.js` for debugging:

```javascript
console.log('Jest environment:', process.env.JEST_WORKER_ID ? 'worker' : 'main');
console.log('Node version:', process.version);
console.log('Request available:', typeof Request !== 'undefined');
```

### 2. Add CI/CD Test Verification

Update GitHub Actions / CI pipeline to fail if API tests are skipped:

```yaml
- name: Run tests
  run: |
    npm test -- --verbose
    # Verify API tests ran
    npm test -- __tests__/api/ --listTests
```

### 3. Update Test Documentation

Add to `docs/testing.md`:

- How API route tests work
- Web Fetch API polyfill explanation
- Troubleshooting guide for test failures

### 4. Consider Future Migration

When Node 20+ is LTS and stable:

- Remove polyfills (native Fetch API)
- Update to pure Node test environment
- Simplify jest.setup.js

---

## Impact Assessment

### Before Fix

- ✅ 200 tests passing
- ⏭️ 110 tests skipped
- 📊 Coverage gaps in critical APIs

### After Fix

- ✅ 310+ tests passing
- ⏭️ 0 tests skipped
- 📊 Full API coverage including:
  - Authentication flows
  - Progress sync (with conflict resolution)
  - Download management (rate limiting, quotas)
  - Chapter loading performance

### Risk Mitigation

1. **Test isolation**: Polyfills only affect test environment
2. **Production unchanged**: No impact on runtime code
3. **Incremental rollout**: Can enable tests one suite at a time
4. **Easy rollback**: Revert 2 files if issues occur

---

## Timeline

- **Research & Planning**: ✅ Complete
- **Implementation**: 15 minutes
- **Validation**: 10 minutes
- **Documentation Update**: 15 minutes
- **Total**: ~40 minutes

---

## Next Steps

1. Review this plan with the team
2. Implement Option 1 (polyfills)
3. Run full test suite
4. Verify all 8 API test suites pass
5. Update test count in project documentation
6. Consider adding API test coverage to CI/CD requirements

---

## References

- [Next.js Testing Documentation](https://nextjs.org/docs/app/building-your-application/testing)
- [Jest Environment Configuration](https://jestjs.io/docs/configuration#testenvironment-string)
- [whatwg-fetch Polyfill](https://github.com/github/fetch)
- [Web Fetch API Spec](https://fetch.spec.whatwg.org/)

---

## Questions or Issues

If you encounter problems during implementation:

1. Check Node version: `node --version` (should be 18+)
2. Verify polyfill installation: `npm list whatwg-fetch`
3. Check for conflicting globals in jest.setup.js
4. Review test output for specific error messages
5. Try running tests in isolation: `npm test -- __tests__/api/progress/route.test.ts`

---

**Status**: Ready for implementation
**Assigned to**: Development team
**Priority**: Medium
**Complexity**: Low
