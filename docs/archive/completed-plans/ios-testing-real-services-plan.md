# iOS Testing Strategy: Real Services Testing Plan

> **Purpose**: Improve iOS test coverage from 13% to 60%+ by testing real service implementations instead of only mocks.
>
> **Date**: December 29, 2025
> **Current State**: 246 tests, 13% code coverage on actual app code

---

## Executive Summary

### The Problem

Our current test suite has a fundamental coverage gap:

1. **Tests test mocks, not real code**: Files like `OfflineProgressStoreTests.swift` test `MockOfflineProgressStore` instead of `OfflineProgressStore`
2. **Singletons block dependency injection**: All services use `static let shared = ServiceName()` with `private init()`
3. **Protocols exist but aren't used for DI**: We have protocols (`OfflineStoring`, `StorageManaging`, etc.) but services hardcode dependencies to `.shared` singletons
4. **13% coverage on real code**: Despite 246 passing tests, most app logic remains untested

### The Solution

A phased approach to refactor services for testability and add real service tests:

1. **Phase 1**: Test services with no dependencies (pure logic + file system)
2. **Phase 2**: Refactor services to accept injected dependencies
3. **Phase 3**: Test services with mocked external dependencies
4. **Phase 4**: Add integration tests for service interactions

---

## Service Dependency Analysis

### Service Dependency Matrix

| Service                | Dependencies                                                            | External I/O       | Testability                        |
| ---------------------- | ----------------------------------------------------------------------- | ------------------ | ---------------------------------- |
| `DebugLogger`          | None                                                                    | Console            | **Easy** - Pure static functions   |
| `ThemeManager`         | UserDefaults                                                            | None               | **Easy** - Only UserDefaults       |
| `NetworkMonitor`       | NWPathMonitor                                                           | Network            | **Medium** - Can mock path updates |
| `StorageManager`       | FileManager, UserDefaults                                               | File System        | **Medium** - Use temp directories  |
| `OfflineProgressStore` | FileManager, AuthManager                                                | File System        | **Medium** - Needs auth mock       |
| `LibraryCacheManager`  | FileManager, AuthManager                                                | File System        | **Medium** - Needs auth mock       |
| `ProgressManager`      | APIClient, NetworkMonitor, OfflineProgressStore                         | Network            | **Hard** - Multiple deps           |
| `SyncManager`          | NetworkMonitor, OfflineProgressStore, ProgressManager, LibraryManager   | Network            | **Hard** - Many deps               |
| `AuthManager`          | APIClient, Keychain                                                     | Network + Keychain | **Hard** - Keychain access         |
| `APIClient`            | URLSession                                                              | Network            | **Hard** - Network calls           |
| `DownloadManager`      | APIClient, StorageManager, NetworkMonitor, URLSession                   | Network + FS       | **Very Hard**                      |
| `AudioPlayerManager`   | AVPlayer, ProgressManager, StorageManager, DownloadManager, AuthManager | Audio + Network    | **Very Hard**                      |
| `ChapterManager`       | APIClient                                                               | Network            | **Medium** - Single dep            |
| `SearchManager`        | URLSession                                                              | Network            | **Medium** - Single dep            |
| `LibraryManager`       | APIClient, LibraryCacheManager                                          | Network            | **Medium** - Two deps              |

### Current Singleton Architecture

Every service follows this pattern:

```swift
@MainActor
class ServiceName: ObservableObject, ProtocolName {
    static let shared = ServiceName()

    private let dependency = OtherService.shared  // Hardcoded!

    private init() {
        // Setup that may depend on other singletons
    }
}
```

**Problems**:

1. `private init()` prevents creating test instances
2. Dependencies are hardcoded to `.shared` singletons
3. No way to inject mocks for unit testing
4. Tests must use the global shared instance (state pollution)

---

## Testability Categories

### Category 1: Easy to Test Directly (No Refactoring Needed)

These services have minimal dependencies and can be tested by creating instances with controlled inputs.

#### 1.1 DebugLogger

- **Dependencies**: None (static functions)
- **Test Strategy**: Test static methods directly
- **Expected Tests**: 5-10 tests
- **Coverage Impact**: ~50 lines

#### 1.2 ThemeManager

- **Dependencies**: UserDefaults only
- **Current Issue**: Uses `private init()` but only reads/writes UserDefaults
- **Test Strategy**:
  - Make init internal (or add testable initializer)
  - Inject UserDefaults.standard or mock UserDefaults
- **Expected Tests**: 8-12 tests
- **Coverage Impact**: ~40 lines

### Category 2: Testable with File System Isolation

These services use FileManager for persistence but can be tested using temporary directories.

#### 2.1 StorageManager

- **Dependencies**: FileManager, UserDefaults
- **Current Issue**: Uses Documents directory, hardcoded paths
- **Refactoring Needed**:
  - Add internal initializer that accepts base directory URL
  - Create test instances pointing to temp directories
- **Test Strategy**:
  ```swift
  init(baseDirectory: URL) {
      self.downloadsDirectory = baseDirectory.appendingPathComponent("downloads")
      // ... rest of setup
  }
  ```
- **Expected Tests**: 25-35 tests
- **Coverage Impact**: ~200 lines

#### 2.2 OfflineProgressStore

- **Dependencies**: FileManager, AuthManager.shared.currentUser
- **Current Issue**: Depends on AuthManager singleton for user ID
- **Refactoring Needed**:
  - Add internal initializer accepting cache directory
  - Add optional user ID provider closure or protocol
- **Test Strategy**:
  ```swift
  init(cacheDirectory: URL, userIdProvider: @escaping () -> String?) {
      self.cacheDirectory = cacheDirectory
      self.userIdProvider = userIdProvider
  }
  ```
- **Expected Tests**: 20-30 tests
- **Coverage Impact**: ~150 lines

#### 2.3 LibraryCacheManager

- **Dependencies**: FileManager, AuthManager.shared.currentUser
- **Same pattern as OfflineProgressStore**
- **Expected Tests**: 15-20 tests
- **Coverage Impact**: ~100 lines

### Category 3: Requires Dependency Injection Refactoring

These services depend on other services and need DI to be testable.

#### 3.1 ProgressManager

- **Dependencies**: APIClient.shared, OfflineProgressStore.shared, NetworkMonitor.shared
- **Refactoring Needed**:
  ```swift
  init(
      apiClient: APIClientProtocol = APIClient.shared,
      offlineStore: OfflineStoring = OfflineProgressStore.shared,
      networkMonitor: NetworkMonitoring = NetworkMonitor.shared
  ) {
      self.apiClient = apiClient
      self.offlineStore = offlineStore
      self.networkMonitor = networkMonitor
  }
  ```
- **Test Strategy**: Inject mocks for all dependencies
- **Expected Tests**: 25-35 tests
- **Coverage Impact**: ~120 lines

#### 3.2 SyncManager

- **Dependencies**: NetworkMonitor, OfflineProgressStore, ProgressManager, LibraryManager
- **Refactoring**: Same pattern as ProgressManager
- **Expected Tests**: 15-25 tests
- **Coverage Impact**: ~80 lines

#### 3.3 ChapterManager

- **Dependencies**: APIClient.shared
- **Refactoring**: Simple - just inject APIClient
- **Expected Tests**: 10-15 tests
- **Coverage Impact**: ~50 lines

#### 3.4 LibraryManager

- **Dependencies**: APIClient.shared, LibraryCacheManager.shared
- **Refactoring**: Inject both dependencies
- **Expected Tests**: 15-25 tests
- **Coverage Impact**: ~80 lines

### Category 4: Complex External Dependencies

These services have significant external dependencies (network, audio, keychain).

#### 4.1 NetworkMonitor

- **Dependencies**: NWPathMonitor (system framework)
- **Challenge**: NWPathMonitor can't be easily mocked
- **Test Strategy**:
  - Test state management logic by making path handling internal
  - Add method to simulate path updates for testing
  - Or use protocol wrapper around NWPathMonitor
- **Expected Tests**: 10-15 tests
- **Coverage Impact**: ~80 lines

#### 4.2 AuthManager

- **Dependencies**: APIClient.shared, Keychain (Security framework)
- **Challenge**: Keychain requires entitlements, varies between test/app targets
- **Test Strategy**:
  - Extract keychain operations into a `KeychainStoring` protocol
  - Inject mock keychain for tests
- **Expected Tests**: 20-30 tests
- **Coverage Impact**: ~130 lines

#### 4.3 APIClient

- **Dependencies**: URLSession
- **Current State**: Uses URLSession.shared with real network calls
- **Test Strategy**:
  - Use URLProtocol for request interception
  - Or inject URLSession and use mock responses
- **Expected Tests**: 25-35 tests
- **Coverage Impact**: ~180 lines

#### 4.4 DownloadManager

- **Dependencies**: APIClient, StorageManager, NetworkMonitor, URLSession (background)
- **Challenge**: Background URLSession delegates, file I/O
- **Test Strategy**:
  - Inject all dependencies
  - Use mock URLSession for download simulation
  - Test delegate handling with mock tasks
- **Expected Tests**: 30-40 tests
- **Coverage Impact**: ~300 lines

#### 4.5 AudioPlayerManager

- **Dependencies**: AVPlayer, ProgressManager, StorageManager, DownloadManager, AuthManager, MediaPlayer
- **Challenge**: AVPlayer can't run without device/simulator with audio
- **Test Strategy**:
  - Focus on state management logic
  - Mock AVPlayer with protocol wrapper
  - Test chapter navigation, progress saving logic
- **Expected Tests**: 35-50 tests
- **Coverage Impact**: ~450 lines

---

## Specific Refactoring Details

### Pattern 1: Testable Initializer (Preserve Singleton)

Keep the singleton for production but allow test instances:

```swift
@MainActor
class OfflineProgressStore: ObservableObject, OfflineStoring {
    static let shared = OfflineProgressStore()

    private let cacheDirectory: URL
    private let userIdProvider: () -> String?

    // Production singleton init
    private convenience init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsPath.appendingPathComponent("cache", isDirectory: true)
        self.init(
            cacheDirectory: cacheDir,
            userIdProvider: { AuthManager.shared.currentUser?.id.uuidString }
        )
    }

    // Testable initializer (internal visibility)
    init(cacheDirectory: URL, userIdProvider: @escaping () -> String?) {
        self.cacheDirectory = cacheDirectory
        self.userIdProvider = userIdProvider
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadCacheFromDisk()
    }
}
```

### Pattern 2: Protocol-Based Dependency Injection

```swift
@MainActor
class ProgressManager: ObservableObject, ProgressManaging {
    static let shared = ProgressManager()

    private let apiClient: APIClientProtocol
    private let offlineStore: OfflineStoring
    private let networkMonitor: NetworkMonitoring

    // Production singleton
    private convenience init() {
        self.init(
            apiClient: APIClient.shared,
            offlineStore: OfflineProgressStore.shared,
            networkMonitor: NetworkMonitor.shared
        )
    }

    // Testable initializer
    init(
        apiClient: APIClientProtocol,
        offlineStore: OfflineStoring,
        networkMonitor: NetworkMonitoring
    ) {
        self.apiClient = apiClient
        self.offlineStore = offlineStore
        self.networkMonitor = networkMonitor
    }
}
```

### Pattern 3: Protocol Wrapper for System APIs

For APIs like Keychain that can't be easily mocked:

```swift
protocol KeychainStoring {
    func save(key: String, value: String) throws
    func load(key: String) -> String?
    func delete(key: String)
}

class SystemKeychain: KeychainStoring {
    func save(key: String, value: String) throws {
        // Actual SecItemAdd implementation
    }
    // ...
}

class MockKeychain: KeychainStoring {
    var storage: [String: String] = [:]

    func save(key: String, value: String) throws {
        storage[key] = value
    }
    // ...
}
```

---

## Implementation Plan

### Phase 1: Low-Hanging Fruit (Week 1)

**Goal**: Add tests for services that need minimal or no refactoring.

| Service        | Refactoring                | New Tests | Est. Coverage Gain |
| -------------- | -------------------------- | --------- | ------------------ |
| DebugLogger    | None                       | 5         | +50 lines          |
| ThemeManager   | Internal init              | 10        | +40 lines          |
| NetworkMonitor | Add path simulation method | 12        | +60 lines          |

**Deliverables**:

- `DebugLoggerTests.swift` - Testing real static functions
- `ThemeManagerRealTests.swift` - Testing real UserDefaults interaction
- `NetworkMonitorRealTests.swift` - Testing real state management

**Estimated Time**: 2-3 days

### Phase 2: File System Services (Week 1-2)

**Goal**: Test services that persist to file system using temp directories.

| Service              | Refactoring                   | New Tests | Est. Coverage Gain |
| -------------------- | ----------------------------- | --------- | ------------------ |
| StorageManager       | Testable init with base URL   | 30        | +200 lines         |
| OfflineProgressStore | Testable init + user provider | 25        | +150 lines         |
| LibraryCacheManager  | Testable init + user provider | 18        | +100 lines         |

**Deliverables**:

- `StorageManagerRealTests.swift` - Real file operations in temp dir
- `OfflineProgressStoreRealTests.swift` - Real JSON persistence
- `LibraryCacheManagerRealTests.swift` - Real cache operations

**Estimated Time**: 4-5 days

### Phase 3: DI-Enabled Services (Week 2-3)

**Goal**: Refactor services to accept dependencies and test with controlled inputs.

| Service         | Refactoring                 | New Tests | Est. Coverage Gain |
| --------------- | --------------------------- | --------- | ------------------ |
| ProgressManager | Protocol-based DI           | 28        | +120 lines         |
| SyncManager     | Protocol-based DI           | 20        | +80 lines          |
| ChapterManager  | Simple API client injection | 12        | +50 lines          |
| LibraryManager  | Two-dependency injection    | 20        | +80 lines          |

**Deliverables**:

- Update service files with testable initializers
- Add real service test files with mocked network dependencies
- Test actual business logic (merge, sync, cache refresh)

**Estimated Time**: 5-7 days

### Phase 4: Complex Services (Week 3-4)

**Goal**: Add testability to services with complex external dependencies.

| Service            | Refactoring               | New Tests | Est. Coverage Gain |
| ------------------ | ------------------------- | --------- | ------------------ |
| AuthManager        | Keychain protocol         | 25        | +130 lines         |
| APIClient          | URLProtocol interception  | 30        | +180 lines         |
| DownloadManager    | Full DI + mock session    | 35        | +250 lines         |
| AudioPlayerManager | AVPlayer protocol wrapper | 40        | +300 lines         |

**Deliverables**:

- `KeychainStoring` protocol and mock
- `URLProtocol` subclass for API testing
- Mock URLSession for download testing
- Mock AVPlayer wrapper for audio testing

**Estimated Time**: 8-10 days

---

## Expected Outcomes

### Coverage Projection

| Phase   | Lines Covered | Cumulative Coverage |
| ------- | ------------- | ------------------- |
| Current | ~350 lines    | 13%                 |
| Phase 1 | +150 lines    | ~18%                |
| Phase 2 | +450 lines    | ~35%                |
| Phase 3 | +330 lines    | ~47%                |
| Phase 4 | +860 lines    | ~78%                |

**Target**: 60-80% coverage on service layer code.

### Test Count Projection

| Phase   | New Tests | Total Tests |
| ------- | --------- | ----------- |
| Current | 0         | 246         |
| Phase 1 | 27        | 273         |
| Phase 2 | 73        | 346         |
| Phase 3 | 80        | 426         |
| Phase 4 | 130       | 556         |

### Quality Improvements

1. **Real logic tested**: Business logic (merge, sync, caching) verified
2. **Regression protection**: File I/O and persistence actually tested
3. **Edge cases covered**: Error handling paths exercised
4. **Integration confidence**: Services work correctly together

---

## Files to Modify

### Phase 1 Files

- `ios/BookVault/Services/ThemeManager.swift` - Add internal init
- `ios/BookVault/Services/NetworkMonitor.swift` - Add test path injection

### Phase 2 Files

- `ios/BookVault/Services/StorageManager.swift` - Add testable init with baseDirectory
- `ios/BookVault/Services/OfflineProgressStore.swift` - Add testable init with userIdProvider
- `ios/BookVault/Services/LibraryCacheManager.swift` - Add testable init with userIdProvider

### Phase 3 Files

- `ios/BookVault/Services/ProgressManager.swift` - Full DI refactor
- `ios/BookVault/Services/SyncManager.swift` - Full DI refactor
- `ios/BookVault/Services/ChapterManager.swift` - API client injection
- `ios/BookVault/Services/LibraryManager.swift` - Dual dependency injection

### Phase 4 Files

- `ios/BookVault/Services/AuthManager.swift` - Keychain protocol extraction
- `ios/BookVault/Services/APIClient.swift` - URLSession injection
- `ios/BookVault/Services/DownloadManager.swift` - Full DI + session mock
- `ios/BookVault/Services/AudioPlayerManager.swift` - AVPlayer wrapper protocol

### New Protocol Files

- `ios/BookVault/Services/Protocols/KeychainStoring.swift`
- `ios/BookVault/Services/Protocols/NetworkMonitoring.swift` (update existing)

### New Test Files

- `ios/BookVaultTests/Services/Real/DebugLoggerTests.swift`
- `ios/BookVaultTests/Services/Real/ThemeManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/NetworkMonitorRealTests.swift`
- `ios/BookVaultTests/Services/Real/StorageManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/OfflineProgressStoreRealTests.swift`
- `ios/BookVaultTests/Services/Real/LibraryCacheManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/ProgressManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/SyncManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/ChapterManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/LibraryManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/AuthManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/APIClientRealTests.swift`
- `ios/BookVaultTests/Services/Real/DownloadManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/AudioPlayerManagerRealTests.swift`

---

## Risk Assessment

### Low Risk

- **Phase 1-2**: Additive changes only, existing tests unaffected
- File system tests use temp directories (no production data risk)

### Medium Risk

- **Phase 3**: Changing initializers could break SwiftUI previews if not careful
- Mitigation: Keep `private convenience init()` for singleton, add separate testable init

### Higher Risk

- **Phase 4**: AVPlayer and background URLSession testing may require simulator
- Mitigation: Focus on logic testing, use CI with simulator for full coverage

---

## Success Metrics

1. **Coverage**: Achieve 60%+ coverage on `ios/BookVault/Services/` directory
2. **Test Reliability**: All new tests pass consistently in CI
3. **No Regressions**: Existing 246 tests continue to pass
4. **Real Code Tested**: Each real service has at least 10 tests exercising actual implementation

---

## Phase 5: Fix Phase 4 Test Compilation Issues

> **Status**: Blocked - Tests written but not compiling
> **Date Added**: December 30, 2025
> **Prerequisite**: Phase 4 service refactoring is complete

### Background

Phase 4 service refactoring was completed successfully. The four complex services (AuthManager, APIClient, DownloadManager, AudioPlayerManager) were refactored with full dependency injection support. However, the test files have compilation errors due to mismatches between test code and OpenAPI-generated model signatures.

### What Was Completed in Phase 4

#### Service Refactoring (✅ Complete)

1. **AuthManager** - Refactored with:
   - `KeychainStoring` protocol for mock keychain testing
   - `SystemKeychain` production implementation
   - Testable initializer: `init(apiClient:keychain:)`
   - `clearCachesOnLogout` callback for DI

2. **APIClient** - Refactored with:
   - Testable initializer: `init(baseURL:session:)` for URLProtocol interception
   - `forceLogoutHandler` callback for DI
   - Session configuration moved to production singleton

3. **DownloadManager** - Refactored with:
   - Full DI: `init(apiClient:storageManager:networkMonitor:sessionIdentifier:session:)`
   - `forceLogoutHandler` callback
   - Optional session injection for testing

4. **AudioPlayerManager** - Refactored with:
   - DI: `init(progressManager:downloadManager:storageManager:concreteDownloadManager:skipAudioSetup:)`
   - `authTokenProvider` callback for token injection
   - `skipAudioSetup` flag to skip AVAudioSession in unit tests
   - `AudioPlayable` protocol wrapping AVPlayer
   - `AVPlayerWrapper` production implementation

#### New Files Created (✅ Complete)

- `ios/BookVault/Services/Protocols/KeychainStoring.swift`
- `ios/BookVault/Services/Protocols/AudioPlayable.swift`
- `ios/BookVault/Services/SystemKeychain.swift`
- `ios/BookVaultTests/Services/Real/AuthManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/APIClientRealTests.swift`
- `ios/BookVaultTests/Services/Real/DownloadManagerRealTests.swift`
- `ios/BookVaultTests/Services/Real/AudioPlayerManagerRealTests.swift`

### Known Issues (❌ Need Fixing)

#### Issue 1: OpenAPI Model Signature Mismatches

The test files were written with assumed model signatures, but the actual OpenAPI-generated models have different structures.

**Affected Models and Fixes Needed:**

1. **`User` model** (`ios/BookVault/Generated/Models/User.swift`)
   - Actual: `init(id: UUID, email: String)`
   - Tests assumed: `init(id:, email:, createdAt:, updatedAt:)`
   - **Fix**: Update test helpers to only use `id` and `email`

2. **`LoginMobile200Response`** (`ios/BookVault/Generated/Models/LoginMobile200Response.swift`)
   - Actual: `init(accessToken:, refreshToken:, user:, expiresIn:)`
   - Tests assumed: `init(user:, accessToken:, refreshToken:)` (missing `expiresIn`, wrong order)
   - **Fix**: Update test response creation to include `expiresIn` and use correct parameter order

3. **`Book` model** (`ios/BookVault/Generated/Models/Book.swift`)
   - Actual: Optional fields, no `createdAt`/`updatedAt`
   - Tests assumed: Required fields with timestamps
   - **Fix**: Update `makeTestBook()` helpers to match actual signature

4. **`Chapter` model** (`ios/BookVault/Generated/Models/Chapter.swift`)
   - Actual: `init(id:, title:, startTime:, endTime:, duration:, index:)`
   - Tests assumed: `init(id:, title:, startTime:, endTime:)` (missing `duration` and `index`)
   - **Fix**: Update `makeTestChapter()` helpers - PARTIALLY DONE in `AudioPlayerManagerRealTests.swift`

5. **`UserProgress` model** (`ios/BookVault/Models/UserProgress.swift`)
   - Actual: `init(positionSeconds:, completed:, lastPlayed:)`
   - Tests assumed: `init(positionSeconds:, status:, updatedAt:)`
   - **Fix**: Update mock return values - PARTIALLY DONE in `AudioPlayerManagerRealTests.swift`

6. **`SaveProgressResponse`** (`ios/BookVault/Models/UserProgress.swift`)
   - Actual: `init(positionSeconds:, completed:, lastPlayed:, updated:)`
   - Tests assumed: Different field names
   - **Fix**: Update mock return values - PARTIALLY DONE in `AudioPlayerManagerRealTests.swift`

7. **`ListBooks200ResponsePagination`**
   - Test uses `totalBooks` but actual field name may differ
   - **Fix**: Check actual model and update test assertions

8. **`UpdateProgress200Response`**
   - Test uses `.success` but actual model structure differs
   - **Fix**: Check actual model and update test assertions

#### Issue 2: Protocol Conformance in Test Mocks

Some test mocks don't fully conform to their protocols due to the above model mismatches.

**Affected Files:**

- `AuthManagerRealTests.swift` - `MockAPIClientForAuth` login result type
- `AudioPlayerManagerRealTests.swift` - `MockProgressManagerForAudio` return types

#### Issue 3: DownloadError Equatable

`DownloadManagerRealTests.swift` uses `XCTAssertEqual` with `DownloadError`, but the enum doesn't conform to `Equatable`.

**Fix Options:**

1. Add `Equatable` conformance to `DownloadError` (preferred if not too complex)
2. Use pattern matching in assertions (currently partially applied)

### Files Requiring Updates

| File                                | Issues                                                    | Priority |
| ----------------------------------- | --------------------------------------------------------- | -------- |
| `AuthManagerRealTests.swift`        | User model, LoginMobile200Response signatures             | High     |
| `APIClientRealTests.swift`          | ListBooks200ResponsePagination, UpdateProgress200Response | High     |
| `AudioPlayerManagerRealTests.swift` | Chapter model (partially fixed), Book model               | Medium   |
| `DownloadManagerRealTests.swift`    | Book model, DownloadError Equatable                       | Medium   |

### Recommended Approach

1. **Read the actual generated models** in `ios/BookVault/Generated/Models/` to understand exact signatures
2. **Read custom models** in `ios/BookVault/Models/` (UserProgress, SaveProgressResponse)
3. **Update test helper functions** (`makeTestBook()`, `makeTestChapter()`, response builders)
4. **Update mock implementations** to return correct types
5. **Run tests incrementally** - fix one test file at a time

### Estimated Effort

- **Time**: 2-4 hours
- **Complexity**: Low (mostly mechanical updates to match signatures)
- **Risk**: Low (no production code changes needed)

### Commands to Verify

```bash
# Regenerate Xcode project after changes
cd ios && xcodegen generate

# Run Phase 4 tests only
xcodebuild test -scheme BookVault \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:BookVaultTests/AuthManagerRealTests \
  -only-testing:BookVaultTests/APIClientRealTests \
  -only-testing:BookVaultTests/DownloadManagerRealTests \
  -only-testing:BookVaultTests/AudioPlayerManagerRealTests

# Check specific compilation errors
xcodebuild test -scheme BookVault \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  2>&1 | grep "error:"
```

---

## Next Steps

1. **Immediate**: Start with Phase 1 - DebugLogger and ThemeManager tests
2. **This Week**: Complete Phase 2 - StorageManager refactor and tests
3. **Code Review**: Review refactoring patterns before applying to all services
4. **CI Integration**: Ensure coverage reports show improvement after each phase
5. **Phase 5**: Fix Phase 4 test compilation issues (see above)
