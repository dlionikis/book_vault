# iOS Testing & Preview Coverage Recommendations

> **Purpose**: Analysis and recommendations for improving iOS test coverage and SwiftUI Preview coverage.
>
> **Date**: December 29, 2025
> **Status**: Decisions finalized - Ready for implementation

---

## Executive Summary

| Category              | Current State          | Assessment               |
| --------------------- | ---------------------- | ------------------------ |
| **Unit Tests**        | 0 tests                | Critical gap             |
| **Integration Tests** | 0 tests                | Critical gap             |
| **Preview Coverage**  | 100% of views          | Good foundation          |
| **Preview Quality**   | Mixed (varies by view) | Deferred to future phase |

**Key Finding**: The iOS app has been developed with zero automated tests. While all 22 SwiftUI views have previews (a positive sign), there is significant risk in deploying an app with no automated testing for core functionality like authentication, audio playback, downloads, and offline mode.

---

## Decisions Made (December 29, 2025)

| Question                    | Decision                                                            |
| --------------------------- | ------------------------------------------------------------------- |
| **Test Priority**           | Auth → Play critical path first                                     |
| **Testability Refactoring** | Yes - refactor singletons to protocols following DRY best practices |
| **Preview Investment**      | Deferred - prioritize unit tests                                    |
| **CI/CD**                   | Yes - set up iOS testing in CI pipeline                             |
| **Coverage Target**         | 70% for services                                                    |
| **Snapshot Testing**        | Deferred to future phase (along with Preview enhancements)          |

---

## Part 1: Test Coverage Analysis

### 1.1 Current State: Zero Test Coverage

The iOS project has **no automated tests**:

- No XCTest files exist
- No test target configured in `project.yml`
- No test framework integration
- No CI/CD pipeline for iOS tests

### 1.2 Services Inventory (16 files, 0 tested)

| Service                                              | Complexity | Business Critical | Risk Level |
| ---------------------------------------------------- | ---------- | ----------------- | ---------- |
| **APIClient.swift**                                  | HIGH       | YES               | Critical   |
| **AuthManager.swift**                                | HIGH       | YES               | Critical   |
| **AudioPlayerManager.swift**                         | VERY HIGH  | YES               | Critical   |
| **DownloadManager.swift**                            | VERY HIGH  | YES               | Critical   |
| **StorageManager.swift**                             | HIGH       | YES               | Critical   |
| **ProgressManager.swift**                            | MEDIUM     | YES               | High       |
| **LibraryManager.swift**                             | MEDIUM     | YES               | High       |
| **OfflineProgressStore.swift**                       | HIGH       | YES               | High       |
| **LibraryCacheManager.swift**                        | MEDIUM     | YES               | High       |
| **NetworkMonitor.swift**                             | MEDIUM     | YES               | High       |
| **SyncManager.swift**                                | MEDIUM     | YES               | Medium     |
| **SearchManager.swift**                              | HIGH       | NO                | Medium     |
| **ChapterManager.swift**                             | MEDIUM     | NO                | Low        |
| **AuthenticatedAVAssetResourceLoaderDelegate.swift** | HIGH       | YES               | High       |
| **DebugLogger.swift**                                | MEDIUM     | NO                | Low        |
| **ThemeManager.swift**                               | LOW        | NO                | Low        |

### 1.3 Critical Functionality Without Tests

#### Authentication Flow (AuthManager)

- Login/logout functionality
- Token storage in Keychain
- Session restoration on app launch
- Token refresh mechanism
- Force logout on 401 responses

#### API Communication (APIClient)

- Network request creation with headers
- JSON encoding/decoding
- Date parsing (ISO8601 with multiple formats)
- Error handling (401, 404, 5xx)
- Bearer token authorization

#### Audio Playback (AudioPlayerManager)

- AVPlayer initialization and state management
- Progress tracking and saving
- Chapter navigation
- Audio session configuration
- Background playback
- Playback rate control
- Media session remote commands

#### Download Management (DownloadManager)

- Download state machine transitions
- Progress calculations
- Storage space validation
- WiFi-only enforcement
- Download resuming/pausing
- File integrity verification

#### Offline Mode (Phase 8 - Recently Completed)

- OfflineProgressStore caching logic
- LibraryCacheManager persistence
- SyncManager reconciliation
- Network state change handling
- Local-first save with server sync

### 1.4 Testability Challenges

**Current Patterns That Hinder Testing**:

1. **Singleton Pattern Everywhere**
   - All managers use `static let shared`
   - Makes dependency injection difficult
   - **Decision**: Will refactor to protocols with DI

2. **Tight Coupling**
   - Services directly reference other singletons
   - Example: `DownloadManager.shared` calls `AuthManager.shared`

3. **No Protocol Abstractions**
   - Services are concrete classes, not protocols
   - Cannot easily swap implementations for testing

**Positive Patterns That Help**:

1. **Some Dependency Injection**
   - `ChapterManager(apiClient:)` accepts APIClient
   - Can be leveraged for testing with mock clients

2. **MockData.swift Exists**
   - Good mock data for Book, Chapter, UserProgress
   - Can be reused for unit tests

---

## Part 2: Preview Coverage Analysis (Deferred)

> **Note**: Preview enhancements deferred to future phase. This section retained for reference.

### 2.1 Current State: 100% View Coverage

All 22 SwiftUI views have at least one preview variant:

- **Total Preview Variants**: 31 unique configurations
- **Mock Data**: Centralized in MockData.swift

### 2.2 Known Gaps (For Future Phase)

1. **Detail Views** - Use placeholder UUIDs, previews load forever
2. **List Views** - Missing loading/error/empty state variants
3. **Search View** - Only shows empty state
4. **Downloads/Offline Views** - Minimal state coverage
5. **Syntax Inconsistency** - LibraryView uses older PreviewWrapper pattern

---

## Part 3: Implementation Plan Summary

See **[ios-testing-implementation-plan.md](ios-testing-implementation-plan.md)** for detailed phased implementation guide.

### Phase Overview

| Phase | Focus                     | Tests | Includes CI/CD |
| ----- | ------------------------- | ----- | -------------- |
| **1** | Infrastructure + Auth/API | ~25   | Yes (basic)    |
| **2** | Progress + Storage        | ~25   | Enhanced       |
| **3** | Playback Core             | ~25   | -              |
| **4** | Downloads                 | ~25   | -              |
| **5** | Offline Mode              | ~25   | Full coverage  |

**Total Target**: ~125 tests achieving 70% service coverage

---

## Part 4: Testability Refactoring Approach

### Guiding Principles (Per Decision)

1. **Follow best practices** - Use established Swift testing patterns
2. **DRY code** - Create reusable mock infrastructure, avoid duplication
3. **Incremental refactoring** - Refactor each service as we test it
4. **Backward compatible** - Keep `.shared` working during transition

### Pattern: Protocol + Default Implementation

```swift
// 1. Define protocol
protocol AuthManaging {
    var isLoggedIn: Bool { get }
    var token: String? { get }
    func login(email: String, password: String) async throws
    func logout()
}

// 2. Conform existing class
class AuthManager: AuthManaging {
    static let shared = AuthManager()
    // ... existing implementation
}

// 3. Create mock for tests
class MockAuthManager: AuthManaging {
    var isLoggedIn: Bool = false
    var token: String? = nil
    var loginResult: Result<Void, Error> = .success(())

    func login(email: String, password: String) async throws {
        try loginResult.get()
        isLoggedIn = true
        token = "mock-token"
    }

    func logout() {
        isLoggedIn = false
        token = nil
    }
}
```

### Pattern: Constructor Injection with Defaults

```swift
class ProgressManager {
    static let shared = ProgressManager()

    private let apiClient: APIClientProtocol
    private let storage: StorageManaging

    // Production uses defaults, tests inject mocks
    init(apiClient: APIClientProtocol = APIClient.shared,
         storage: StorageManaging = StorageManager.shared) {
        self.apiClient = apiClient
        self.storage = storage
    }
}
```

---

## Part 5: Risk Assessment

### Current Risk (No Tests)

| Risk                           | Likelihood | Impact   |
| ------------------------------ | ---------- | -------- |
| Auth regression breaks login   | Medium     | Critical |
| Audio playback bug crashes app | Medium     | High     |
| Download state corruption      | Low        | High     |
| Offline sync loses data        | Medium     | Critical |
| Progress not saving correctly  | Medium     | High     |

### Expected Risk (After Implementation)

| Risk                      | New Likelihood | Notes                    |
| ------------------------- | -------------- | ------------------------ |
| Auth regression           | Low            | Caught by unit tests     |
| Audio playback bug        | Low-Medium     | State machine tested     |
| Download state corruption | Low            | State transitions tested |
| Offline sync issues       | Low            | Sync logic tested        |
| Progress not saving       | Low            | Save/restore tested      |

---

## Part 6: Future Work (Deferred)

### Phase 6: Preview Enhancements

- Fix detail view previews (placeholder UUIDs)
- Add state variations to list views
- Enhance search previews with results
- Add download state previews
- Modernize preview syntax

### Phase 7: Snapshot Testing

- Evaluate snapshot testing frameworks (Swift Snapshot Testing)
- Add snapshot tests for critical views
- Dark mode snapshot variants
- Device size variants

---

## Related Documents

- **[ios-testing-implementation-plan.md](ios-testing-implementation-plan.md)** - Detailed phased implementation guide
- **[mobile-ios-plan.md](mobile-ios-plan.md)** - iOS app development plan
- **[STATUS.md](STATUS.md)** - Current project status

---

_Updated December 29, 2025 with finalized decisions._
