# iOS Authentication Deep Analysis

**Date**: January 3, 2026
**Status**: RESOLVED
**Severity**: High - Users being logged out after 1 hour unexpectedly

---

## Executive Summary

This document provides a comprehensive analysis of the BookVault iOS authentication system. Users were being logged out after approximately one hour, and audio continued playing after logout.

**Root Cause Identified**: The backend `/api/auth/mobile/refresh` endpoint was returning `{ accessToken, expiresIn }` but the OpenAPI spec (and generated Swift model) required `{ accessToken, refreshToken, expiresIn }`. The Swift JSON decoder failed on the missing `refreshToken` field, causing the refresh to fail and triggering logout.

### Resolution Summary

| Issue                         | Root Cause                                                  | Fix Applied                                                        | Status    |
| ----------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------ | --------- |
| 1-hour logout                 | Backend refresh endpoint missing `refreshToken` in response | Implemented token rotation - backend now returns new refresh token | **FIXED** |
| Audio plays after logout      | `AudioPlayerManager.stop()` not called on logout            | Added `stop()` to `clearCachesOnLogout`                            | **FIXED** |
| Potential deadlock in refresh | `execute()` used instead of `executeWithoutRefresh()`       | Changed to `executeWithoutRefresh()`                               | **FIXED** |
| Missing contract test         | No OpenAPI contract test for refresh endpoint               | Added contract test to catch spec/implementation drift             | **FIXED** |

### Confidence Assessment (Post-Resolution)

| Finding                                             | Confidence | Evidence                                      |
| --------------------------------------------------- | ---------- | --------------------------------------------- |
| Refresh endpoint missing `refreshToken` in response | **PROVEN** | Logs showed decoding error for missing key    |
| Audio doesn't stop on logout                        | **PROVEN** | Code clearly missing `stop()` call - fixed    |
| Contract test gap allowed bug                       | **PROVEN** | No contract test existed for refresh endpoint |
| Token rotation improves security                    | **HIGH**   | Industry best practice now implemented        |

---

## Table of Contents

1. [User's Actual Usage Pattern](#1-users-actual-usage-pattern)
2. [Current Architecture](#2-current-architecture)
3. [Root Cause Analysis](#3-root-cause-analysis)
4. [Fixes Applied](#4-fixes-applied)
5. [Testing & Verification](#5-testing--verification)
6. [Remaining Recommendations](#6-remaining-recommendations)
7. [Lessons Learned](#7-lessons-learned)

---

## 1. User's Actual Usage Pattern

**Critical context**: The user is NOT actively using the app for a full hour. The actual pattern is:

```
1. Open app, use for a few minutes
2. App goes to background (or phone is locked)
3. 1-2+ hours pass (app may be terminated by iOS)
4. Open app again
5. LOGGED OUT - sees login screen (WAS HAPPENING)
6. Audio from previous session may still be playing (WAS HAPPENING)
```

This is important because:

- iOS may **terminate** the app after extended background time
- On next launch, the app must **restore session from Keychain**
- The restored access token is **already expired** (1+ hours old)
- The first API call will get a **401 error**
- The refresh mechanism **should** handle this - and now it does

---

## 2. Current Architecture

### 2.1 Token System

| Token         | Purpose                            | Lifetime | Storage           |
| ------------- | ---------------------------------- | -------- | ----------------- |
| Access Token  | Sent with every API request        | 1 hour   | Keychain + memory |
| Refresh Token | Used only to get new access tokens | 30 days  | Keychain + memory |

**How it works now**: When access token expires, the app uses the 30-day refresh token to get a new access token AND a new rotated refresh token. User stays logged in for 30 days without re-entering credentials.

### 2.2 Token Rotation (NEW)

The refresh endpoint now implements **token rotation** for improved security:

```
1. Client sends current refresh token
2. Server validates token
3. Server generates new access token + new refresh token
4. Server deletes old refresh token, stores new one (atomic transaction)
5. Server returns both tokens to client
6. Client stores new refresh token for next refresh
```

Benefits:

- If a refresh token is stolen, it becomes invalid after one use
- Limits the window of opportunity for token theft
- Each refresh creates an audit trail in the database

### 2.3 Token Expiration Configuration

**Backend** (`lib/jwt.ts`, `.env`):

```
JWT_ACCESS_TOKEN_EXPIRY = 3600      # 1 hour (configurable via env var)
JWT_REFRESH_TOKEN_EXPIRY = 2592000  # 30 days
```

---

## 3. Root Cause Analysis

### 3.1 The Bug

The `/api/auth/mobile/refresh` endpoint was returning:

```json
{ "accessToken": "...", "expiresIn": 3600 }
```

But the OpenAPI spec defined (and Swift model expected):

```json
{ "accessToken": "...", "refreshToken": "...", "expiresIn": 3600 }
```

When the iOS app tried to decode the response:

```
❌ Failed to decode API response | Error: The data couldn't be read because it is missing.
❌ Missing key: refreshToken
```

This caused `APIError.decodingError` to be thrown, which triggered `clearSession()` and logged the user out.

### 3.2 Why It Wasn't Caught

1. **Unit test checked wrong assertions**: The refresh unit test verified `accessToken` and `expiresIn` but not `refreshToken`
2. **No contract test for refresh**: Unlike login, there was no OpenAPI contract test for the refresh endpoint
3. **OpenAPI spec was correct**: The spec required `refreshToken`, but implementation diverged and nothing validated it

### 3.3 Timeline of Discovery

1. User reported logout after ~1 hour
2. Debug logging was added to capture the failure point
3. Logs revealed: `Missing key: refreshToken` during decode
4. OpenAPI spec confirmed `refreshToken` was required
5. Backend was updated to return `refreshToken` (with token rotation)
6. iOS was updated to store the rotated refresh token
7. Contract test added to prevent regression

---

## 4. Fixes Applied

### 4.1 Backend: Token Rotation in Refresh Endpoint

**File**: `app/api/auth/mobile/refresh/route.ts`

```typescript
// Generate new access token
const accessToken = await generateAccessToken(tokenRecord.user.id, tokenRecord.user.email);

// Rotate refresh token for security (invalidate old, create new)
const newRefreshToken = generateRefreshToken();
const refreshTokenExpiry = parseInt(process.env.JWT_REFRESH_TOKEN_EXPIRY || '2592000');
const expiresAt = new Date(Date.now() + refreshTokenExpiry * 1000);

// Delete old token and create new one in a transaction
await prisma.$transaction([
  prisma.refreshToken.delete({ where: { id: tokenRecord.id } }),
  prisma.refreshToken.create({
    data: {
      userId: tokenRecord.user.id,
      token: newRefreshToken,
      expiresAt,
    },
  }),
]);

// Return new access token and rotated refresh token
return NextResponse.json({
  accessToken,
  refreshToken: newRefreshToken,
  expiresIn: getAccessTokenExpiry(),
});
```

### 4.2 iOS: Store Rotated Refresh Token

**File**: `ios/BookVault/Services/AuthManager.swift`

```swift
func refreshAccessToken() async -> Bool {
    // ... existing code ...

    let response = try await apiClient.refreshToken(refreshToken: refreshToken)

    // Update stored access token in keychain
    try keychain.save(key: accessTokenKey, value: response.accessToken)

    // Store the rotated refresh token (token rotation for security)
    try keychain.save(key: refreshTokenKey, value: response.refreshToken.uuidString)
    self.refreshTokenValue = response.refreshToken

    // Update APIClient's token
    apiClient.accessToken = response.accessToken

    return true
}
```

### 4.3 iOS: Stop Audio on Logout

**File**: `ios/BookVault/Services/AuthManager.swift`

```swift
var clearCachesOnLogout: () -> Void = {
    LibraryCacheManager.shared.clearCache()
    OfflineProgressStore.shared.clearCache()
    ProgressManager.shared.clearCache()
    AudioPlayerManager.shared.stop()  // ADDED: Stop audio playback on logout
}
```

### 4.4 iOS: Use executeWithoutRefresh for Refresh Endpoint

**File**: `ios/BookVault/Services/APIClient.swift`

```swift
func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response {
    // ... setup code ...

    // IMPORTANT: Use executeWithoutRefresh to avoid deadlock if refresh returns 401
    let response: RefreshToken200Response = try await executeWithoutRefresh(request: request)
    return response
}
```

### 4.5 Contract Test Added

**File**: `__tests__/api/openapi-contract.test.ts`

```typescript
describe('POST /api/auth/mobile/refresh', () => {
  testFn('should satisfy OpenAPI spec for successful token refresh', async () => {
    // First login to get a valid refresh token
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/mobile/login`, TEST_USER, ...);
    const { refreshToken } = loginResponse.data;

    // Now test the refresh endpoint
    const response = await axios.post(`${BASE_URL}/api/auth/mobile/refresh`, { refreshToken }, ...);

    expect(response.status).toBe(200);
    expect(response).toSatisfyApiSpec();  // Validates against OpenAPI spec
    expect(response.data).toHaveProperty('accessToken');
    expect(response.data).toHaveProperty('refreshToken');
    expect(response.data).toHaveProperty('expiresIn');
  });

  testFn('should satisfy OpenAPI spec for missing refresh token', async () => { ... });
  testFn('should satisfy OpenAPI spec for invalid refresh token', async () => { ... });
});
```

---

## 5. Testing & Verification

### 5.1 Successful Refresh Flow (Verified)

```
17:47:16.689 🔐 Login API response received - expiresIn: 120s
17:47:16.698 🔐 Login successful - user: test@example.com, tokenExpiresIn: 120s
... (2 minutes pass) ...
17:49:33.777 ⚠️ API Response: /api/library | Status: 401 | Body: {"error":"Unauthorized"}
17:49:33.777 🔐 Received 401 Unauthorized - access token expired, attempting refresh...
17:49:33.777 🔐 Refresh attempt starting - refreshToken: 581D5595...
17:49:33.940 ✅ API Response: /api/auth/mobile/refresh | Status: 200 | Body: {"accessToken":"...","refreshToken":"f76fcbd5-...","expiresIn":120}
17:49:33.941 🔐 Refresh API response received - new expiresIn: 120s
17:49:33.950 🔐 Rotated refresh token saved - new token: F76FCBD5...
17:49:33.951 ✅ Token refresh successful - session extended for 120s
17:49:33.951 🔐 Token refresh succeeded - retrying original request to /api/library
17:49:34.008 ✅ API Response: /api/library | Status: 200 | Body: {"books":[],"total":0}
```

### 5.2 Unit Tests

All 18 auth mobile tests pass:

- `POST /api/auth/mobile/login` - 4 tests
- `POST /api/auth/mobile/refresh` - 5 tests (including token rotation verification)
- `POST /api/auth/mobile/logout` - 4 tests
- Other auth tests - 5 tests

### 5.3 Contract Tests

New contract tests added for refresh endpoint:

- Successful refresh (validates OpenAPI spec compliance)
- Missing refresh token (400 response)
- Invalid refresh token (401 response)

---

## 6. Remaining Recommendations

These are optional improvements that would further enhance the authentication system:

### 6.1 Proactive Token Refresh (Optional - Medium Priority)

Currently the app uses **reactive refresh** (refresh on 401). Proactive refresh would prevent 401s entirely:

```swift
// Schedule refresh at 80% of token lifetime
private func scheduleTokenRefresh(expiresIn: Int) {
    refreshTimer?.invalidate()
    let refreshInterval = TimeInterval(expiresIn) * 0.8
    refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: false) { _ in
        Task { await self.refreshAccessToken() }
    }
}
```

**Why it's optional**: The reactive refresh now works correctly. Proactive refresh is a nice-to-have that reduces 401 errors but isn't critical.

### 6.2 Refresh on App Foreground (Optional - Low Priority)

Check token validity when app returns from background:

```swift
func handleAppBecameActive() {
    guard let expiresAt = tokenExpiresAt else { return }
    if Date() >= expiresAt {
        Task { await refreshAccessToken() }
    }
}
```

**Why it's optional**: The reactive refresh handles this case. This optimization would make the first request slightly faster.

### 6.3 Track Token Expiry (Optional - Low Priority)

Store `expiresIn` from login response:

```swift
let expiresIn = response.expiresIn
tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
```

**Why it's optional**: Needed only if implementing proactive refresh or foreground refresh.

---

## 7. Lessons Learned

### 7.1 OpenAPI Contract Tests Are Essential

The bug was caught by having the OpenAPI spec correct, but **not having a contract test** to enforce it. The spec said `refreshToken` was required, but the implementation didn't return it, and nothing validated this at build/test time.

**Action**: Ensure every endpoint has a contract test that calls `expect(response).toSatisfyApiSpec()`.

### 7.2 Unit Tests Should Mirror API Contracts

The unit test for refresh checked for `accessToken` and `expiresIn` but not `refreshToken`. If it had checked all required fields per the spec, this would have been caught immediately.

**Action**: When writing unit tests, verify all fields defined in the OpenAPI spec are present.

### 7.3 Debug Logging Saves Time

The comprehensive auth logging we added made it trivial to identify the exact failure point. The logs clearly showed "Missing key: refreshToken" which pointed directly to the issue.

**Action**: Keep detailed logging in authentication flows. The `DebugLogger` pattern works well.

### 7.4 Swift Codable Fails Loudly (Good!)

Swift's strict `Decodable` protocol failed immediately when a required field was missing, rather than silently returning partial data. This made the bug obvious in logs.

---

## Appendix A: File Locations

| File                                              | Purpose                             |
| ------------------------------------------------- | ----------------------------------- |
| `ios/BookVault/Services/AuthManager.swift`        | Session management, token storage   |
| `ios/BookVault/Services/APIClient.swift`          | API requests, 401 handling          |
| `ios/BookVault/Services/AudioPlayerManager.swift` | Audio playback                      |
| `app/api/auth/mobile/login/route.ts`              | Login endpoint                      |
| `app/api/auth/mobile/refresh/route.ts`            | Refresh endpoint (token rotation)   |
| `lib/jwt.ts`                                      | JWT generation, token expiry config |
| `__tests__/api/openapi-contract.test.ts`          | Contract tests                      |
| `__tests__/api/auth/mobile/refresh.test.ts`       | Refresh unit tests                  |

## Appendix B: Related PRs and Commits

- PR #TBD: Fix iOS authentication refresh and add contract tests

## Appendix C: References

- [Auth0 - Refresh Token Rotation](https://auth0.com/docs/secure/tokens/refresh-tokens/refresh-token-rotation)
- [OWASP - Token Best Practices](https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_Cheat_Sheet_for_Java.html)
