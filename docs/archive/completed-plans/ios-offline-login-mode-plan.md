# iOS Offline Login Mode — Implementation Plan

Status: ✅ **Complete** — shipped in PR #132 (July 28, 2026); manual verification done
Owner: (assign)
Related: `docs/plans/ios-audio-session-persistence-plan.md`, approved plan `~/.claude/plans/generic-squishing-axolotl.md`

---

## 1. Context / Problem

During a power + internet outage a user opened BookVault and got stuck on the
login screen: it hung with little visible, and there was no way to reach
already-downloaded audiobooks. They asked for an **"offline mode" escape hatch on
the auth screen**.

Investigation shows ~80% of the offline machinery already exists; the failure is
narrow and has a clear root cause.

**What already works**

- `AuthManager.restoreSession()` is **fully local** (keychain only, no network),
  so a returning user normally boots straight in even offline —
  `ios/BookVault/Services/AuthManager.swift:196`.
- Once `isAuthenticated`, `ContentView` **already renders an offline experience**
  gated on `NetworkMonitor.isConnected` (hides Catalog/Browse/Search, shows
  `OfflineModeView`, keeps Library/Downloads/Settings) —
  `ios/BookVault/ContentView.swift:66`.
- Downloaded books **play from local disk with no token** (`playFromLocalFile`) —
  `ios/BookVault/Services/AudioPlayerManager.swift:389`.
- Downloaded audio files **survive logout** (`clearCachesOnLogout` clears
  library/progress caches + stops audio, but does not delete `DownloadManager`
  files) — `ios/BookVault/Services/AuthManager.swift:32`.

**Root cause of getting stuck**
`AuthManager.refreshAccessToken()` calls `clearSession()` on _any_ error,
including `.networkError` — `ios/BookVault/Services/AuthManager.swift:168`. A token
refresh attempted while offline logs the user out and dumps them at `LoginView`,
which has no offline escape and needs the network to log back in. "Temporarily
offline" becomes "logged out and stuck."

**Secondary UX issue**
An offline login attempt hangs on the shared 30s request timeout
(`ios/BookVault/Services/APIClient.swift:110`) showing only a spinner.

**Decisions (confirmed with user)**

- Scope: **full layered fix** (root-cause bug + login-screen escape hatch + login feedback).
- Offline entry gate: **prior session + biometric** (require Face ID/Touch ID when enrolled).

---

## 2. Design overview

Three layers, implementable and verifiable independently:

1. **Layer 1 (root cause):** refresh failures caused by _network_ must never tear
   down the session. Only a real auth rejection (401) clears it.
2. **Layer 2 (escape hatch):** an explicit `isOfflineMode` session state, reachable
   from `LoginView` via a biometric-gated "Continue Offline" button, that unlocks
   the existing offline tab set.
3. **Layer 3 (feedback):** don't fire a 30s-hanging login request when offline;
   fail fast with a clear message and surface the offline option.

Reused as-is: `NetworkMonitor` / `NetworkMonitoring`, `BiometricAuthManager`,
`OfflineModeView`, `DownloadManager`, `StorageManager`, user-scoped caches
(they resolve via `AuthManager.shared.currentUser?.id`, so `enterOfflineMode()`
setting `currentUser` is sufficient).

---

## 3. Reference facts (verified in code)

- `APIError` cases: `invalidURL`, `networkError(Error)`, `invalidResponse`,
  `decodingError(Error)`, `serverError(Int, String?)`, `unauthorized`, `notFound`
  — `ios/BookVault/Services/APIClient.swift:13`.
- `AuthManager` keychain keys: `accessTokenKey`, `refreshTokenKey`, `userDataKey`
  — `AuthManager.swift:27`.
- `AuthManager` testable init: `init(apiClient:keychain:)` (no network monitor yet)
  — `AuthManager.swift:62`.
- `AuthManaging` protocol currently exposes `isAuthenticated`, `isRestoringSession`,
  `currentUser`, `isLoading`, `errorMessage`, `token`, `username`, and the 4 funcs
  — `ios/BookVault/Services/Protocols/AuthManaging.swift`.
- `NetworkMonitoring` protocol + `MockNetworkMonitor` exist (DI pattern to follow).
- `OfflineProgressStore` / `LibraryCacheManager` user id = `AuthManager.shared.currentUser?.id.uuidString`
  — `OfflineProgressStore.swift:43`.
- `BiometricAuthManager`: `canUseBiometrics`, `isBiometricEnabled`, `biometryName`,
  `authenticateAndGetCredentials() async throws -> (username,password)`
  — `BiometricAuthManager.swift`.

---

## 4. Step-by-step implementation

### Step 1 — Layer 1: fix `refreshAccessToken()` (root cause)

File: `ios/BookVault/Services/AuthManager.swift`

1a. **Inject a network monitor** for the offline guard + testability (mirrors the
existing DI pattern). Add a stored `private let networkMonitor: NetworkMonitoring`
and thread it through both inits (default `NetworkMonitor.shared` in the
convenience init; a parameter with default in the testable init):

```swift
init(apiClient: APIClientProtocol,
     keychain: KeychainStoring,
     networkMonitor: NetworkMonitoring = NetworkMonitor.shared) {
    self.apiClient = apiClient
    self.keychain = keychain
    self.networkMonitor = networkMonitor
    self.isRestoringSession = false
}
```

(Confirm `NetworkMonitoring` is `@MainActor` / exposes `isConnected`; if not, read
`Services/Protocols/NetworkMonitoring.swift` and add `var isConnected: Bool { get }`.)

1b. **Early offline guard** at the top of `refreshAccessToken()` — after the
`guard let refreshToken` check:

```swift
guard networkMonitor.isConnected else {
    DebugLogger.auth("Refresh skipped - offline; preserving session")
    return false   // do NOT clearSession()
}
```

1c. **Only clear on a real 401.** In the `catch let error as APIError` block
(`AuthManager.swift:168`), move `clearSession()` so it runs **only** for
`.unauthorized`. For `.networkError`, `.serverError` (non-401), `.decodingError`,
and the generic `catch`, log and `return false` **without** clearing:

```swift
} catch let error as APIError {
    switch error {
    case .unauthorized:
        DebugLogger.error("REFRESH FAILED: 401 - refresh token invalid/expired")
        clearSession()          // real auth failure → log out
        return false
    case .networkError(let underlying):
        DebugLogger.error("REFRESH FAILED: Network - \(underlying.localizedDescription); preserving session")
        return false            // offline/transient → keep session
    case .serverError(let code, let message):
        DebugLogger.error("REFRESH FAILED: Server \(code) - \(message ?? "")")
        if code == 401 { clearSession(); }
        return false            // 5xx must NOT log out
    default:
        DebugLogger.error("REFRESH FAILED: \(error.localizedDescription); preserving session")
        return false
    }
} catch {
    DebugLogger.error("REFRESH FAILED: Unexpected - \(error.localizedDescription); preserving session")
    return false                // do NOT clearSession()
}
```

**Checkpoint:** offline token refresh returns `false` and leaves
`refreshTokenValue`, keychain, and `currentUser` intact.

---

### Step 2 — Layer 2: offline session state in `AuthManager`

File: `ios/BookVault/Services/AuthManager.swift`

2a. Add published state near the other `@Published` props:

```swift
@Published private(set) var isOfflineMode = false
```

2b. Add a restorable-session probe:

```swift
/// True when a prior online session's user data still lives in the keychain.
var hasRestorableSession: Bool {
    keychain.load(key: userDataKey) != nil
}
```

2c. Add `enterOfflineMode()`:

```swift
/// Enter a local, offline-only session. Rehydrates the cached user so
/// user-scoped caches resolve, without claiming an online-verified session.
func enterOfflineMode() {
    guard let userDataString = keychain.load(key: userDataKey),
          let userData = userDataString.data(using: .utf8),
          let user = try? JSONDecoder().decode(User.self, from: userData) else {
        DebugLogger.auth("enterOfflineMode: no cached user to restore")
        errorMessage = "No offline session available on this device."
        return
    }
    if let accessToken = keychain.load(key: accessTokenKey) {
        apiClient.accessToken = accessToken     // may be expired; only local playback needs no token
    }
    if let refreshString = keychain.load(key: refreshTokenKey) {
        refreshTokenValue = UUID(uuidString: refreshString)
    }
    currentUser = user
    isOfflineMode = true
    isRestoringSession = false
    errorMessage = nil
    DebugLogger.auth("Entered offline mode for user: \(user.username)")
}
```

2d. Reset the flag in `clearSession()` (add `self.isOfflineMode = false` alongside
the other state resets at `AuthManager.swift:265`).

2e. Add a promotion helper used when connectivity returns (Step 3 calls it):

```swift
/// Called when connectivity returns during offline mode. Attempts a refresh;
/// on success upgrades to a full online session.
func promoteToOnlineIfPossible() async {
    guard isOfflineMode else { return }
    if await refreshAccessToken() {
        isAuthenticated = true
        isOfflineMode = false
        DebugLogger.auth("Promoted offline session to online")
    }
}
```

2f. **Protocol** `ios/BookVault/Services/Protocols/AuthManaging.swift`: add

```swift
var isOfflineMode: Bool { get }
var hasRestorableSession: Bool { get }
func enterOfflineMode()
func promoteToOnlineIfPossible() async
```

Then update any conforming mocks under `ios/BookVaultTests/Mocks/` (search for
`AuthManaging`; add the members). If there is no `MockAuthManager`, only the real
type conforms — nothing else to update.

**Checkpoint:** project compiles; `enterOfflineMode()` sets `currentUser` + flag.

---

### Step 3 — Layer 2: gate `ContentView` + online promotion

File: `ios/BookVault/ContentView.swift`

3a. Change the authed branch condition (`ContentView.swift:62`):

```swift
} else if authManager.isAuthenticated || authManager.isOfflineMode {
```

The existing `networkMonitor.isConnected` tab logic (line 66) then shows the
offline tab set automatically. No new UI.

3b. In `handleNetworkChange(isOnline:)` (`ContentView.swift:170`), when we come
back online while in offline mode, attempt promotion before restoring tabs:

```swift
if isOnline {
    if authManager.isOfflineMode {
        Task { await authManager.promoteToOnlineIfPossible() }
    }
    // ...existing tab-restore logic...
}
```

**Checkpoint:** with `isOfflineMode = true` and offline, app shows Offline /
Library / Downloads / Settings; restoring network promotes to full tabs.

---

### Step 4 — Layer 2/3: `LoginView` offline banner + Continue Offline + short-circuit

File: `ios/BookVault/Views/Auth/LoginView.swift`

4a. Observe the monitor: add `@StateObject private var networkMonitor = NetworkMonitor.shared`.

4b. **Offline banner** — above the login form (after the logo block, ~line 43),
shown when `!networkMonitor.isConnected`:

```swift
if !networkMonitor.isConnected {
    Label("No internet connection", systemImage: "wifi.slash")
        .font(.footnote)
        .foregroundColor(.orange)
        .padding(.bottom, 4)
}
```

4c. **Continue Offline button** — show when offline AND there is a known identity
(`authManager.hasRestorableSession || biometricManager.isBiometricEnabled`). Place
it near the login button:

```swift
if !networkMonitor.isConnected
    && (authManager.hasRestorableSession || biometricManager.isBiometricEnabled) {
    Button {
        Task { await continueOffline() }
    } label: {
        HStack { Image(systemName: "wifi.slash"); Text("Continue Offline") }
            .fontWeight(.medium).frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .buttonStyle(.bordered)
}
```

4d. **`continueOffline()`** — biometric gate (when enrolled) then enter offline
mode (reuses `authenticateAndGetCredentials()` like `authenticateWithBiometric()`):

```swift
private func continueOffline() async {
    if biometricManager.canUseBiometrics && biometricManager.isBiometricEnabled {
        do { _ = try await biometricManager.authenticateAndGetCredentials() }
        catch { authManager.errorMessage = "Biometric verification failed."; return }
    }
    authManager.enterOfflineMode()
}
```

4e. **Short-circuit online login when offline** — in `login()` (`LoginView.swift:155`),
before starting the network task:

```swift
guard networkMonitor.isConnected else {
    authManager.errorMessage = "You're offline — check your connection, or continue offline."
    return
}
```

**Checkpoint:** offline LoginView shows banner + Continue Offline; tapping prompts
Face ID then lands in offline tabs; tapping Log In offline shows the message
instantly (no 30s hang).

---

### Step 5 — Optional hardening: faster auth timeout

File: `ios/BookVault/Services/APIClient.swift`

The offline short-circuit (Step 4e) covers the reported hang. Optionally, for
flaky (not fully down) networks, give auth requests a shorter deadline than the
shared 30s (`APIClient.swift:110`) — e.g. set `request.timeoutInterval = 12` on
the login/refresh `URLRequest` in `createRequest`/`login`. Keep the global 300s
resource timeout for downloads. Low priority; do only if we want fast-fail on
degraded links.

---

## 5. Tests

Dir: `ios/BookVaultTests/Services/` (add `AuthManagerOfflineTests.swift`). Use
`MockAPIClient`, an in-memory keychain mock (see `KeychainStoring` conformances),
and `MockNetworkMonitor`.

Cover:

1. `refreshAccessToken()` with `MockAPIClient.refreshToken` throwing
   `APIError.networkError` → returns `false`, `isAuthenticated` stays `true`,
   keychain tokens still present (**regression test for the root-cause bug**).
2. Same with `APIError.unauthorized` → returns `false`, session cleared.
3. `refreshAccessToken()` with `MockNetworkMonitor.isConnected == false` →
   returns `false` immediately, session preserved, `MockAPIClient.refreshToken`
   never called.
4. `enterOfflineMode()` with cached user data in keychain → `isOfflineMode == true`,
   `currentUser != nil`; with empty keychain → stays `false`, sets `errorMessage`.
5. `promoteToOnlineIfPossible()` → success path flips to `isAuthenticated`.

`MockNetworkMonitor` + `NetworkMonitor.simulateNetworkState(connected:)` (DEBUG,
`NetworkMonitor.swift:199`) support offline simulation.

---

## 6. Manual verification (simulator)

Build:

```
xcodebuild -project ios/BookVault.xcodeproj -scheme BookVault \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Then, after logging in once and downloading a book, use Airplane Mode / Network
Link Conditioner ("100% Loss"):

1. **Cold launch offline** → lands in the app (offline tabs), not stuck. _(restoreSession is local)_
2. **Force refresh offline** (expired access token) → **not** logged out. _(Layer 1)_
3. **Logged-out + offline** → LoginView shows banner + "Continue Offline"; Face ID
   gates entry; Downloads plays a local file. _(Layer 2)_
4. **Tap Log In while offline** → immediate message, no 30s spinner. _(Layer 3)_
5. **Restore connectivity** in offline mode → promoted to full online tabs. _(Step 3b)_

---

## 7. Work log / checklist

- [x] Step 1 — Layer 1 refresh fix (+ network monitor DI)
- [x] Step 2 — AuthManager offline state + protocol
- [x] Step 3 — ContentView gating + promotion
- [x] Step 4 — LoginView banner / Continue Offline / short-circuit
- [x] Step 5 — faster auth timeout (15s on login/refresh via `createRequest(timeout:)`)
- [x] Tests added & passing — `AuthManagerRealTests` 27/27 pass (7 new offline tests)
- [x] Manual verification 1–5 (simulator, on-device) — confirmed July 30, 2026
