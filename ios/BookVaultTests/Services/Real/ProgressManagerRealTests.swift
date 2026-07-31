//
//  ProgressManagerRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 3: Real Services Testing - ProgressManager
//
//  Tests the real ProgressManager implementation with mocked dependencies.
//

import XCTest
@testable import BookVault

final class ProgressManagerRealTests: XCTestCase {
    // MARK: - Properties

    private var progressManager: ProgressManager!
    private var mockAPIClient: MockAPIClient!
    private var mockOfflineStore: MockOfflineProgressStore!
    private var mockNetworkMonitor: MockNetworkMonitor!

    // MARK: - Setup & Teardown

    // `@MainActor` because the type under test has a main-actor isolated
    // init. Legal on the async form of setUp, unlike the synchronous one.
    @MainActor
    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        mockOfflineStore = MockOfflineProgressStore()
        mockNetworkMonitor = MockNetworkMonitor()

        progressManager = ProgressManager(
            apiClient: mockAPIClient,
            offlineStore: mockOfflineStore,
            networkMonitor: mockNetworkMonitor
        )
    }

    override func tearDown() async throws {
        progressManager = nil
        mockAPIClient = nil
        mockOfflineStore = nil
        mockNetworkMonitor = nil
    }

    // MARK: - Fetch Progress Tests (Online)

    @MainActor
    func testFetchProgress_WhenOnline_FetchesFromServer() async throws {
        // Given: Online and server has progress
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        let serverProgress = TestFixtures.makeGetProgressResponse(
            positionSeconds: 300.0,
            completed: false,
            lastPlayed: Date()
        )
        mockAPIClient.fetchProgressResult = .success(serverProgress)

        // When: Fetching progress
        let result = try await progressManager.fetchProgress(for: bookId.uuidString)

        // Then: Returns server progress
        XCTAssertEqual(result.positionSeconds, 300.0)
        XCTAssertFalse(result.completed)
        XCTAssertEqual(mockAPIClient.fetchProgressCalls.count, 1)
    }

    @MainActor
    func testFetchProgress_WhenOnline_UpdatesLocalCacheFromServer() async throws {
        // Given: Online with server progress
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        let serverDate = Date()
        let serverProgress = TestFixtures.makeGetProgressResponse(
            positionSeconds: 500.0,
            completed: false,
            lastPlayed: serverDate
        )
        mockAPIClient.fetchProgressResult = .success(serverProgress)

        // When: Fetching progress
        _ = try await progressManager.fetchProgress(for: bookId.uuidString)

        // Then: Updates local cache from server
        XCTAssertEqual(mockOfflineStore.updateFromServerCalls.count, 1)
        XCTAssertEqual(mockOfflineStore.updateFromServerCalls.first?.bookId, bookId.uuidString)
        XCTAssertEqual(mockOfflineStore.updateFromServerCalls.first?.position, 500.0)
    }

    @MainActor
    func testFetchProgress_WhenOnline_WithNewerLocalProgress_ReturnsLocal() async throws {
        // Given: Online, but local progress is newer
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()

        let oldServerDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let serverProgress = TestFixtures.makeGetProgressResponse(
            positionSeconds: 100.0,
            completed: false,
            lastPlayed: oldServerDate
        )
        mockAPIClient.fetchProgressResult = .success(serverProgress)

        // Local progress is newer
        let newerDate = Date()
        mockOfflineStore.addPendingProgress(
            bookId: bookId.uuidString,
            position: 300.0,
            completed: false,
            lastPlayed: newerDate
        )

        // When: Fetching progress
        let result = try await progressManager.fetchProgress(for: bookId.uuidString)

        // Then: Returns local progress (which is newer)
        XCTAssertEqual(result.positionSeconds, 300.0)
    }

    @MainActor
    func testFetchProgress_WithInvalidBookId_Throws() async {
        // Given: Invalid book ID
        mockNetworkMonitor.isConnected = true

        // When/Then: Throws error
        do {
            _ = try await progressManager.fetchProgress(for: "not-a-uuid")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid book ID"))
        }
    }

    // MARK: - Fetch Progress Tests (Offline)

    @MainActor
    func testFetchProgress_WhenOffline_ReturnsLocalProgress() async throws {
        // Given: Offline with local progress
        mockNetworkMonitor.isConnected = false
        let bookId = UUID()
        mockOfflineStore.addSyncedProgress(
            bookId: bookId.uuidString,
            position: 150.0,
            completed: false
        )

        // When: Fetching progress
        let result = try await progressManager.fetchProgress(for: bookId.uuidString)

        // Then: Returns local progress
        XCTAssertEqual(result.positionSeconds, 150.0)
        XCTAssertEqual(mockAPIClient.fetchProgressCalls.count, 0) // No API call
    }

    @MainActor
    func testFetchProgress_WhenOffline_WithNoLocalProgress_ReturnsZero() async throws {
        // Given: Offline with no local progress
        mockNetworkMonitor.isConnected = false
        let bookId = UUID()

        // When: Fetching progress
        let result = try await progressManager.fetchProgress(for: bookId.uuidString)

        // Then: Returns zero progress
        XCTAssertEqual(result.positionSeconds, 0)
        XCTAssertFalse(result.completed)
    }

    // MARK: - Save Progress Tests (Online)

    @MainActor
    func testSaveProgress_WhenOnline_SavesLocallyFirst() async throws {
        // Given: Online
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        mockAPIClient.updateProgressResult = .success(TestFixtures.makeUpdateProgressResponse(
            positionSeconds: 200.0,
            completed: false,
            lastPlayed: Date(),
            updated: true
        ))

        // When: Saving progress
        _ = try await progressManager.saveProgress(for: bookId.uuidString, positionSeconds: 200.0)

        // Then: Saved locally
        XCTAssertEqual(mockOfflineStore.saveProgressCalls.count, 1)
        XCTAssertEqual(mockOfflineStore.saveProgressCalls.first?.bookId, bookId.uuidString)
        XCTAssertEqual(mockOfflineStore.saveProgressCalls.first?.position, 200.0)
    }

    @MainActor
    func testSaveProgress_WhenOnline_SyncsToServer() async throws {
        // Given: Online
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        mockAPIClient.updateProgressResult = .success(TestFixtures.makeUpdateProgressResponse(
            positionSeconds: 200.0,
            completed: false,
            lastPlayed: Date(),
            updated: true
        ))

        // When: Saving progress
        let response = try await progressManager.saveProgress(for: bookId.uuidString, positionSeconds: 200.0)

        // Then: Synced to server
        XCTAssertEqual(mockAPIClient.updateProgressCalls.count, 1)
        XCTAssertEqual(mockAPIClient.updateProgressCalls.first?.positionSeconds, 200.0)
        XCTAssertTrue(response.updated)
    }

    @MainActor
    func testSaveProgress_WhenOnline_MarksAsSynced() async throws {
        // Given: Online
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        mockAPIClient.updateProgressResult = .success(TestFixtures.makeUpdateProgressResponse(
            positionSeconds: 200.0,
            completed: false,
            lastPlayed: Date(),
            updated: true
        ))

        // When: Saving progress
        _ = try await progressManager.saveProgress(for: bookId.uuidString, positionSeconds: 200.0)

        // Then: Marked as synced
        XCTAssertEqual(mockOfflineStore.markSyncedCalls.count, 1)
        XCTAssertEqual(mockOfflineStore.markSyncedCalls.first, bookId.uuidString)
    }

    @MainActor
    func testSaveProgress_WhenOnline_ServerFails_StillReturnsSuccess() async throws {
        // Given: Online but server fails
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        mockAPIClient.updateProgressResult = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

        // When: Saving progress
        let response = try await progressManager.saveProgress(for: bookId.uuidString, positionSeconds: 200.0)

        // Then: Returns success (local save succeeded)
        XCTAssertTrue(response.updated)
        XCTAssertEqual(response.positionSeconds, 200.0)
        // Not marked as synced since server failed
        XCTAssertEqual(mockOfflineStore.markSyncedCalls.count, 0)
    }

    // MARK: - Save Progress Tests (Offline)

    @MainActor
    func testSaveProgress_WhenOffline_SavesLocally() async throws {
        // Given: Offline
        mockNetworkMonitor.isConnected = false
        let bookId = UUID()

        // When: Saving progress
        let response = try await progressManager.saveProgress(for: bookId.uuidString, positionSeconds: 150.0)

        // Then: Saved locally
        XCTAssertEqual(mockOfflineStore.saveProgressCalls.count, 1)
        XCTAssertEqual(mockOfflineStore.saveProgressCalls.first?.position, 150.0)
        XCTAssertTrue(response.updated)
        // No API call when offline
        XCTAssertEqual(mockAPIClient.updateProgressCalls.count, 0)
    }

    @MainActor
    func testSaveProgress_WhenOffline_DoesNotSyncToServer() async throws {
        // Given: Offline
        mockNetworkMonitor.isConnected = false
        let bookId = UUID()

        // When: Saving progress
        _ = try await progressManager.saveProgress(for: bookId.uuidString, positionSeconds: 150.0)

        // Then: No server call
        XCTAssertEqual(mockAPIClient.updateProgressCalls.count, 0)
        XCTAssertEqual(mockOfflineStore.markSyncedCalls.count, 0)
    }

    // MARK: - Mark Completed Tests

    @MainActor
    func testMarkCompleted_CallsAPIWithCorrectStatus() async throws {
        // Given: Valid book ID
        let bookId = UUID()
        mockAPIClient.setProgressStatusResult = .success(TestFixtures.makeSetProgressStatusResponse(
            positionSeconds: 3600.0,
            completed: true,
            lastPlayed: Date()
        ))

        // When: Marking as completed
        try await progressManager.markCompleted(bookId: bookId.uuidString)

        // Then: API called with completed status
        XCTAssertEqual(mockAPIClient.setProgressStatusCalls.count, 1)
        XCTAssertEqual(mockAPIClient.setProgressStatusCalls.first?.status, .completed)
    }

    @MainActor
    func testMarkCompleted_WithInvalidBookId_Throws() async {
        // Given: Invalid book ID
        // When/Then: Throws error
        do {
            try await progressManager.markCompleted(bookId: "invalid")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid book ID"))
        }
    }

    // MARK: - Reset Progress Tests

    @MainActor
    func testResetProgress_CallsAPIWithCorrectStatus() async throws {
        // Given: Valid book ID
        let bookId = UUID()
        mockAPIClient.setProgressStatusResult = .success(TestFixtures.makeSetProgressStatusResponse(
            positionSeconds: 0.0,
            completed: false,
            lastPlayed: nil
        ))

        // When: Resetting progress
        try await progressManager.resetProgress(bookId: bookId.uuidString)

        // Then: API called with notStarted status
        XCTAssertEqual(mockAPIClient.setProgressStatusCalls.count, 1)
        XCTAssertEqual(mockAPIClient.setProgressStatusCalls.first?.status, .notStarted)
    }

    @MainActor
    func testResetProgress_WithInvalidBookId_Throws() async {
        // Given: Invalid book ID
        // When/Then: Throws error
        do {
            try await progressManager.resetProgress(bookId: "invalid")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid book ID"))
        }
    }

    // MARK: - Loading State Tests

    @MainActor
    func testFetchProgress_SetsLoadingState() async throws {
        // Given: Online with server response
        mockNetworkMonitor.isConnected = true
        let bookId = UUID()
        mockAPIClient.fetchProgressResult = .success(TestFixtures.makeGetProgressResponse(
            positionSeconds: 100.0,
            completed: false,
            lastPlayed: Date()
        ))

        // When: Fetching progress
        _ = try await progressManager.fetchProgress(for: bookId.uuidString)

        // Then: Loading state was set and cleared
        // Note: In async tests, we can't easily check intermediate states
        // but we can verify it's false after completion
        XCTAssertFalse(progressManager.isLoading)
    }
}
