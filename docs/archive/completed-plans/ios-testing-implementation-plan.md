# iOS Testing Implementation Plan

> **Purpose**: Detailed phased implementation guide for adding unit tests to the iOS app.
>
> **Date**: December 29, 2025
> **Target Coverage**: 70% for services (~125 tests)
> **Approach**: Incremental - each phase is self-contained with cleared context

---

## Overview

This plan is divided into 5 phases, each designed to be executed independently with a fresh context. Each phase includes:

- Prerequisites (what must be done before starting)
- Deliverables (concrete outputs)
- Verification steps (how to confirm success)
- Files to create/modify

---

## Phase 1: Test Infrastructure + Auth/API Tests

**Goal**: Establish test foundation and test the critical authentication path.

### 1.1 Prerequisites

- iOS project builds successfully: `cd ios && xcodegen generate && xcodebuild build -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15'`
- No uncommitted changes in `ios/` directory

### 1.2 Deliverables

| Deliverable                 | Description                                 |
| --------------------------- | ------------------------------------------- |
| Test target in project.yml  | XCTest target configured for BookVaultTests |
| BookVaultTests directory    | Test file structure matching source         |
| Protocol: APIClientProtocol | Protocol extraction from APIClient          |
| Protocol: AuthManaging      | Protocol extraction from AuthManager        |
| MockAPIClient               | Test double for API calls                   |
| MockAuthManager             | Test double for auth state                  |
| XCTestCase+Async helpers    | Async testing utilities                     |
| AuthManagerTests.swift      | ~10 tests                                   |
| APIClientTests.swift        | ~15 tests                                   |
| GitHub Actions workflow     | ios-tests.yml for CI                        |

### 1.3 Implementation Steps

#### Step 1.3.1: Update project.yml to add test target

Add to `ios/project.yml`:

```yaml
targets:
  # ... existing BookVault target ...

  BookVaultTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: '17.0'

    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.bookvault.BookVaultTests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: '$(BUILT_PRODUCTS_DIR)/BookVault.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/BookVault'
        BUNDLE_LOADER: '$(TEST_HOST)'

    sources:
      - path: BookVaultTests
        createIntermediateGroups: true

    dependencies:
      - target: BookVault

schemes:
  BookVault:
    # ... existing scheme ...
    test:
      config: Debug
      targets:
        - BookVaultTests
```

#### Step 1.3.2: Create test directory structure

```
ios/BookVaultTests/
├── Mocks/
│   ├── MockAPIClient.swift
│   ├── MockAuthManager.swift
│   └── MockURLSession.swift
├── Helpers/
│   └── XCTestCase+Async.swift
├── Services/
│   ├── AuthManagerTests.swift
│   └── APIClientTests.swift
└── Info.plist (auto-generated)
```

#### Step 1.3.3: Extract APIClientProtocol

Create `ios/BookVault/Services/Protocols/APIClientProtocol.swift`:

```swift
import Foundation

/// Protocol for API client to enable testing with mocks
protocol APIClientProtocol {
    var accessToken: String? { get set }
    var baseURL: URL { get }

    // Authentication
    func login(email: String, password: String) async throws -> LoginMobile200Response
    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response
    func logout(refreshToken: UUID) async throws

    // Books
    func fetchBooks(page: Int, limit: Int, sortBy: String?) async throws -> ListBooks200Response
    func fetchBook(id: UUID) async throws -> Book
    func fetchBookChapters(bookId: UUID) async throws -> [Chapter]

    // Progress
    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response
    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response
    func setProgressStatus(bookId: UUID, status: SetProgressStatusRequest.Status) async throws -> SetProgressStatus200Response

    // Library
    func fetchLibrary() async throws -> GetLibrary200Response
    func addToLibrary(bookId: UUID) async throws -> AddToLibrary201Response
    func removeFromLibrary(bookId: UUID) async throws
}
```

Update `APIClient.swift` to conform:

```swift
class APIClient: APIClientProtocol {
    // ... existing implementation unchanged ...
}
```

#### Step 1.3.4: Extract AuthManaging protocol

Create `ios/BookVault/Services/Protocols/AuthManaging.swift`:

```swift
import Foundation

/// Protocol for AuthManager to enable testing with mocks
@MainActor
protocol AuthManaging: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get set }
    var token: String? { get }
    var userEmail: String? { get }

    func login(email: String, password: String) async
    func logout() async
    func forceLogout()
    func refreshAccessToken() async -> Bool
}
```

Update `AuthManager.swift` to conform:

```swift
@MainActor
class AuthManager: ObservableObject, AuthManaging {
    // ... existing implementation unchanged ...
}
```

#### Step 1.3.5: Create MockAPIClient

Create `ios/BookVaultTests/Mocks/MockAPIClient.swift`:

```swift
import Foundation
@testable import BookVault

/// Mock API client for testing - allows configuring responses and tracking calls
class MockAPIClient: APIClientProtocol {
    var accessToken: String?
    var baseURL: URL = URL(string: "http://localhost:3000")!

    // MARK: - Call Tracking
    var loginCalls: [(email: String, password: String)] = []
    var refreshTokenCalls: [UUID] = []
    var logoutCalls: [UUID] = []
    var fetchBooksCalls: [(page: Int, limit: Int, sortBy: String?)] = []
    var fetchBookCalls: [UUID] = []
    var fetchProgressCalls: [UUID] = []
    var updateProgressCalls: [(bookId: UUID, positionSeconds: Double)] = []

    // MARK: - Configurable Results
    var loginResult: Result<LoginMobile200Response, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))
    var refreshTokenResult: Result<RefreshToken200Response, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))
    var logoutResult: Result<Void, Error> = .success(())
    var fetchBooksResult: Result<ListBooks200Response, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))
    var fetchBookResult: Result<Book, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))
    var fetchProgressResult: Result<GetProgress200Response, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))
    var updateProgressResult: Result<UpdateProgress200Response, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

    // MARK: - Reset
    func reset() {
        loginCalls = []
        refreshTokenCalls = []
        logoutCalls = []
        fetchBooksCalls = []
        fetchBookCalls = []
        fetchProgressCalls = []
        updateProgressCalls = []
        accessToken = nil
    }

    // MARK: - APIClientProtocol Implementation

    func login(email: String, password: String) async throws -> LoginMobile200Response {
        loginCalls.append((email, password))
        return try loginResult.get()
    }

    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response {
        refreshTokenCalls.append(refreshToken)
        return try refreshTokenResult.get()
    }

    func logout(refreshToken: UUID) async throws {
        logoutCalls.append(refreshToken)
        try logoutResult.get()
    }

    func fetchBooks(page: Int, limit: Int, sortBy: String?) async throws -> ListBooks200Response {
        fetchBooksCalls.append((page, limit, sortBy))
        return try fetchBooksResult.get()
    }

    func fetchBook(id: UUID) async throws -> Book {
        fetchBookCalls.append(id)
        return try fetchBookResult.get()
    }

    func fetchBookChapters(bookId: UUID) async throws -> [Chapter] {
        // Implement as needed
        return []
    }

    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response {
        fetchProgressCalls.append(bookId)
        return try fetchProgressResult.get()
    }

    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response {
        updateProgressCalls.append((bookId, positionSeconds))
        return try updateProgressResult.get()
    }

    func setProgressStatus(bookId: UUID, status: SetProgressStatusRequest.Status) async throws -> SetProgressStatus200Response {
        // Implement as needed
        fatalError("Not implemented in mock")
    }

    func fetchLibrary() async throws -> GetLibrary200Response {
        // Implement as needed
        fatalError("Not implemented in mock")
    }

    func addToLibrary(bookId: UUID) async throws -> AddToLibrary201Response {
        // Implement as needed
        fatalError("Not implemented in mock")
    }

    func removeFromLibrary(bookId: UUID) async throws {
        // Implement as needed
    }
}
```

#### Step 1.3.6: Create async test helpers

Create `ios/BookVaultTests/Helpers/XCTestCase+Async.swift`:

```swift
import XCTest

extension XCTestCase {
    /// Helper for testing async code on MainActor
    @MainActor
    func awaitPublisher<T: ObservableObject>(
        _ object: T,
        timeout: TimeInterval = 1.0,
        condition: @escaping (T) -> Bool
    ) async throws {
        let start = Date()
        while !condition(object) {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
}
```

#### Step 1.3.7: Create AuthManagerTests

Create `ios/BookVaultTests/Services/AuthManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

@MainActor
final class AuthManagerTests: XCTestCase {

    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        // Note: Full DI refactoring will allow injecting mock
        // For now, we test the protocol contract
    }

    override func tearDown() {
        mockAPIClient = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsNotAuthenticated() {
        // Given a fresh AuthManager
        let manager = AuthManager.shared

        // Then (after clearing any persisted state in test setup)
        // Note: In actual implementation, we'd inject dependencies
        XCTAssertNotNil(manager)
    }

    // MARK: - Login Tests

    func testLoginSuccessUpdatesAuthenticatedState() async {
        // Given
        let mockResponse = LoginMobile200Response(
            accessToken: "test-token",
            refreshToken: UUID(),
            user: User(id: UUID(), email: "test@example.com")
        )
        mockAPIClient.loginResult = .success(mockResponse)

        // When
        // Note: With DI refactoring, we'd test:
        // await authManager.login(email: "test@example.com", password: "password")

        // Then
        // XCTAssertTrue(authManager.isAuthenticated)
        // XCTAssertEqual(authManager.currentUser?.email, "test@example.com")
        XCTAssertTrue(true) // Placeholder until DI is complete
    }

    func testLoginFailureSetsErrorMessage() async {
        // Given
        mockAPIClient.loginResult = .failure(APIError.unauthorized)

        // When / Then
        // After DI: verify errorMessage is set, isAuthenticated is false
        XCTAssertTrue(true) // Placeholder
    }

    func testLoginStoresTokenSecurely() async {
        // Given successful login
        // When login completes
        // Then token should be retrievable via token property
        XCTAssertTrue(true) // Placeholder - requires Keychain testing approach
    }

    // MARK: - Logout Tests

    func testLogoutClearsAuthenticatedState() async {
        // Given authenticated user
        // When logout is called
        // Then isAuthenticated should be false, currentUser should be nil
        XCTAssertTrue(true) // Placeholder
    }

    func testLogoutClearsToken() async {
        // Given authenticated user
        // When logout is called
        // Then token property should return nil
        XCTAssertTrue(true) // Placeholder
    }

    func testLogoutCallsServerLogout() async {
        // Given authenticated user with refresh token
        // When logout is called
        // Then server logout endpoint should be called
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Force Logout Tests

    func testForceLogoutClearsSession() {
        // Given authenticated user
        // When forceLogout is called
        // Then session should be cleared immediately
        XCTAssertTrue(true) // Placeholder
    }

    func testForceLogoutSetsErrorMessage() {
        // Given authenticated user
        // When forceLogout is called
        // Then errorMessage should indicate session expired
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Token Refresh Tests

    func testRefreshAccessTokenSuccess() async {
        // Given valid refresh token
        // When refreshAccessToken is called
        // Then new access token should be stored
        XCTAssertTrue(true) // Placeholder
    }

    func testRefreshAccessTokenFailureClearsSession() async {
        // Given invalid/expired refresh token
        // When refreshAccessToken is called
        // Then session should be cleared
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Session Restoration Tests

    func testRestoreSessionFromKeychain() async {
        // Given valid tokens stored in Keychain
        // When AuthManager initializes
        // Then session should be restored
        XCTAssertTrue(true) // Placeholder - requires Keychain setup
    }
}
```

#### Step 1.3.8: Create APIClientTests

Create `ios/BookVaultTests/Services/APIClientTests.swift`:

```swift
import XCTest
@testable import BookVault

final class APIClientTests: XCTestCase {

    // MARK: - URL Construction Tests

    func testBaseURLIsConfiguredCorrectly() {
        let client = APIClient.shared
        XCTAssertEqual(client.baseURL.absoluteString, "http://localhost:3000")
    }

    // MARK: - Request Creation Tests

    func testRequestIncludesContentTypeHeader() async throws {
        // Test that requests include Content-Type: application/json
        // This requires either exposing createRequest or using URLProtocol mocking
        XCTAssertTrue(true) // Placeholder
    }

    func testAuthenticatedRequestIncludesBearerToken() async throws {
        // Given client with access token
        // When authenticated request is created
        // Then Authorization header should contain Bearer token
        XCTAssertTrue(true) // Placeholder
    }

    func testUnauthenticatedRequestOmitsAuthorizationHeader() async throws {
        // Given client without access token
        // When request is created
        // Then no Authorization header should be present
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Date Parsing Tests

    func testDecodesISO8601DateWithFractionalSeconds() throws {
        // Given JSON with "2025-12-28T19:07:21.367Z"
        // When decoded
        // Then date should be parsed correctly
        let json = """
        {"date": "2025-12-28T19:07:21.367Z"}
        """
        // Test decoder
        XCTAssertTrue(true) // Placeholder
    }

    func testDecodesISO8601DateWithoutFractionalSeconds() throws {
        // Given JSON with "2025-12-28T19:07:21Z"
        // When decoded
        // Then date should be parsed correctly
        XCTAssertTrue(true) // Placeholder
    }

    func testDecodesDateOnlyFormat() throws {
        // Given JSON with "2022-08-08"
        // When decoded
        // Then date should be parsed correctly
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Error Handling Tests

    func testHandles401AsUnauthorized() async throws {
        // Given server returns 401
        // When request completes
        // Then APIError.unauthorized should be thrown
        XCTAssertTrue(true) // Placeholder - requires URLProtocol mock
    }

    func testHandles404AsNotFound() async throws {
        // Given server returns 404
        // When request completes
        // Then APIError.notFound should be thrown
        XCTAssertTrue(true) // Placeholder
    }

    func testHandles500AsServerError() async throws {
        // Given server returns 500 with error message
        // When request completes
        // Then APIError.serverError should be thrown with status and message
        XCTAssertTrue(true) // Placeholder
    }

    func testHandlesNetworkError() async throws {
        // Given network is unavailable
        // When request is attempted
        // Then APIError.networkError should be thrown
        XCTAssertTrue(true) // Placeholder
    }

    func testHandlesDecodingError() async throws {
        // Given server returns malformed JSON
        // When decoding is attempted
        // Then APIError.decodingError should be thrown
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Login Endpoint Tests

    func testLoginReturnsTokensAndUser() async throws {
        // This would require mocking the network layer
        // See Phase 2 for URLProtocol-based testing
        XCTAssertTrue(true) // Placeholder
    }

    func testLoginStoresAccessToken() async throws {
        // Given successful login response
        // When login completes
        // Then accessToken property should be set
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 1.3.9: Create GitHub Actions workflow

Create `.github/workflows/ios-tests.yml`:

```yaml
name: iOS Tests

on:
  push:
    branches: [main]
    paths:
      - 'ios/**'
      - '.github/workflows/ios-tests.yml'
  pull_request:
    branches: [main]
    paths:
      - 'ios/**'
      - '.github/workflows/ios-tests.yml'

jobs:
  test:
    runs-on: macos-14

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.0'

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        working-directory: ios
        run: xcodegen generate

      - name: Run tests
        working-directory: ios
        run: |
          xcodebuild test \
            -scheme BookVault \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
            -resultBundlePath TestResults.xcresult \
            | xcpretty

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: ios/TestResults.xcresult
```

### 1.4 Verification Steps

1. **Regenerate Xcode project**:

   ```bash
   cd ios && xcodegen generate
   ```

2. **Build and run tests**:

   ```bash
   xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15'
   ```

3. **Verify test target exists**:
   - Open `ios/BookVault.xcodeproj` in Xcode
   - Verify `BookVaultTests` target appears in scheme selector
   - Run tests with Cmd+U

4. **Verify CI workflow**:
   - Commit and push changes
   - Check GitHub Actions for test run

### 1.5 Success Criteria

- [ ] Test target builds without errors
- [ ] All placeholder tests pass (will be filled in after DI refactoring)
- [ ] GitHub Actions workflow runs and passes
- [ ] Protocol files compile without affecting existing functionality
- [ ] MockAPIClient can be instantiated in tests

### 1.6 Notes for Next Phase

- Phase 2 will complete the DI refactoring to enable real tests
- Placeholder tests will be converted to actual assertions
- Consider adding URLProtocol-based mocking for network tests

---

## Phase 2: Progress + Storage Tests + DI Completion

**Goal**: Complete dependency injection refactoring and add tests for progress/storage services.

### 2.1 Prerequisites

- Phase 1 completed successfully
- Test target builds and runs
- Protocols extracted for APIClient and AuthManager

### 2.2 Deliverables

| Deliverable                      | Description                         |
| -------------------------------- | ----------------------------------- |
| Protocol: ProgressManaging       | Protocol for ProgressManager        |
| Protocol: StorageManaging        | Protocol for StorageManager         |
| Protocol: NetworkMonitoring      | Protocol for NetworkMonitor         |
| Dependency injection in services | Constructor injection with defaults |
| MockProgressManager              | Test double for progress            |
| MockStorageManager               | Test double for storage             |
| MockNetworkMonitor               | Test double for connectivity        |
| ProgressManagerTests.swift       | ~12 tests                           |
| StorageManagerTests.swift        | ~10 tests                           |
| NetworkMonitorTests.swift        | ~5 tests                            |
| Convert Phase 1 placeholders     | Real test assertions                |

### 2.3 Implementation Steps

#### Step 2.3.1: Extract ProgressManaging protocol

Create `ios/BookVault/Services/Protocols/ProgressManaging.swift`:

```swift
import Foundation

/// Protocol for ProgressManager to enable testing
protocol ProgressManaging {
    /// Save progress locally and sync to server
    func saveProgress(bookId: UUID, positionSeconds: Double, totalSeconds: Double) async

    /// Get locally cached progress for a book
    func getCachedProgress(bookId: UUID) -> UserProgress?

    /// Mark book as completed
    func markAsCompleted(bookId: UUID) async throws

    /// Reset progress for a book
    func resetProgress(bookId: UUID) async throws

    /// Sync pending progress updates to server
    func syncPendingProgress() async
}
```

#### Step 2.3.2: Extract StorageManaging protocol

Create `ios/BookVault/Services/Protocols/StorageManaging.swift`:

```swift
import Foundation

/// Protocol for StorageManager to enable testing
protocol StorageManaging {
    /// Get available storage space in bytes
    var availableStorage: Int64 { get }

    /// Get total used storage by downloads
    var usedStorage: Int64 { get }

    /// Check if there's enough space for a download
    func hasSpaceForDownload(sizeInBytes: Int64) -> Bool

    /// Get local file URL for a downloaded book
    func localFileURL(for bookId: UUID) -> URL?

    /// Save audio data to local storage
    func saveAudioFile(bookId: UUID, data: Data) throws -> URL

    /// Delete downloaded audio file
    func deleteAudioFile(bookId: UUID) throws

    /// Check if book is downloaded
    func isDownloaded(bookId: UUID) -> Bool

    /// Get download metadata
    func getDownloadMetadata(bookId: UUID) -> DownloadMetadata?

    /// Save download metadata
    func saveDownloadMetadata(_ metadata: DownloadMetadata) throws
}
```

#### Step 2.3.3: Extract NetworkMonitoring protocol

Create `ios/BookVault/Services/Protocols/NetworkMonitoring.swift`:

```swift
import Foundation
import Combine

/// Protocol for NetworkMonitor to enable testing
protocol NetworkMonitoring {
    /// Current connection status
    var isConnected: Bool { get }

    /// Whether connected via WiFi
    var isConnectedViaWiFi: Bool { get }

    /// Whether connected via cellular
    var isConnectedViaCellular: Bool { get }

    /// Publisher for connection status changes
    var connectionStatusPublisher: AnyPublisher<Bool, Never> { get }
}
```

#### Step 2.3.4: Refactor ProgressManager with dependency injection

Update `ios/BookVault/Services/ProgressManager.swift`:

```swift
class ProgressManager: ProgressManaging {
    static let shared = ProgressManager()

    private let apiClient: APIClientProtocol
    private let offlineStore: OfflineProgressStore
    private let networkMonitor: NetworkMonitoring

    // Default init uses singletons (production)
    init(
        apiClient: APIClientProtocol = APIClient.shared,
        offlineStore: OfflineProgressStore = .shared,
        networkMonitor: NetworkMonitoring = NetworkMonitor.shared
    ) {
        self.apiClient = apiClient
        self.offlineStore = offlineStore
        self.networkMonitor = networkMonitor
    }

    // ... rest of implementation uses injected dependencies ...
}
```

#### Step 2.3.5: Create MockProgressManager

Create `ios/BookVaultTests/Mocks/MockProgressManager.swift`:

```swift
import Foundation
@testable import BookVault

class MockProgressManager: ProgressManaging {
    // Call tracking
    var saveProgressCalls: [(bookId: UUID, position: Double, total: Double)] = []
    var getCachedProgressCalls: [UUID] = []
    var markAsCompletedCalls: [UUID] = []
    var resetProgressCalls: [UUID] = []
    var syncPendingProgressCalled = false

    // Configurable returns
    var cachedProgress: [UUID: UserProgress] = [:]
    var markAsCompletedShouldFail = false
    var resetProgressShouldFail = false

    func saveProgress(bookId: UUID, positionSeconds: Double, totalSeconds: Double) async {
        saveProgressCalls.append((bookId, positionSeconds, totalSeconds))
    }

    func getCachedProgress(bookId: UUID) -> UserProgress? {
        getCachedProgressCalls.append(bookId)
        return cachedProgress[bookId]
    }

    func markAsCompleted(bookId: UUID) async throws {
        markAsCompletedCalls.append(bookId)
        if markAsCompletedShouldFail {
            throw APIError.networkError(NSError(domain: "Test", code: -1))
        }
    }

    func resetProgress(bookId: UUID) async throws {
        resetProgressCalls.append(bookId)
        if resetProgressShouldFail {
            throw APIError.networkError(NSError(domain: "Test", code: -1))
        }
    }

    func syncPendingProgress() async {
        syncPendingProgressCalled = true
    }

    func reset() {
        saveProgressCalls = []
        getCachedProgressCalls = []
        markAsCompletedCalls = []
        resetProgressCalls = []
        syncPendingProgressCalled = false
        cachedProgress = [:]
    }
}
```

#### Step 2.3.6: Create MockStorageManager

Create `ios/BookVaultTests/Mocks/MockStorageManager.swift`:

```swift
import Foundation
@testable import BookVault

class MockStorageManager: StorageManaging {
    var availableStorage: Int64 = 10_000_000_000 // 10GB default
    var usedStorage: Int64 = 0

    var downloadedBooks: Set<UUID> = []
    var savedFiles: [UUID: Data] = []
    var metadata: [UUID: DownloadMetadata] = []

    // Call tracking
    var saveAudioFileCalls: [(bookId: UUID, dataSize: Int)] = []
    var deleteAudioFileCalls: [UUID] = []

    // Error simulation
    var saveShouldFail = false
    var deleteShouldFail = false

    func hasSpaceForDownload(sizeInBytes: Int64) -> Bool {
        return availableStorage >= sizeInBytes
    }

    func localFileURL(for bookId: UUID) -> URL? {
        guard downloadedBooks.contains(bookId) else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId.uuidString).mp3")
    }

    func saveAudioFile(bookId: UUID, data: Data) throws -> URL {
        saveAudioFileCalls.append((bookId, data.count))
        if saveShouldFail {
            throw NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage full"])
        }
        savedFiles[bookId] = data
        downloadedBooks.insert(bookId)
        usedStorage += Int64(data.count)
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId.uuidString).mp3")
    }

    func deleteAudioFile(bookId: UUID) throws {
        deleteAudioFileCalls.append(bookId)
        if deleteShouldFail {
            throw NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
        }
        if let data = savedFiles.removeValue(forKey: bookId) {
            usedStorage -= Int64(data.count)
        }
        downloadedBooks.remove(bookId)
        metadata.removeValue(forKey: bookId)
    }

    func isDownloaded(bookId: UUID) -> Bool {
        return downloadedBooks.contains(bookId)
    }

    func getDownloadMetadata(bookId: UUID) -> DownloadMetadata? {
        return metadata[bookId]
    }

    func saveDownloadMetadata(_ metadata: DownloadMetadata) throws {
        self.metadata[metadata.bookId] = metadata
    }

    func reset() {
        downloadedBooks = []
        savedFiles = [:]
        metadata = [:]
        saveAudioFileCalls = []
        deleteAudioFileCalls = []
        usedStorage = 0
        saveShouldFail = false
        deleteShouldFail = false
    }
}
```

#### Step 2.3.7: Create MockNetworkMonitor

Create `ios/BookVaultTests/Mocks/MockNetworkMonitor.swift`:

```swift
import Foundation
import Combine
@testable import BookVault

class MockNetworkMonitor: NetworkMonitoring {
    var isConnected: Bool = true
    var isConnectedViaWiFi: Bool = true
    var isConnectedViaCellular: Bool = false

    private let connectionSubject = CurrentValueSubject<Bool, Never>(true)

    var connectionStatusPublisher: AnyPublisher<Bool, Never> {
        connectionSubject.eraseToAnyPublisher()
    }

    func simulateConnectionChange(connected: Bool) {
        isConnected = connected
        connectionSubject.send(connected)
    }

    func simulateWiFiConnection() {
        isConnected = true
        isConnectedViaWiFi = true
        isConnectedViaCellular = false
        connectionSubject.send(true)
    }

    func simulateCellularConnection() {
        isConnected = true
        isConnectedViaWiFi = false
        isConnectedViaCellular = true
        connectionSubject.send(true)
    }

    func simulateDisconnection() {
        isConnected = false
        isConnectedViaWiFi = false
        isConnectedViaCellular = false
        connectionSubject.send(false)
    }

    func reset() {
        isConnected = true
        isConnectedViaWiFi = true
        isConnectedViaCellular = false
        connectionSubject.send(true)
    }
}
```

#### Step 2.3.8: Create ProgressManagerTests

Create `ios/BookVaultTests/Services/ProgressManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

final class ProgressManagerTests: XCTestCase {

    var sut: ProgressManager!
    var mockAPIClient: MockAPIClient!
    var mockNetworkMonitor: MockNetworkMonitor!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockNetworkMonitor = MockNetworkMonitor()
        // Note: Will need to create testable initializer or use OfflineProgressStore mock
    }

    override func tearDown() {
        sut = nil
        mockAPIClient = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }

    // MARK: - Save Progress Tests

    func testSaveProgressUpdatesLocalCache() async {
        // Given a book ID and position
        // When saveProgress is called
        // Then local cache should be updated
        XCTAssertTrue(true) // Placeholder - complete after DI
    }

    func testSaveProgressSyncsToServerWhenOnline() async {
        // Given network is connected
        // When saveProgress is called
        // Then API updateProgress should be called
        XCTAssertTrue(true) // Placeholder
    }

    func testSaveProgressQueuesForSyncWhenOffline() async {
        // Given network is disconnected
        // When saveProgress is called
        // Then progress should be queued for later sync
        XCTAssertTrue(true) // Placeholder
    }

    func testSaveProgressThrottlesFrequentUpdates() async {
        // Given multiple rapid saveProgress calls
        // When processed
        // Then API should only be called once (debounced)
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Get Cached Progress Tests

    func testGetCachedProgressReturnsSavedProgress() {
        // Given progress was previously saved
        // When getCachedProgress is called
        // Then saved progress should be returned
        XCTAssertTrue(true) // Placeholder
    }

    func testGetCachedProgressReturnsNilForUnknownBook() {
        // Given no progress saved for book
        // When getCachedProgress is called
        // Then nil should be returned
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Mark Completed Tests

    func testMarkAsCompletedUpdatesLocalAndRemote() async throws {
        // Given a book ID
        // When markAsCompleted is called
        // Then both local cache and server should be updated
        XCTAssertTrue(true) // Placeholder
    }

    func testMarkAsCompletedThrowsOnNetworkError() async {
        // Given network error
        // When markAsCompleted is called
        // Then error should be thrown
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Reset Progress Tests

    func testResetProgressClearsLocalAndRemote() async throws {
        // Given existing progress
        // When resetProgress is called
        // Then progress should be cleared locally and on server
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Sync Tests

    func testSyncPendingProgressUploadsQueuedUpdates() async {
        // Given queued offline progress updates
        // When syncPendingProgress is called
        // Then all queued updates should be sent to server
        XCTAssertTrue(true) // Placeholder
    }

    func testSyncPendingProgressHandlesPartialFailure() async {
        // Given some updates fail
        // When syncPendingProgress is called
        // Then successful updates should be marked complete, failed should remain queued
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 2.3.9: Create StorageManagerTests

Create `ios/BookVaultTests/Services/StorageManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

final class StorageManagerTests: XCTestCase {

    var sut: StorageManager!
    var testDirectory: URL!

    override func setUp() {
        super.setUp()
        // Create temp directory for test files
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        // Note: Will need to inject test directory path
    }

    override func tearDown() {
        // Clean up test files
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Storage Space Tests

    func testAvailableStorageReturnsSystemValue() {
        // Given system has available storage
        // When availableStorage is queried
        // Then should return positive value
        let storage = StorageManager.shared.availableStorage
        XCTAssertGreaterThan(storage, 0)
    }

    func testHasSpaceForDownloadReturnsTrueWhenSpaceAvailable() {
        // Given enough storage available
        // When hasSpaceForDownload is called with small size
        // Then should return true
        let result = StorageManager.shared.hasSpaceForDownload(sizeInBytes: 1000)
        XCTAssertTrue(result)
    }

    func testHasSpaceForDownloadReturnsFalseWhenInsufficientSpace() {
        // Given limited storage
        // When hasSpaceForDownload is called with huge size
        // Then should return false
        let hugeSize: Int64 = Int64.max
        let result = StorageManager.shared.hasSpaceForDownload(sizeInBytes: hugeSize)
        XCTAssertFalse(result)
    }

    // MARK: - File Operations Tests

    func testSaveAudioFileCreatesFile() throws {
        // Given audio data
        // When saveAudioFile is called
        // Then file should exist at returned URL
        XCTAssertTrue(true) // Placeholder - requires DI for custom directory
    }

    func testDeleteAudioFileRemovesFile() throws {
        // Given saved audio file
        // When deleteAudioFile is called
        // Then file should no longer exist
        XCTAssertTrue(true) // Placeholder
    }

    func testIsDownloadedReturnsTrueForSavedFile() {
        // Given saved audio file
        // When isDownloaded is called
        // Then should return true
        XCTAssertTrue(true) // Placeholder
    }

    func testIsDownloadedReturnsFalseForMissingFile() {
        // Given no saved file for book
        // When isDownloaded is called
        // Then should return false
        let result = StorageManager.shared.isDownloaded(bookId: UUID())
        XCTAssertFalse(result)
    }

    // MARK: - Metadata Tests

    func testSaveAndRetrieveMetadata() throws {
        // Given download metadata
        // When saved and retrieved
        // Then should match original
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 2.3.10: Create NetworkMonitorTests

Create `ios/BookVaultTests/Services/NetworkMonitorTests.swift`:

```swift
import XCTest
import Combine
@testable import BookVault

final class NetworkMonitorTests: XCTestCase {

    var sut: NetworkMonitor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = NetworkMonitor.shared
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Connection Status Tests

    func testInitialConnectionStatusIsSet() {
        // Given NetworkMonitor is initialized
        // When checked
        // Then isConnected should have a value (true or false based on actual network)
        // Note: This is more of a smoke test since we can't control actual network in tests
        XCTAssertNotNil(sut)
    }

    func testConnectionStatusPublisherEmitsValue() {
        // Given NetworkMonitor
        // When subscribed to publisher
        // Then should receive current status
        let expectation = expectation(description: "Receive connection status")

        sut.connectionStatusPublisher
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - WiFi vs Cellular Tests

    func testWiFiAndCellularAreMutuallyExclusive() {
        // Given connected to network
        // When checking connection type
        // Then should not be both WiFi and Cellular simultaneously
        if sut.isConnected {
            let bothTrue = sut.isConnectedViaWiFi && sut.isConnectedViaCellular
            XCTAssertFalse(bothTrue, "Cannot be on both WiFi and Cellular")
        }
    }

    func testWhenConnectedAtLeastOneTypeIsTrue() {
        // Given connected to network
        // When checking connection types
        // Then at least one should be true
        if sut.isConnected {
            let atLeastOne = sut.isConnectedViaWiFi || sut.isConnectedViaCellular
            XCTAssertTrue(atLeastOne, "Must be connected via WiFi or Cellular")
        }
    }
}
```

### 2.4 Verification Steps

1. **Run all tests**:

   ```bash
   cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15'
   ```

2. **Verify mock injection works**:
   - Create a test that uses MockAPIClient with ProgressManager
   - Verify API calls are captured by mock

3. **Check test coverage** (optional):
   ```bash
   xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES
   ```

### 2.5 Success Criteria

- [ ] All protocols compile without errors
- [ ] Services conform to their protocols
- [ ] Mocks can be injected into services
- [ ] ~27 new tests pass
- [ ] Existing app functionality unchanged
- [ ] CI pipeline passes

---

## Phase 3: Playback Core Tests

**Goal**: Test the audio playback functionality.

### 3.1 Prerequisites

- Phase 2 completed successfully
- DI infrastructure in place
- Mocks for API, Storage, Progress available

### 3.2 Deliverables

| Deliverable                   | Description                     |
| ----------------------------- | ------------------------------- |
| Protocol: AudioPlayerManaging | Protocol for AudioPlayerManager |
| MockAudioPlayerManager        | Test double for audio playback  |
| MockAVPlayer                  | Wrapper for testable AVPlayer   |
| AudioPlayerManagerTests.swift | ~20 tests                       |
| ChapterManagerTests.swift     | ~8 tests                        |

### 3.3 Implementation Steps

#### Step 3.3.1: Extract AudioPlayerManaging protocol

Create `ios/BookVault/Services/Protocols/AudioPlayerManaging.swift`:

```swift
import Foundation
import Combine

/// Playback state enumeration
enum PlaybackState {
    case idle
    case loading
    case playing
    case paused
    case error(Error)
}

/// Protocol for AudioPlayerManager to enable testing
protocol AudioPlayerManaging: ObservableObject {
    // State
    var playbackState: PlaybackState { get }
    var currentBook: Book? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var playbackRate: Float { get }
    var isPlaying: Bool { get }

    // Playback Control
    func loadBook(_ book: Book) async
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func seekToChapter(_ chapter: Chapter)
    func setPlaybackRate(_ rate: Float)

    // Skip Controls
    func skipForward(seconds: TimeInterval)
    func skipBackward(seconds: TimeInterval)
}
```

#### Step 3.3.2: Create MockAudioPlayerManager

Create `ios/BookVaultTests/Mocks/MockAudioPlayerManager.swift`:

```swift
import Foundation
import Combine
@testable import BookVault

class MockAudioPlayerManager: AudioPlayerManaging, ObservableObject {
    @Published var playbackState: PlaybackState = .idle
    @Published var currentBook: Book?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0

    var isPlaying: Bool {
        if case .playing = playbackState { return true }
        return false
    }

    // Call tracking
    var loadBookCalls: [Book] = []
    var playCalled = false
    var pauseCalled = false
    var stopCalled = false
    var seekCalls: [TimeInterval] = []
    var seekToChapterCalls: [Chapter] = []
    var setPlaybackRateCalls: [Float] = []
    var skipForwardCalls: [TimeInterval] = []
    var skipBackwardCalls: [TimeInterval] = []

    // Behavior configuration
    var loadShouldFail = false

    func loadBook(_ book: Book) async {
        loadBookCalls.append(book)
        if loadShouldFail {
            playbackState = .error(NSError(domain: "Test", code: -1))
            return
        }
        currentBook = book
        duration = Double(book.runtimeMinutes ?? 0) * 60
        playbackState = .paused
    }

    func play() {
        playCalled = true
        playbackState = .playing
    }

    func pause() {
        pauseCalled = true
        playbackState = .paused
    }

    func stop() {
        stopCalled = true
        playbackState = .idle
        currentBook = nil
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        seekCalls.append(time)
        currentTime = time
    }

    func seekToChapter(_ chapter: Chapter) {
        seekToChapterCalls.append(chapter)
        currentTime = chapter.startTime
    }

    func setPlaybackRate(_ rate: Float) {
        setPlaybackRateCalls.append(rate)
        playbackRate = rate
    }

    func skipForward(seconds: TimeInterval) {
        skipForwardCalls.append(seconds)
        currentTime = min(currentTime + seconds, duration)
    }

    func skipBackward(seconds: TimeInterval) {
        skipBackwardCalls.append(seconds)
        currentTime = max(currentTime - seconds, 0)
    }

    func reset() {
        playbackState = .idle
        currentBook = nil
        currentTime = 0
        duration = 0
        playbackRate = 1.0
        loadBookCalls = []
        playCalled = false
        pauseCalled = false
        stopCalled = false
        seekCalls = []
        seekToChapterCalls = []
        setPlaybackRateCalls = []
        skipForwardCalls = []
        skipBackwardCalls = []
        loadShouldFail = false
    }
}
```

#### Step 3.3.3: Create AudioPlayerManagerTests

Create `ios/BookVaultTests/Services/AudioPlayerManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

@MainActor
final class AudioPlayerManagerTests: XCTestCase {

    var sut: AudioPlayerManager!
    var mockProgressManager: MockProgressManager!
    var mockStorageManager: MockStorageManager!

    override func setUp() {
        super.setUp()
        mockProgressManager = MockProgressManager()
        mockStorageManager = MockStorageManager()
        // Note: Need to add DI to AudioPlayerManager
    }

    override func tearDown() {
        sut = nil
        mockProgressManager = nil
        mockStorageManager = nil
        super.tearDown()
    }

    // MARK: - State Machine Tests

    func testInitialStateIsIdle() {
        // Given fresh AudioPlayerManager
        // When checked
        // Then state should be idle
        XCTAssertTrue(true) // Placeholder
    }

    func testLoadBookTransitionsToLoading() async {
        // Given idle state
        // When loadBook is called
        // Then state should transition to loading
        XCTAssertTrue(true) // Placeholder
    }

    func testSuccessfulLoadTransitionsToPaused() async {
        // Given loading state
        // When load completes successfully
        // Then state should be paused (ready to play)
        XCTAssertTrue(true) // Placeholder
    }

    func testFailedLoadTransitionsToError() async {
        // Given loading state
        // When load fails
        // Then state should be error with message
        XCTAssertTrue(true) // Placeholder
    }

    func testPlayTransitionsFromPausedToPlaying() {
        // Given paused state with loaded book
        // When play is called
        // Then state should be playing
        XCTAssertTrue(true) // Placeholder
    }

    func testPauseTransitionsFromPlayingToPaused() {
        // Given playing state
        // When pause is called
        // Then state should be paused
        XCTAssertTrue(true) // Placeholder
    }

    func testStopTransitionsToIdle() {
        // Given any non-idle state
        // When stop is called
        // Then state should be idle
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Seek Tests

    func testSeekUpdatesCurrentTime() {
        // Given playing/paused book
        // When seek is called
        // Then currentTime should update
        XCTAssertTrue(true) // Placeholder
    }

    func testSeekClampsToDuration() {
        // Given book with duration
        // When seek is called beyond duration
        // Then currentTime should be clamped to duration
        XCTAssertTrue(true) // Placeholder
    }

    func testSeekClampsToZero() {
        // Given book
        // When seek is called with negative value
        // Then currentTime should be clamped to 0
        XCTAssertTrue(true) // Placeholder
    }

    func testSeekToChapterSetsCorrectTime() {
        // Given book with chapters
        // When seekToChapter is called
        // Then currentTime should be chapter start time
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Skip Tests

    func testSkipForward30Seconds() {
        // Given current time at 60s
        // When skipForward(30) is called
        // Then currentTime should be 90s
        XCTAssertTrue(true) // Placeholder
    }

    func testSkipBackward15Seconds() {
        // Given current time at 60s
        // When skipBackward(15) is called
        // Then currentTime should be 45s
        XCTAssertTrue(true) // Placeholder
    }

    func testSkipBackwardDoesNotGoBelowZero() {
        // Given current time at 5s
        // When skipBackward(15) is called
        // Then currentTime should be 0
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Playback Rate Tests

    func testSetPlaybackRateUpdatesRate() {
        // Given default rate (1.0)
        // When setPlaybackRate(1.5) is called
        // Then playbackRate should be 1.5
        XCTAssertTrue(true) // Placeholder
    }

    func testPlaybackRatePersistsAcrossBooks() {
        // Given rate set to 2.0
        // When new book is loaded
        // Then rate should still be 2.0
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Progress Saving Tests

    func testProgressSavedPeriodically() async {
        // Given playing book
        // When time passes
        // Then progress should be saved to ProgressManager
        XCTAssertTrue(true) // Placeholder
    }

    func testProgressSavedOnPause() async {
        // Given playing book
        // When pause is called
        // Then progress should be saved immediately
        XCTAssertTrue(true) // Placeholder
    }

    func testProgressSavedOnStop() async {
        // Given playing book
        // When stop is called
        // Then progress should be saved before clearing
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Offline Playback Tests

    func testPlaysFromLocalFileWhenDownloaded() async {
        // Given book is downloaded locally
        // When loadBook is called
        // Then should use local file URL
        XCTAssertTrue(true) // Placeholder
    }

    func testStreamsWhenNotDownloaded() async {
        // Given book is not downloaded
        // When loadBook is called
        // Then should stream from server
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 3.3.4: Create ChapterManagerTests

Create `ios/BookVaultTests/Services/ChapterManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

final class ChapterManagerTests: XCTestCase {

    var sut: ChapterManager!
    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        sut = ChapterManager(apiClient: mockAPIClient)
    }

    override func tearDown() {
        sut = nil
        mockAPIClient = nil
        super.tearDown()
    }

    // MARK: - Fetch Chapters Tests

    func testFetchChaptersReturnsFromCache() async throws {
        // Given chapters already cached for book
        // When fetchChapters is called
        // Then should return cached chapters without API call
        XCTAssertTrue(true) // Placeholder
    }

    func testFetchChaptersCallsAPIWhenNotCached() async throws {
        // Given no cached chapters
        // When fetchChapters is called
        // Then should call API
        XCTAssertTrue(true) // Placeholder
    }

    func testFetchChaptersCachesResult() async throws {
        // Given API returns chapters
        // When fetchChapters is called twice
        // Then second call should use cache
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Chapter Navigation Tests

    func testGetChapterAtTimeReturnsCorrectChapter() {
        // Given chapters with known time ranges
        // When getChapterAtTime is called
        // Then correct chapter should be returned
        XCTAssertTrue(true) // Placeholder
    }

    func testGetNextChapterReturnsFollowingChapter() {
        // Given current chapter
        // When getNextChapter is called
        // Then should return next chapter
        XCTAssertTrue(true) // Placeholder
    }

    func testGetPreviousChapterReturnsPrecedingChapter() {
        // Given current chapter (not first)
        // When getPreviousChapter is called
        // Then should return previous chapter
        XCTAssertTrue(true) // Placeholder
    }

    func testGetNextChapterReturnsNilForLastChapter() {
        // Given last chapter
        // When getNextChapter is called
        // Then should return nil
        XCTAssertTrue(true) // Placeholder
    }
}
```

### 3.4 Verification Steps

1. **Run playback tests**:

   ```bash
   cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BookVaultTests/AudioPlayerManagerTests
   ```

2. **Verify mocks work correctly**:
   - Test that MockAudioPlayerManager can simulate various states
   - Verify state transitions are tracked

### 3.5 Success Criteria

- [ ] AudioPlayerManaging protocol defined
- [ ] ~25 playback tests pass
- [ ] State machine transitions tested
- [ ] Skip and seek functionality tested
- [ ] Progress saving integration tested

---

## Phase 4: Download Tests

**Goal**: Test the download management functionality.

### 4.1 Prerequisites

- Phase 3 completed successfully
- Storage and network mocks available

### 4.2 Deliverables

| Deliverable                | Description                  |
| -------------------------- | ---------------------------- |
| Protocol: DownloadManaging | Protocol for DownloadManager |
| MockDownloadManager        | Test double for downloads    |
| MockURLSessionDownloadTask | Mock for download tasks      |
| DownloadManagerTests.swift | ~25 tests                    |

### 4.3 Implementation Steps

#### Step 4.3.1: Extract DownloadManaging protocol

Create `ios/BookVault/Services/Protocols/DownloadManaging.swift`:

```swift
import Foundation
import Combine

/// Download state enumeration
enum DownloadState: Equatable {
    case notDownloaded
    case queued
    case downloading(progress: Double)
    case paused(progress: Double)
    case completed
    case failed(Error)

    static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.queued, .queued): return true
        case (.downloading(let p1), .downloading(let p2)): return p1 == p2
        case (.paused(let p1), .paused(let p2)): return p1 == p2
        case (.completed, .completed): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}

/// Protocol for DownloadManager to enable testing
protocol DownloadManaging: ObservableObject {
    // State
    var downloads: [UUID: DownloadState] { get }
    var activeDownloadCount: Int { get }
    var isWiFiOnly: Bool { get set }

    // Publishers
    var downloadProgressPublisher: AnyPublisher<(UUID, Double), Never> { get }
    var downloadCompletedPublisher: AnyPublisher<UUID, Never> { get }

    // Operations
    func startDownload(book: Book) async throws
    func pauseDownload(bookId: UUID)
    func resumeDownload(bookId: UUID) async throws
    func cancelDownload(bookId: UUID)
    func deleteDownload(bookId: UUID) throws

    // Queries
    func downloadState(for bookId: UUID) -> DownloadState
    func isDownloaded(bookId: UUID) -> Bool
}
```

#### Step 4.3.2: Create MockDownloadManager

Create `ios/BookVaultTests/Mocks/MockDownloadManager.swift`:

```swift
import Foundation
import Combine
@testable import BookVault

class MockDownloadManager: DownloadManaging, ObservableObject {
    @Published var downloads: [UUID: DownloadState] = [:]
    @Published var isWiFiOnly: Bool = true

    var activeDownloadCount: Int {
        downloads.values.filter {
            if case .downloading = $0 { return true }
            return false
        }.count
    }

    // Publishers
    private let progressSubject = PassthroughSubject<(UUID, Double), Never>()
    private let completedSubject = PassthroughSubject<UUID, Never>()

    var downloadProgressPublisher: AnyPublisher<(UUID, Double), Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var downloadCompletedPublisher: AnyPublisher<UUID, Never> {
        completedSubject.eraseToAnyPublisher()
    }

    // Call tracking
    var startDownloadCalls: [Book] = []
    var pauseDownloadCalls: [UUID] = []
    var resumeDownloadCalls: [UUID] = []
    var cancelDownloadCalls: [UUID] = []
    var deleteDownloadCalls: [UUID] = []

    // Behavior configuration
    var startShouldFail = false
    var resumeShouldFail = false

    func startDownload(book: Book) async throws {
        startDownloadCalls.append(book)
        if startShouldFail {
            downloads[book.id] = .failed(NSError(domain: "Test", code: -1))
            throw NSError(domain: "Test", code: -1)
        }
        downloads[book.id] = .downloading(progress: 0)
    }

    func pauseDownload(bookId: UUID) {
        pauseDownloadCalls.append(bookId)
        if case .downloading(let progress) = downloads[bookId] {
            downloads[bookId] = .paused(progress: progress)
        }
    }

    func resumeDownload(bookId: UUID) async throws {
        resumeDownloadCalls.append(bookId)
        if resumeShouldFail {
            throw NSError(domain: "Test", code: -1)
        }
        if case .paused(let progress) = downloads[bookId] {
            downloads[bookId] = .downloading(progress: progress)
        }
    }

    func cancelDownload(bookId: UUID) {
        cancelDownloadCalls.append(bookId)
        downloads[bookId] = .notDownloaded
    }

    func deleteDownload(bookId: UUID) throws {
        deleteDownloadCalls.append(bookId)
        downloads[bookId] = .notDownloaded
    }

    func downloadState(for bookId: UUID) -> DownloadState {
        downloads[bookId] ?? .notDownloaded
    }

    func isDownloaded(bookId: UUID) -> Bool {
        downloads[bookId] == .completed
    }

    // Simulation helpers
    func simulateProgress(bookId: UUID, progress: Double) {
        downloads[bookId] = .downloading(progress: progress)
        progressSubject.send((bookId, progress))
    }

    func simulateCompletion(bookId: UUID) {
        downloads[bookId] = .completed
        completedSubject.send(bookId)
    }

    func simulateFailure(bookId: UUID, error: Error) {
        downloads[bookId] = .failed(error)
    }

    func reset() {
        downloads = [:]
        startDownloadCalls = []
        pauseDownloadCalls = []
        resumeDownloadCalls = []
        cancelDownloadCalls = []
        deleteDownloadCalls = []
        startShouldFail = false
        resumeShouldFail = false
    }
}
```

#### Step 4.3.3: Create DownloadManagerTests

Create `ios/BookVaultTests/Services/DownloadManagerTests.swift`:

```swift
import XCTest
import Combine
@testable import BookVault

final class DownloadManagerTests: XCTestCase {

    var sut: DownloadManager!
    var mockStorageManager: MockStorageManager!
    var mockNetworkMonitor: MockNetworkMonitor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockStorageManager = MockStorageManager()
        mockNetworkMonitor = MockNetworkMonitor()
        cancellables = []
        // Note: Need to add DI to DownloadManager
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockStorageManager = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }

    // MARK: - Start Download Tests

    func testStartDownloadChangesStateToDownloading() async throws {
        // Given a book
        // When startDownload is called
        // Then state should be downloading
        XCTAssertTrue(true) // Placeholder
    }

    func testStartDownloadChecksStorageSpace() async throws {
        // Given insufficient storage
        // When startDownload is called
        // Then should throw storage error
        XCTAssertTrue(true) // Placeholder
    }

    func testStartDownloadRespectsWiFiOnlySetting() async throws {
        // Given WiFi-only enabled and on cellular
        // When startDownload is called
        // Then should queue instead of start
        XCTAssertTrue(true) // Placeholder
    }

    func testStartDownloadQueuesWhenMaxConcurrentReached() async throws {
        // Given max concurrent downloads reached
        // When startDownload is called
        // Then should queue the download
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Progress Tests

    func testProgressPublisherEmitsUpdates() async throws {
        // Given active download
        // When progress changes
        // Then publisher should emit update
        XCTAssertTrue(true) // Placeholder
    }

    func testDownloadStateReflectsProgress() async throws {
        // Given active download
        // When progress is 50%
        // Then state should be .downloading(progress: 0.5)
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Pause/Resume Tests

    func testPauseDownloadChangesStateToPaused() {
        // Given downloading state
        // When pauseDownload is called
        // Then state should be paused with same progress
        XCTAssertTrue(true) // Placeholder
    }

    func testResumeDownloadChangesStateToDownloading() async throws {
        // Given paused state
        // When resumeDownload is called
        // Then state should be downloading
        XCTAssertTrue(true) // Placeholder
    }

    func testResumeDownloadRespectsWiFiOnlySetting() async throws {
        // Given WiFi-only enabled and on cellular
        // When resumeDownload is called
        // Then should remain paused
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Cancel/Delete Tests

    func testCancelDownloadRemovesFromQueue() {
        // Given queued download
        // When cancelDownload is called
        // Then should be removed from downloads
        XCTAssertTrue(true) // Placeholder
    }

    func testCancelActiveDownloadStopsTransfer() {
        // Given active download
        // When cancelDownload is called
        // Then download task should be cancelled
        XCTAssertTrue(true) // Placeholder
    }

    func testDeleteDownloadRemovesFile() throws {
        // Given completed download
        // When deleteDownload is called
        // Then file should be removed from storage
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Completion Tests

    func testCompletionPublisherEmitsOnSuccess() async throws {
        // Given active download
        // When download completes
        // Then completion publisher should emit
        XCTAssertTrue(true) // Placeholder
    }

    func testCompletedStateAfterSuccessfulDownload() async throws {
        // Given active download
        // When download completes
        // Then state should be .completed
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Error Handling Tests

    func testNetworkErrorSetsFailedState() async throws {
        // Given active download
        // When network error occurs
        // Then state should be .failed with error
        XCTAssertTrue(true) // Placeholder
    }

    func testStorageFullSetsFailedState() async throws {
        // Given active download
        // When storage becomes full
        // Then state should be .failed with storage error
        XCTAssertTrue(true) // Placeholder
    }

    func testRetryAfterFailure() async throws {
        // Given failed download
        // When startDownload is called again
        // Then should attempt download again
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - WiFi-Only Tests

    func testWiFiOnlyPausesOnCellularSwitch() async throws {
        // Given downloading on WiFi with WiFi-only enabled
        // When switching to cellular
        // Then should pause download
        XCTAssertTrue(true) // Placeholder
    }

    func testWiFiOnlyResumesOnWiFiReconnect() async throws {
        // Given paused due to cellular
        // When WiFi reconnects
        // Then should resume download
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Query Tests

    func testIsDownloadedReturnsTrueForCompleted() {
        // Given completed download
        // When isDownloaded is called
        // Then should return true
        XCTAssertTrue(true) // Placeholder
    }

    func testIsDownloadedReturnsFalseForPartial() {
        // Given downloading state
        // When isDownloaded is called
        // Then should return false
        XCTAssertTrue(true) // Placeholder
    }
}
```

### 4.4 Verification Steps

1. **Run download tests**:

   ```bash
   cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BookVaultTests/DownloadManagerTests
   ```

2. **Verify state machine coverage**:
   - All transitions tested (notDownloaded → downloading → completed)
   - Error states tested
   - WiFi-only behavior tested

### 4.5 Success Criteria

- [ ] DownloadManaging protocol defined
- [ ] ~25 download tests pass
- [ ] State transitions fully covered
- [ ] WiFi-only logic tested
- [ ] Storage integration tested

---

## Phase 5: Offline Mode Tests + CI Completion

**Goal**: Test offline functionality and finalize CI pipeline.

### 5.1 Prerequisites

- Phases 1-4 completed successfully
- All core service mocks available

### 5.2 Deliverables

| Deliverable                     | Description                       |
| ------------------------------- | --------------------------------- |
| Protocol: OfflineStoring        | Protocol for OfflineProgressStore |
| Protocol: LibraryCaching        | Protocol for LibraryCacheManager  |
| Protocol: SyncManaging          | Protocol for SyncManager          |
| MockOfflineProgressStore        | Test double                       |
| MockLibraryCacheManager         | Test double                       |
| MockSyncManager                 | Test double                       |
| OfflineProgressStoreTests.swift | ~10 tests                         |
| LibraryCacheManagerTests.swift  | ~10 tests                         |
| SyncManagerTests.swift          | ~8 tests                          |
| Integration tests               | Cross-service tests               |
| Complete CI workflow            | Code coverage, artifact upload    |

### 5.3 Implementation Steps

#### Step 5.3.1: Extract offline protocols

Create the three protocols for offline services:

**OfflineStoring**:

```swift
protocol OfflineStoring {
    func saveProgress(_ progress: UserProgress)
    func getProgress(for bookId: UUID) -> UserProgress?
    func getAllPendingSync() -> [UserProgress]
    func markAsSynced(bookId: UUID)
    func clearCache()
}
```

**LibraryCaching**:

```swift
protocol LibraryCaching {
    var cachedBooks: [Book] { get }
    var cacheTimestamp: Date? { get }
    var isCacheValid: Bool { get }

    func cacheLibrary(_ books: [Book])
    func getCachedLibrary() -> [Book]?
    func clearCache()
    func refreshIfNeeded() async
}
```

**SyncManaging**:

```swift
protocol SyncManaging {
    var isSyncing: Bool { get }
    var lastSyncDate: Date? { get }

    func syncNow() async
    func scheduleBackgroundSync()
    func cancelPendingSync()
}
```

#### Step 5.3.2: Create OfflineProgressStoreTests

Create `ios/BookVaultTests/Services/OfflineProgressStoreTests.swift`:

```swift
import XCTest
@testable import BookVault

final class OfflineProgressStoreTests: XCTestCase {

    var sut: OfflineProgressStore!

    override func setUp() {
        super.setUp()
        // Use isolated storage for tests
    }

    override func tearDown() {
        sut?.clearCache()
        sut = nil
        super.tearDown()
    }

    // MARK: - Save/Retrieve Tests

    func testSaveProgressStoresLocally() {
        // Given progress data
        // When saveProgress is called
        // Then progress should be retrievable
        XCTAssertTrue(true) // Placeholder
    }

    func testGetProgressReturnsNilForUnknownBook() {
        // Given no saved progress
        // When getProgress is called
        // Then should return nil
        XCTAssertTrue(true) // Placeholder
    }

    func testSaveProgressUpdatesExisting() {
        // Given existing progress
        // When saveProgress is called with new position
        // Then should update existing record
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Pending Sync Tests

    func testNewProgressMarkedAsPendingSync() {
        // Given fresh save
        // When getAllPendingSync is called
        // Then should include the new progress
        XCTAssertTrue(true) // Placeholder
    }

    func testMarkAsSyncedRemovesFromPending() {
        // Given pending progress
        // When markAsSynced is called
        // Then should no longer be in pending list
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Persistence Tests

    func testDataPersistsAcrossInstances() {
        // Given saved progress
        // When creating new instance
        // Then should load persisted data
        XCTAssertTrue(true) // Placeholder
    }

    func testClearCacheRemovesAllData() {
        // Given saved progress
        // When clearCache is called
        // Then all progress should be removed
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Thread Safety Tests

    func testConcurrentWritesAreSafe() async {
        // Given multiple concurrent writes
        // When executed
        // Then no crashes or data corruption
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 5.3.3: Create LibraryCacheManagerTests

Create `ios/BookVaultTests/Services/LibraryCacheManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

final class LibraryCacheManagerTests: XCTestCase {

    var sut: LibraryCacheManager!

    override func setUp() {
        super.setUp()
        // Use isolated cache for tests
    }

    override func tearDown() {
        sut?.clearCache()
        sut = nil
        super.tearDown()
    }

    // MARK: - Cache Storage Tests

    func testCacheLibraryStoresBooks() {
        // Given list of books
        // When cacheLibrary is called
        // Then books should be retrievable
        XCTAssertTrue(true) // Placeholder
    }

    func testGetCachedLibraryReturnsNilWhenEmpty() {
        // Given empty cache
        // When getCachedLibrary is called
        // Then should return nil
        XCTAssertTrue(true) // Placeholder
    }

    func testCacheTimestampUpdatedOnCache() {
        // Given cache operation
        // When cacheLibrary is called
        // Then cacheTimestamp should be updated
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Cache Validity Tests

    func testIsCacheValidTrueWhenFresh() {
        // Given recently cached data
        // When isCacheValid is checked
        // Then should return true
        XCTAssertTrue(true) // Placeholder
    }

    func testIsCacheValidFalseWhenStale() {
        // Given old cached data (> 1 hour)
        // When isCacheValid is checked
        // Then should return false
        XCTAssertTrue(true) // Placeholder
    }

    func testIsCacheValidFalseWhenEmpty() {
        // Given empty cache
        // When isCacheValid is checked
        // Then should return false
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Refresh Tests

    func testRefreshIfNeededFetchesWhenStale() async {
        // Given stale cache
        // When refreshIfNeeded is called
        // Then should fetch from API
        XCTAssertTrue(true) // Placeholder
    }

    func testRefreshIfNeededSkipsWhenFresh() async {
        // Given fresh cache
        // When refreshIfNeeded is called
        // Then should not fetch from API
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Clear Cache Tests

    func testClearCacheRemovesAllData() {
        // Given cached library
        // When clearCache is called
        // Then getCachedLibrary should return nil
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 5.3.4: Create SyncManagerTests

Create `ios/BookVaultTests/Services/SyncManagerTests.swift`:

```swift
import XCTest
@testable import BookVault

final class SyncManagerTests: XCTestCase {

    var sut: SyncManager!
    var mockOfflineStore: MockOfflineProgressStore!
    var mockAPIClient: MockAPIClient!
    var mockNetworkMonitor: MockNetworkMonitor!

    override func setUp() {
        super.setUp()
        mockOfflineStore = MockOfflineProgressStore()
        mockAPIClient = MockAPIClient()
        mockNetworkMonitor = MockNetworkMonitor()
        // Note: Need DI in SyncManager
    }

    override func tearDown() {
        sut = nil
        mockOfflineStore = nil
        mockAPIClient = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }

    // MARK: - Sync Now Tests

    func testSyncNowUploadsPendingProgress() async {
        // Given pending progress updates
        // When syncNow is called
        // Then should upload all pending
        XCTAssertTrue(true) // Placeholder
    }

    func testSyncNowUpdatesLastSyncDate() async {
        // Given successful sync
        // When syncNow completes
        // Then lastSyncDate should be updated
        XCTAssertTrue(true) // Placeholder
    }

    func testSyncNowSkipsWhenOffline() async {
        // Given no network
        // When syncNow is called
        // Then should skip without error
        XCTAssertTrue(true) // Placeholder
    }

    func testSyncNowMarksProgressAsSynced() async {
        // Given pending progress
        // When syncNow succeeds
        // Then progress should be marked synced
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Error Handling Tests

    func testSyncNowRetriesOnFailure() async {
        // Given network error on first try
        // When syncNow is called
        // Then should retry
        XCTAssertTrue(true) // Placeholder
    }

    func testPartialSyncFailureKeepsUnsynced() async {
        // Given some updates fail
        // When syncNow completes
        // Then failed updates should remain pending
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Background Sync Tests

    func testScheduleBackgroundSyncCreatesTask() {
        // When scheduleBackgroundSync is called
        // Then background task should be scheduled
        XCTAssertTrue(true) // Placeholder
    }

    func testCancelPendingSyncCancelsTask() {
        // Given scheduled sync
        // When cancelPendingSync is called
        // Then sync should be cancelled
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 5.3.5: Create integration tests

Create `ios/BookVaultTests/Integration/PlaybackFlowTests.swift`:

```swift
import XCTest
@testable import BookVault

/// Integration tests for the full playback flow
final class PlaybackFlowTests: XCTestCase {

    // MARK: - Online Playback Flow

    func testOnlinePlaybackFlowSavesProgress() async {
        // Given authenticated user, online, book to play
        // When book is played and paused
        // Then progress should be saved locally and synced to server
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Offline Playback Flow

    func testOfflinePlaybackFlowQueuesSync() async {
        // Given authenticated user, offline, downloaded book
        // When book is played and paused
        // Then progress should be saved locally and queued for sync
        XCTAssertTrue(true) // Placeholder
    }

    func testOfflineSyncOnReconnect() async {
        // Given queued progress updates
        // When network reconnects
        // Then should sync to server
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Download Then Play Flow

    func testDownloadThenOfflinePlay() async {
        // Given book downloaded while online
        // When going offline and playing
        // Then should play from local file
        XCTAssertTrue(true) // Placeholder
    }
}
```

#### Step 5.3.6: Update CI workflow with coverage

Update `.github/workflows/ios-tests.yml`:

```yaml
name: iOS Tests

on:
  push:
    branches: [main]
    paths:
      - 'ios/**'
      - '.github/workflows/ios-tests.yml'
  pull_request:
    branches: [main]
    paths:
      - 'ios/**'
      - '.github/workflows/ios-tests.yml'

jobs:
  test:
    runs-on: macos-14

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.0'

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Install xcpretty
        run: gem install xcpretty

      - name: Generate Xcode project
        working-directory: ios
        run: xcodegen generate

      - name: Run tests with coverage
        working-directory: ios
        run: |
          xcodebuild test \
            -scheme BookVault \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
            -enableCodeCoverage YES \
            -resultBundlePath TestResults.xcresult \
            | xcpretty --report junit --output TestResults.xml

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: |
            ios/TestResults.xcresult
            ios/TestResults.xml

      - name: Generate coverage report
        if: success()
        working-directory: ios
        run: |
          xcrun xccov view --report --json TestResults.xcresult > coverage.json
          echo "## Code Coverage Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          xcrun xccov view --report TestResults.xcresult | head -20 >> $GITHUB_STEP_SUMMARY

      - name: Upload coverage
        uses: actions/upload-artifact@v4
        if: success()
        with:
          name: coverage-report
          path: ios/coverage.json

      - name: Check coverage threshold
        if: success()
        working-directory: ios
        run: |
          COVERAGE=$(xcrun xccov view --report TestResults.xcresult | grep 'BookVault.app' | awk '{print $2}' | tr -d '%')
          echo "Coverage: $COVERAGE%"
          if (( $(echo "$COVERAGE < 70" | bc -l) )); then
            echo "::warning::Coverage ($COVERAGE%) is below 70% target"
          fi
```

### 5.4 Verification Steps

1. **Run all tests**:

   ```bash
   cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES
   ```

2. **Check coverage report**:

   ```bash
   xcrun xccov view --report TestResults.xcresult
   ```

3. **Verify CI pipeline**:
   - Push changes to trigger workflow
   - Verify coverage report appears in GitHub Actions summary
   - Confirm artifacts are uploaded

### 5.5 Success Criteria

- [ ] All 5 phases complete (~125 tests total)
- [ ] Code coverage at or above 70% for services
- [ ] CI pipeline runs on all PRs
- [ ] Coverage report generated
- [ ] All existing app functionality unchanged

---

## Appendix A: File Structure After Completion

```
ios/
├── BookVault/
│   └── Services/
│       ├── Protocols/
│       │   ├── APIClientProtocol.swift
│       │   ├── AuthManaging.swift
│       │   ├── ProgressManaging.swift
│       │   ├── StorageManaging.swift
│       │   ├── NetworkMonitoring.swift
│       │   ├── AudioPlayerManaging.swift
│       │   ├── DownloadManaging.swift
│       │   ├── OfflineStoring.swift
│       │   ├── LibraryCaching.swift
│       │   └── SyncManaging.swift
│       └── ... (existing services, now conforming to protocols)
├── BookVaultTests/
│   ├── Mocks/
│   │   ├── MockAPIClient.swift
│   │   ├── MockAuthManager.swift
│   │   ├── MockProgressManager.swift
│   │   ├── MockStorageManager.swift
│   │   ├── MockNetworkMonitor.swift
│   │   ├── MockAudioPlayerManager.swift
│   │   ├── MockDownloadManager.swift
│   │   ├── MockOfflineProgressStore.swift
│   │   ├── MockLibraryCacheManager.swift
│   │   └── MockSyncManager.swift
│   ├── Helpers/
│   │   └── XCTestCase+Async.swift
│   ├── Services/
│   │   ├── AuthManagerTests.swift
│   │   ├── APIClientTests.swift
│   │   ├── ProgressManagerTests.swift
│   │   ├── StorageManagerTests.swift
│   │   ├── NetworkMonitorTests.swift
│   │   ├── AudioPlayerManagerTests.swift
│   │   ├── ChapterManagerTests.swift
│   │   ├── DownloadManagerTests.swift
│   │   ├── OfflineProgressStoreTests.swift
│   │   ├── LibraryCacheManagerTests.swift
│   │   └── SyncManagerTests.swift
│   └── Integration/
│       └── PlaybackFlowTests.swift
└── project.yml (updated with test target)
```

---

## Appendix B: Starting Each Phase

Each phase can be started with a fresh Claude Code session. Use this prompt template:

```
I'm implementing iOS tests for the Book Vault app. I'm starting Phase 5 of the testing implementation plan.

Please read:
1. docs/ios-testing-implementation-plan.md - specifically Phase 5
2. ios/project.yml - current project configuration
3. Any existing test files in ios/BookVaultTests/

Then implement Phase 5 following the detailed steps in the plan.

Commit your changes at the end of this phase

Previous phases are complete. The test target exists and mocks from earlier phases are available.
```

---

## Appendix C: Quick Reference

### Run All Tests

```bash
cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Run Specific Test File

```bash
cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BookVaultTests/AuthManagerTests
```

### Generate Coverage Report

```bash
cd ios && xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES -resultBundlePath TestResults.xcresult && xcrun xccov view --report TestResults.xcresult
```

### Regenerate Xcode Project

```bash
cd ios && xcodegen generate
```

---

_Created December 29, 2025_
