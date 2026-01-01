# iOS Token Refresh Implementation Plan

**Created**: December 31, 2025
**Status**: Ready for Implementation
**Priority**: HIGH - Users are being logged out after 1 hour

## Problem Statement

iOS users are being logged out after exactly 1 hour of usage. This happens because:

1. Backend JWT access tokens expire after 3600 seconds (1 hour) by default
2. The iOS app receives `expiresIn` from login/refresh responses but **ignores it**
3. The `refreshAccessToken()` method exists in AuthManager but is **never called**
4. On 401 errors, APIClient immediately calls `forceLogout()` without attempting refresh

## Current Code Analysis

### Backend Token Configuration

**File**: `lib/jwt.ts` (line 26)

```typescript
const expiresIn = process.env.JWT_ACCESS_TOKEN_EXPIRY || '3600'; // Default 1 hour
```

**Response includes expiry**: Login and refresh responses include `expiresIn: 3600` (seconds).

### iOS Code Issues

**1. AuthManager.login() - Line 67-92**: Stores tokens but ignores `expiresIn`

```swift
let response = try await apiClient.login(email: email, password: password)
try keychain.save(key: accessTokenKey, value: response.accessToken)
try keychain.save(key: refreshTokenKey, value: response.refreshToken.uuidString)
// ❌ response.expiresIn is received but NOT stored or used
```

**2. AuthManager.refreshAccessToken() - Line 124-141**: Exists but never called

```swift
func refreshAccessToken() async -> Bool {
    guard let refreshToken = refreshTokenValue else { return false }
    let response = try await apiClient.refreshToken(refreshToken: refreshToken)
    try keychain.save(key: accessTokenKey, value: response.accessToken)
    return true
}
// ❌ This method is never invoked anywhere in the codebase
```

**3. APIClient.execute() - Line 206-209**: On 401, immediately logs out

```swift
case 401:
    forceLogoutHandler()  // ❌ No attempt to refresh first
    throw APIError.unauthorized
```

---

## Solution Overview

Implement automatic token refresh with two mechanisms:

1. **Reactive Refresh**: On 401 error, try to refresh token before logging out
2. **Proactive Refresh** (optional): Refresh token before it expires

### Architecture

```
┌─────────────┐     API Call      ┌─────────────┐
│  APIClient  │ ──────────────────►│   Backend   │
└──────┬──────┘                    └──────┬──────┘
       │                                  │
       │ 401 Unauthorized                 │
       ◄──────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  Is this a retry after refresh?          │
│  ┌─────────────────────────────────────┐ │
│  │ NO: Try AuthManager.refreshToken() │ │
│  │ YES: forceLogout() (refresh failed) │ │
│  └─────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Reactive Token Refresh on 401

**Goal**: When API returns 401, try refreshing the token before logging out.

#### 1.1 Add retry flag to APIClient

**File**: `ios/BookVault/Services/APIClient.swift`

Add a thread-safe mechanism to prevent infinite retry loops:

```swift
/// Token refresh state to prevent infinite loops
private var isRefreshingToken = false

/// Lock for thread-safe token refresh
private let refreshLock = NSLock()
```

#### 1.2 Modify execute() to attempt refresh on 401

**File**: `ios/BookVault/Services/APIClient.swift`

Replace the current 401 handling (lines 206-209):

```swift
case 401:
    // Attempt token refresh before forcing logout
    if await attemptTokenRefresh() {
        // Retry the original request with new token
        var retryRequest = request
        if let newToken = accessToken {
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        }
        return try await executeWithoutRefresh(request: retryRequest)
    } else {
        // Refresh failed - force logout
        forceLogoutHandler()
        throw APIError.unauthorized
    }
```

#### 1.3 Add helper methods for token refresh

**File**: `ios/BookVault/Services/APIClient.swift`

```swift
/// Attempt to refresh the access token
/// Returns true if refresh succeeded, false otherwise
private func attemptTokenRefresh() async -> Bool {
    // Use lock to prevent multiple concurrent refresh attempts
    refreshLock.lock()
    defer { refreshLock.unlock() }

    // If already refreshing, wait for it to complete
    if isRefreshingToken {
        return false // Let the other caller handle it
    }

    isRefreshingToken = true
    defer { isRefreshingToken = false }

    // Call AuthManager to refresh the token
    return await AuthManager.shared.refreshAccessToken()
}

/// Execute request without attempting refresh (used for retry after refresh)
private func executeWithoutRefresh<T: Decodable>(request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200...299:
        return try decoder.decode(T.self, from: data)
    case 401:
        // Second 401 after refresh - definitely log out
        forceLogoutHandler()
        throw APIError.unauthorized
    case 404:
        throw APIError.notFound
    default:
        let errorMessage = try? decoder.decode([String: String].self, from: data)
        throw APIError.serverError(httpResponse.statusCode, errorMessage?["error"])
    }
}
```

#### 1.4 Update AuthManager.refreshAccessToken()

**File**: `ios/BookVault/Services/AuthManager.swift`

Enhance to also update APIClient's token:

```swift
/// Refresh the access token using the refresh token
func refreshAccessToken() async -> Bool {
    guard let refreshToken = refreshTokenValue else {
        DebugLogger.auth("No refresh token available")
        return false
    }

    do {
        DebugLogger.auth("Attempting token refresh...")
        let response = try await apiClient.refreshToken(refreshToken: refreshToken)

        // Update stored access token
        try keychain.save(key: accessTokenKey, value: response.accessToken)

        // Update APIClient's token
        var mutableApiClient = apiClient
        mutableApiClient.accessToken = response.accessToken

        DebugLogger.auth("Token refresh successful")
        return true
    } catch {
        DebugLogger.auth("Token refresh failed: \(error.localizedDescription)")
        // If refresh fails, clear session (refresh token may be revoked)
        clearSession()
        return false
    }
}
```

---

### Phase 2: Store Token Expiry (Optional Enhancement)

**Goal**: Track when token expires for potential proactive refresh.

#### 2.1 Add expiry storage to AuthManager

**File**: `ios/BookVault/Services/AuthManager.swift`

```swift
private let tokenExpiryKey = "com.bookvault.tokenExpiry"

/// Store token expiry timestamp
private func storeTokenExpiry(expiresIn: Int) {
    let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
    let expiryString = ISO8601DateFormatter().string(from: expiryDate)
    try? keychain.save(key: tokenExpiryKey, value: expiryString)
}

/// Check if token is expired or expiring soon (within 5 minutes)
func isTokenExpiringSoon() -> Bool {
    guard let expiryString = keychain.load(key: tokenExpiryKey),
          let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
        return true // Assume expired if we can't determine
    }

    // Consider expired if within 5 minutes of expiry
    let bufferSeconds: TimeInterval = 300
    return Date().addingTimeInterval(bufferSeconds) >= expiryDate
}
```

#### 2.2 Update login() to store expiry

**File**: `ios/BookVault/Services/AuthManager.swift`

```swift
func login(email: String, password: String) async {
    // ... existing code ...

    let response = try await apiClient.login(email: email, password: password)

    // Store tokens
    try keychain.save(key: accessTokenKey, value: response.accessToken)
    try keychain.save(key: refreshTokenKey, value: response.refreshToken.uuidString)

    // NEW: Store token expiry
    storeTokenExpiry(expiresIn: response.expiresIn)

    // ... rest of existing code ...
}
```

---

### Phase 3: Proactive Token Refresh (Optional)

**Goal**: Refresh token before it expires to prevent any 401 errors.

#### 3.1 Add background refresh timer

**File**: `ios/BookVault/Services/AuthManager.swift`

```swift
private var refreshTimer: Timer?

/// Start proactive token refresh timer
private func startRefreshTimer(expiresIn: Int) {
    // Stop any existing timer
    refreshTimer?.invalidate()

    // Refresh 5 minutes before expiry (or half the expiry time if less than 10 min)
    let refreshInterval = max(TimeInterval(expiresIn) - 300, TimeInterval(expiresIn) / 2)

    refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: false) { [weak self] _ in
        Task { @MainActor in
            await self?.proactiveRefresh()
        }
    }
}

/// Proactively refresh token before expiry
private func proactiveRefresh() async {
    DebugLogger.auth("Proactive token refresh triggered")
    let success = await refreshAccessToken()

    if success {
        // Get new expiry and schedule next refresh
        // Note: We'd need to store the new expiresIn from refresh response
    }
}

/// Stop refresh timer (called on logout)
private func stopRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
}
```

---

## Files to Modify

| File                                       | Changes                                                     |
| ------------------------------------------ | ----------------------------------------------------------- |
| `ios/BookVault/Services/APIClient.swift`   | Add 401 retry logic, token refresh attempt                  |
| `ios/BookVault/Services/AuthManager.swift` | Enhance refreshAccessToken(), add expiry storage (optional) |

## Testing Plan

### Unit Tests

1. **APIClient 401 Handling**
   - Test: 401 triggers refresh attempt
   - Test: Successful refresh retries original request
   - Test: Failed refresh calls forceLogout
   - Test: No infinite retry loop on repeated 401s

2. **AuthManager Token Refresh**
   - Test: refreshAccessToken() updates keychain
   - Test: refreshAccessToken() updates APIClient.accessToken
   - Test: Failed refresh clears session

### Integration Tests

1. **End-to-End Flow**
   - Login → Wait for token to expire → Make API call → Verify auto-refresh
   - Login → Revoke refresh token on backend → Verify forced logout

### Manual Testing

1. Login to iOS app
2. Wait 1+ hours (or set `JWT_ACCESS_TOKEN_EXPIRY=60` for 1-minute expiry)
3. Make any API call (e.g., refresh library)
4. Verify: User stays logged in (token refreshed automatically)
5. Verify: No error message shown to user

---

## Rollout Strategy

### Phase 1 Only (Minimum Viable Fix)

Implement only the reactive 401 refresh. This is the simplest fix with highest impact:

- **Effort**: ~2-3 hours
- **Risk**: Low
- **Benefit**: Users no longer logged out unexpectedly

### Full Implementation (Phases 1-3)

Add proactive refresh for smoother UX:

- **Effort**: ~4-6 hours
- **Risk**: Medium (timer management complexity)
- **Benefit**: No momentary delays from 401 → refresh → retry

---

## Recommendation

**Start with Phase 1 only**. The reactive 401 refresh solves the immediate problem with minimal code changes. Phases 2 and 3 can be added later if needed.

Phase 1 changes are isolated to:

1. `APIClient.execute()` - Add refresh attempt before forceLogout
2. `AuthManager.refreshAccessToken()` - Ensure it updates APIClient.accessToken

This is the standard pattern used by most iOS apps for JWT authentication.

---

## Alternative: Backend-Only Fix

If iOS changes need to wait, a temporary backend fix is possible:

```bash
# In ECS task definition, set longer token expiry
JWT_ACCESS_TOKEN_EXPIRY=604800  # 7 days
```

**Pros**: No iOS changes, instant fix
**Cons**: Less secure (longer token lifetime), doesn't solve root issue

This could be used as a stopgap while implementing the proper iOS fix.
