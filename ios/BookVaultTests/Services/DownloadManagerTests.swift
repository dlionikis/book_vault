//
//  DownloadManagerTests.swift
//  BookVaultTests
//
//  Tests for DownloadManager functionality.
//  Phase 4: Download Tests
//

import XCTest
import Combine
@testable import BookVault

@MainActor
final class DownloadManagerTests: XCTestCase {

    var sut: MockDownloadManager!
    var mockStorageManager: MockStorageManager!
    var mockNetworkMonitor: MockNetworkMonitor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = MockDownloadManager()
        mockStorageManager = MockStorageManager()
        mockNetworkMonitor = MockNetworkMonitor()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockStorageManager = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateHasNoActiveDownloads() {
        // Given a fresh download manager
        // When checking active downloads
        // Then should be empty
        XCTAssertTrue(sut.activeDownloads.isEmpty)
        XCTAssertNil(sut.error)
    }

    // MARK: - Start Download Tests

    func testStartDownloadAddsToActiveDownloads() async throws {
        // Given a book to download
        let book = TestFixtures.makeBook()

        // When starting download
        try await sut.startDownload(book: book)

        // Then should be in active downloads
        let bookId = book.id.uuidString
        XCTAssertNotNil(sut.activeDownloads[bookId])
        XCTAssertEqual(sut.startDownloadCalls.count, 1)
        XCTAssertEqual(sut.startDownloadCalls.first?.id, book.id)
    }

    func testStartDownloadSetsStateToDownloading() async throws {
        // Given a book to download
        let book = TestFixtures.makeBook()

        // When starting download
        try await sut.startDownload(book: book)

        // Then state should be downloading
        let bookId = book.id.uuidString
        if case .downloading(let progress) = sut.activeDownloads[bookId]?.state {
            XCTAssertEqual(progress, 0)
        } else {
            XCTFail("Expected downloading state with 0 progress")
        }
    }

    func testStartDownloadThrowsOnNetworkError() async {
        // Given network error configured
        sut.startShouldFail = true
        sut.startErrorToThrow = .networkError("Connection failed")

        // When starting download
        let book = TestFixtures.makeBook()

        // Then should throw error
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected error to be thrown")
        } catch let error as DownloadError {
            if case .networkError(let message) = error {
                XCTAssertEqual(message, "Connection failed")
            } else {
                XCTFail("Expected networkError")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testStartDownloadThrowsOnInsufficientStorage() async {
        // Given storage error configured
        sut.startShouldFail = true
        sut.startErrorToThrow = .insufficientStorage

        // When starting download
        let book = TestFixtures.makeBook()

        // Then should throw insufficient storage error
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected error to be thrown")
        } catch let error as DownloadError {
            if case .insufficientStorage = error {
                // Success
            } else {
                XCTFail("Expected insufficientStorage error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testStartDownloadThrowsOnWiFiRequired() async {
        // Given WiFi required error configured
        sut.startShouldFail = true
        sut.startErrorToThrow = .wifiRequired

        // When starting download
        let book = TestFixtures.makeBook()

        // Then should throw WiFi required error
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected error to be thrown")
        } catch let error as DownloadError {
            if case .wifiRequired = error {
                // Success
            } else {
                XCTFail("Expected wifiRequired error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Download State Tests

    func testDownloadStateReturnsNotDownloadedForUnknownBook() {
        // Given a book ID that hasn't been downloaded
        let unknownId = UUID().uuidString

        // When checking download state
        let state = sut.downloadState(for: unknownId)

        // Then should return notDownloaded
        XCTAssertEqual(state, .notDownloaded)
    }

    func testDownloadStateReturnsDownloadingForActiveDownload() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)

        // When checking download state
        let state = sut.downloadState(for: book.id.uuidString)

        // Then should return downloading
        if case .downloading = state {
            // Success
        } else {
            XCTFail("Expected downloading state, got \(state)")
        }
    }

    func testDownloadStateReturnsCompletedForFinishedDownload() {
        // Given a completed download
        let bookId = "test-book-id"
        sut.markAsCompleted(bookId: bookId)

        // When checking download state
        let state = sut.downloadState(for: bookId)

        // Then should return completed
        XCTAssertEqual(state, .completed)
    }

    func testDownloadStateTracksCalls() {
        // Given a book ID
        let bookId = "tracked-book"

        // When checking download state
        _ = sut.downloadState(for: bookId)

        // Then call should be tracked
        XCTAssertEqual(sut.downloadStateCalls.count, 1)
        XCTAssertEqual(sut.downloadStateCalls.first, bookId)
    }

    // MARK: - Is Downloading Tests

    func testIsDownloadingReturnsTrueForActiveDownload() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)

        // When checking if downloading
        let isDownloading = sut.isDownloading(bookId: book.id.uuidString)

        // Then should return true
        XCTAssertTrue(isDownloading)
    }

    func testIsDownloadingReturnsFalseForCompletedDownload() {
        // Given a completed download
        let bookId = "completed-book"
        sut.markAsCompleted(bookId: bookId)

        // When checking if downloading
        let isDownloading = sut.isDownloading(bookId: bookId)

        // Then should return false
        XCTAssertFalse(isDownloading)
    }

    func testIsDownloadingReturnsFalseForUnknownBook() {
        // Given an unknown book ID
        let unknownId = "unknown-book"

        // When checking if downloading
        let isDownloading = sut.isDownloading(bookId: unknownId)

        // Then should return false
        XCTAssertFalse(isDownloading)
    }

    // MARK: - Progress Tests

    func testSimulateProgressUpdatesDownloadState() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When simulating progress
        sut.simulateProgress(bookId: bookId, progress: 0.5)

        // Then progress should be updated
        if let download = sut.activeDownloads[bookId] {
            XCTAssertEqual(download.progress, 0.5, accuracy: 0.01)
            if case .downloading(let progress) = download.state {
                XCTAssertEqual(progress, 0.5)
            } else {
                XCTFail("Expected downloading state")
            }
        } else {
            XCTFail("Download not found")
        }
    }

    func testProgressUpdateReflectsInState() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When updating progress to 75%
        sut.simulateProgress(bookId: bookId, progress: 0.75)

        // Then state should reflect 75% progress
        let state = sut.downloadState(for: bookId)
        if case .downloading(let progress) = state {
            XCTAssertEqual(progress, 0.75)
        } else {
            XCTFail("Expected downloading state")
        }
    }

    // MARK: - Pause/Resume Tests

    func testPauseDownloadChangesStateToPaused() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString
        sut.simulateProgress(bookId: bookId, progress: 0.3)

        // When pausing download
        sut.pauseDownload(bookId: bookId)

        // Then state should be paused with same progress
        if case .paused(let progress) = sut.activeDownloads[bookId]?.state {
            XCTAssertEqual(progress, 0.3, accuracy: 0.01)
        } else {
            XCTFail("Expected paused state")
        }
        XCTAssertEqual(sut.pauseDownloadCalls.count, 1)
    }

    func testResumeDownloadChangesStateToDownloading() async throws {
        // Given a paused download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString
        sut.simulateProgress(bookId: bookId, progress: 0.5)
        sut.pauseDownload(bookId: bookId)

        // When resuming download
        try await sut.resumeDownload(book: book)

        // Then state should be downloading
        if case .downloading = sut.activeDownloads[bookId]?.state {
            // Success
        } else {
            XCTFail("Expected downloading state")
        }
        XCTAssertEqual(sut.resumeDownloadCalls.count, 1)
    }

    func testResumeDownloadThrowsOnError() async throws {
        // Given a paused download and resume error configured
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        sut.pauseDownload(bookId: book.id.uuidString)
        sut.resumeShouldFail = true
        sut.resumeErrorToThrow = .networkError("Resume failed")

        // When resuming download
        // Then should throw error
        do {
            try await sut.resumeDownload(book: book)
            XCTFail("Expected error to be thrown")
        } catch let error as DownloadError {
            if case .networkError(let message) = error {
                XCTAssertEqual(message, "Resume failed")
            } else {
                XCTFail("Expected networkError")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cancel Tests

    func testCancelDownloadRemovesFromActiveDownloads() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When cancelling download
        sut.cancelDownload(bookId: bookId)

        // Then should be removed from active downloads
        XCTAssertNil(sut.activeDownloads[bookId])
        XCTAssertEqual(sut.cancelDownloadCalls.count, 1)
        XCTAssertEqual(sut.cancelDownloadCalls.first, bookId)
    }

    func testCancelDownloadChangesStateToNotDownloaded() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When cancelling download
        sut.cancelDownload(bookId: bookId)

        // Then state should be notDownloaded
        XCTAssertEqual(sut.downloadState(for: bookId), .notDownloaded)
    }

    // MARK: - Delete Tests

    func testDeleteDownloadRemovesCompletedDownload() throws {
        // Given a completed download
        let bookId = "completed-book"
        sut.markAsCompleted(bookId: bookId)

        // When deleting download
        try sut.deleteDownload(bookId: bookId)

        // Then should be removed
        XCTAssertEqual(sut.downloadState(for: bookId), .notDownloaded)
        XCTAssertEqual(sut.deleteDownloadCalls.count, 1)
    }

    func testDeleteDownloadThrowsOnError() {
        // Given delete error configured
        sut.deleteShouldFail = true
        let bookId = "to-delete"
        sut.markAsCompleted(bookId: bookId)

        // When deleting download
        // Then should throw error
        XCTAssertThrowsError(try sut.deleteDownload(bookId: bookId))
    }

    // MARK: - Completion Tests

    func testSimulateCompletionSetsStateToCompleted() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When simulating completion
        sut.simulateCompletion(bookId: bookId)

        // Then state should be completed
        XCTAssertTrue(sut.completedDownloads.contains(bookId))
    }

    func testCompletedDownloadReturnsCompletedState() async throws {
        // Given an active download that completes
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString
        sut.simulateCompletion(bookId: bookId)

        // Wait for async removal from active downloads
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // When checking state
        let state = sut.downloadState(for: bookId)

        // Then should return completed
        XCTAssertEqual(state, .completed)
    }

    // MARK: - Failure Tests

    func testSimulateFailureSetsFailedState() async throws {
        // Given an active download
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When simulating failure
        sut.simulateFailure(bookId: bookId, errorMessage: "Network timeout")

        // Then state should be failed
        if case .failed(let error) = sut.activeDownloads[bookId]?.state {
            XCTAssertEqual(error, "Network timeout")
        } else {
            XCTFail("Expected failed state")
        }
    }

    // MARK: - ActiveDownload Tests

    func testActiveDownloadProgressCalculation() async throws {
        // Given an active download
        let book = TestFixtures.makeBook(runtimeMinutes: 60) // 60MB total (1MB per minute)
        try await sut.startDownload(book: book)
        let bookId = book.id.uuidString

        // When simulating 50% progress
        sut.simulateProgress(bookId: bookId, progress: 0.5)

        // Then progress should be 50%
        if let download = sut.activeDownloads[bookId] {
            XCTAssertEqual(download.progress, 0.5, accuracy: 0.01)
            XCTAssertEqual(download.bytesDownloaded, download.totalBytes / 2)
        } else {
            XCTFail("Download not found")
        }
    }

    // MARK: - Error Type Tests

    func testDownloadErrorDescriptions() {
        // Test each error type has a description
        let errors: [DownloadError] = [
            .networkError("Test"),
            .insufficientStorage,
            .rateLimitExceeded,
            .urlExpired,
            .fileCorruption,
            .unauthorized,
            .notEligible,
            .wifiRequired,
            .cancelled
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) description should not be empty")
        }
    }

    // MARK: - DownloadState Equality Tests

    func testDownloadStateEquality() {
        // Test equality for each state type
        XCTAssertEqual(DownloadState.notDownloaded, DownloadState.notDownloaded)
        XCTAssertEqual(DownloadState.waiting, DownloadState.waiting)
        XCTAssertEqual(DownloadState.completed, DownloadState.completed)
        XCTAssertEqual(DownloadState.downloading(progress: 0.5), DownloadState.downloading(progress: 0.5))
        XCTAssertEqual(DownloadState.paused(progress: 0.3), DownloadState.paused(progress: 0.3))

        // Test inequality
        XCTAssertNotEqual(DownloadState.notDownloaded, DownloadState.completed)
        XCTAssertNotEqual(DownloadState.downloading(progress: 0.5), DownloadState.downloading(progress: 0.6))
        XCTAssertNotEqual(DownloadState.paused(progress: 0.5), DownloadState.downloading(progress: 0.5))
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() async throws {
        // Given downloads and state
        let book = TestFixtures.makeBook()
        try await sut.startDownload(book: book)
        sut.markAsCompleted(bookId: "completed-book")
        sut.error = .networkError("Test error")

        // When resetting
        sut.reset()

        // Then all state should be cleared
        XCTAssertTrue(sut.activeDownloads.isEmpty)
        XCTAssertTrue(sut.completedDownloads.isEmpty)
        XCTAssertNil(sut.error)
        XCTAssertTrue(sut.startDownloadCalls.isEmpty)
        XCTAssertTrue(sut.cancelDownloadCalls.isEmpty)
        XCTAssertTrue(sut.pauseDownloadCalls.isEmpty)
        XCTAssertTrue(sut.resumeDownloadCalls.isEmpty)
        XCTAssertTrue(sut.deleteDownloadCalls.isEmpty)
        XCTAssertFalse(sut.startShouldFail)
        XCTAssertFalse(sut.resumeShouldFail)
        XCTAssertFalse(sut.deleteShouldFail)
    }
}
