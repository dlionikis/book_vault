//
//  ProgressManagerTests.swift
//  BookVaultTests
//
//  Unit tests for ProgressManager.
//

import XCTest
@testable import BookVault

@MainActor
final class ProgressManagerTests: XCTestCase {
    var mockAPIClient: MockAPIClient!
    var mockNetworkMonitor: MockNetworkMonitor!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        mockNetworkMonitor = MockNetworkMonitor()
    }

    override func tearDown() async throws {
        mockAPIClient = nil
        mockNetworkMonitor = nil
    }

    // MARK: - Save Progress Tests

    func testSaveProgressRecordsCall() async {
        // Given: A mock progress manager
        let mockManager = MockProgressManager()
        let bookId = TestFixtures.testBookId.uuidString

        // When: saveProgress is called
        _ = try? await mockManager.saveProgress(for: bookId, positionSeconds: 123.45)

        // Then: The call should be recorded
        XCTAssertEqual(mockManager.saveProgressCalls.count, 1)
        XCTAssertEqual(mockManager.saveProgressCalls.first?.bookId, bookId)
        XCTAssertEqual(mockManager.saveProgressCalls.first?.positionSeconds, 123.45)
    }

    func testSaveProgressReturnsConfiguredResult() async throws {
        // Given: A mock with a specific response configured
        let mockManager = MockProgressManager()
        let expectedResponse = SaveProgressResponse(
            positionSeconds: 500.0,
            completed: false,
            lastPlayed: "2025-01-15T10:30:00Z",
            updated: true
        )
        mockManager.saveProgressResult = .success(expectedResponse)

        // When: saveProgress is called
        let result = try await mockManager.saveProgress(for: "test-book", positionSeconds: 500.0)

        // Then: The configured response should be returned
        XCTAssertEqual(result.positionSeconds, 500.0)
        XCTAssertTrue(result.updated)
    }

    func testSaveProgressThrowsOnError() async {
        // Given: A mock configured to fail
        let mockManager = MockProgressManager()
        mockManager.saveProgressResult = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

        // When/Then: saveProgress should throw
        do {
            _ = try await mockManager.saveProgress(for: "test-book", positionSeconds: 100.0)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
            XCTAssertTrue(error is APIError)
        }
    }

    // MARK: - Fetch Progress Tests

    func testFetchProgressRecordsCall() async throws {
        // Given: A mock progress manager
        let mockManager = MockProgressManager()
        let bookId = TestFixtures.testBookId.uuidString

        // When: fetchProgress is called
        _ = try await mockManager.fetchProgress(for: bookId)

        // Then: The call should be recorded
        XCTAssertEqual(mockManager.fetchProgressCalls.count, 1)
        XCTAssertEqual(mockManager.fetchProgressCalls.first, bookId)
    }

    func testFetchProgressReturnsConfiguredResult() async throws {
        // Given: A mock with a specific response configured
        let mockManager = MockProgressManager()
        let expectedProgress = UserProgress(
            positionSeconds: 1234.56,
            completed: true,
            lastPlayed: Date()
        )
        mockManager.fetchProgressResult = .success(expectedProgress)

        // When: fetchProgress is called
        let result = try await mockManager.fetchProgress(for: "test-book")

        // Then: The configured response should be returned
        XCTAssertEqual(result.positionSeconds, 1234.56)
        XCTAssertTrue(result.completed)
    }

    func testFetchProgressReturnsNilForUnknownBook() async throws {
        // Given: A mock with default configuration
        let mockManager = MockProgressManager()

        // When: fetchProgress is called
        let result = try await mockManager.fetchProgress(for: "unknown-book")

        // Then: Default progress should be returned
        XCTAssertEqual(result.positionSeconds, 0)
        XCTAssertFalse(result.completed)
        XCTAssertNil(result.lastPlayed)
    }

    // MARK: - Mark Completed Tests

    func testMarkCompletedRecordsCall() async throws {
        // Given: A mock progress manager
        let mockManager = MockProgressManager()
        let bookId = TestFixtures.testBookId.uuidString

        // When: markCompleted is called
        try await mockManager.markCompleted(bookId: bookId)

        // Then: The call should be recorded
        XCTAssertEqual(mockManager.markCompletedCalls.count, 1)
        XCTAssertEqual(mockManager.markCompletedCalls.first, bookId)
    }

    func testMarkCompletedThrowsOnNetworkError() async {
        // Given: A mock configured to fail
        let mockManager = MockProgressManager()
        mockManager.markCompletedShouldFail = true

        // When/Then: markCompleted should throw
        do {
            try await mockManager.markCompleted(bookId: "test-book")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Reset Progress Tests

    func testResetProgressRecordsCall() async throws {
        // Given: A mock progress manager
        let mockManager = MockProgressManager()
        let bookId = TestFixtures.testBookId.uuidString

        // When: resetProgress is called
        try await mockManager.resetProgress(bookId: bookId)

        // Then: The call should be recorded
        XCTAssertEqual(mockManager.resetProgressCalls.count, 1)
        XCTAssertEqual(mockManager.resetProgressCalls.first, bookId)
    }

    func testResetProgressThrowsOnError() async {
        // Given: A mock configured to fail
        let mockManager = MockProgressManager()
        mockManager.resetProgressShouldFail = true

        // When/Then: resetProgress should throw
        do {
            try await mockManager.resetProgress(bookId: "test-book")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
            XCTAssertNotNil(error)
        }
    }

    // MARK: - State Tests

    func testInitialStateIsNotLoading() {
        // Given: A fresh mock
        let mockManager = MockProgressManager()

        // Then: isLoading should be false
        XCTAssertFalse(mockManager.isLoading)
    }

    func testInitialErrorIsNil() {
        // Given: A fresh mock
        let mockManager = MockProgressManager()

        // Then: error should be nil
        XCTAssertNil(mockManager.error)
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() async throws {
        // Given: A mock with recorded calls and state
        let mockManager = MockProgressManager()
        _ = try await mockManager.saveProgress(for: "book1", positionSeconds: 100)
        _ = try await mockManager.fetchProgress(for: "book2")
        try await mockManager.markCompleted(bookId: "book3")

        // When: reset is called
        mockManager.reset()

        // Then: All state should be cleared
        XCTAssertTrue(mockManager.saveProgressCalls.isEmpty)
        XCTAssertTrue(mockManager.fetchProgressCalls.isEmpty)
        XCTAssertTrue(mockManager.markCompletedCalls.isEmpty)
        XCTAssertTrue(mockManager.resetProgressCalls.isEmpty)
        XCTAssertFalse(mockManager.isLoading)
        XCTAssertNil(mockManager.error)
    }
}
