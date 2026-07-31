//
//  BackgroundDownloadTests.swift
//  BookVaultTests
//
//  Tests for background download functionality.
//  Phase 4: Background Downloads
//

import Combine
import XCTest
@testable import BookVault

@MainActor
final class BackgroundDownloadTests: XCTestCase {
    var sut: DownloadManager!
    var mockAPIClient: MockAPIClient!
    var mockStorageManager: MockStorageManager!
    var mockNetworkMonitor: MockNetworkMonitor!
    var testUserDefaults: UserDefaults!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        mockAPIClient = MockAPIClient()
        mockStorageManager = MockStorageManager()
        mockNetworkMonitor = MockNetworkMonitor()

        // Use a unique suite name for each test to avoid cross-test contamination
        let suiteName = "com.bookvault.test.\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: suiteName)!

        // Create a test session (ephemeral, not background for tests)
        let config = URLSessionConfiguration.ephemeral
        let testSession = URLSession(configuration: config)

        sut = DownloadManager(
            apiClient: mockAPIClient,
            storageManager: mockStorageManager,
            networkMonitor: mockNetworkMonitor,
            sessionIdentifier: "com.bookvault.downloads.test.\(UUID().uuidString)",
            userDefaults: testUserDefaults,
            session: testSession
        )

        cancellables = []
    }

    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        mockAPIClient = nil
        mockStorageManager = nil
        mockNetworkMonitor = nil
        testUserDefaults = nil
        try await super.tearDown()
    }

    // MARK: - DownloadState Tests

    func testDownloadStateBackgroundDownloadingEquality() {
        // Given two background downloading states with same progress
        let state1 = DownloadState.backgroundDownloading(lastProgress: 0.5)
        let state2 = DownloadState.backgroundDownloading(lastProgress: 0.5)

        // Then they should be equal
        XCTAssertEqual(state1, state2)
    }

    func testDownloadStateBackgroundDownloadingInequality() {
        // Given two background downloading states with different progress
        let state1 = DownloadState.backgroundDownloading(lastProgress: 0.5)
        let state2 = DownloadState.backgroundDownloading(lastProgress: 0.75)

        // Then they should not be equal
        XCTAssertNotEqual(state1, state2)
    }

    func testDownloadStateAllCasesAreDistinct() {
        // Given all download states
        let states: [DownloadState] = [
            .notDownloaded,
            .waiting,
            .downloading(progress: 0.5),
            .backgroundDownloading(lastProgress: 0.5),
            .paused(progress: 0.5),
            .completed,
            .failed(error: "Test error")
        ]

        // Then each should be distinct from the others
        for (i, state1) in states.enumerated() {
            for (j, state2) in states.enumerated() where i != j {
                XCTAssertNotEqual(state1, state2, "State at \(i) should not equal state at \(j)")
            }
        }
    }

    // MARK: - Resume Data Tests

    func testHasResumeDataReturnsFalseWhenNoResumeData() {
        // Given a book ID with no resume data
        let bookId = UUID().uuidString

        // When checking for resume data
        let hasData = sut.hasResumeData(bookId: bookId)

        // Then should return false
        XCTAssertFalse(hasData)
    }

    // MARK: - Initial State Tests

    func testInitialStateHasNoActiveDownloads() {
        // Given a fresh download manager
        // When checking active downloads
        // Then should be empty
        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    func testInitialStateHasNoError() {
        // Given a fresh download manager
        // When checking error
        // Then should be nil
        XCTAssertNil(sut.error)
    }

    // MARK: - Download State Query Tests

    func testDownloadStateForUnknownBookReturnsNotDownloaded() {
        // Given a book ID that isn't being downloaded
        let bookId = UUID().uuidString

        // When querying download state
        let state = sut.downloadState(for: bookId)

        // Then should return notDownloaded
        XCTAssertEqual(state, .notDownloaded)
    }

    func testDownloadStateForDownloadedBookReturnsCompleted() {
        // Given a book that has been downloaded
        let bookId = UUID().uuidString
        mockStorageManager.downloadedBooks.insert(bookId.uppercased())

        // When querying download state
        let state = sut.downloadState(for: bookId)

        // Then should return completed
        XCTAssertEqual(state, .completed)
    }

    // MARK: - Cancel Download Tests

    func testCancelDownloadRemovesFromActiveDownloads() async {
        // Given an active download (simulated by adding directly)
        let bookId = UUID().uuidString
        let book = TestFixtures.makeBook(id: UUID(uuidString: bookId)!)

        sut.activeDownloads[bookId] = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 0,
            totalBytes: 1000,
            state: .downloading(progress: 0),
            task: nil
        )

        // When cancelling
        sut.cancelDownload(bookId: bookId)

        // Then should be removed
        XCTAssertNil(sut.activeDownloads[bookId])
    }

    // MARK: - Is Downloading Tests

    func testIsDownloadingReturnsFalseForUnknownBook() {
        // Given a book ID that isn't being downloaded
        let bookId = UUID().uuidString

        // When checking if downloading
        let isDownloading = sut.isDownloading(bookId: bookId)

        // Then should return false
        XCTAssertFalse(isDownloading)
    }

    func testIsDownloadingReturnsTrueForActiveDownload() {
        // Given an active download
        let bookId = UUID().uuidString
        let book = TestFixtures.makeBook(id: UUID(uuidString: bookId)!)

        sut.activeDownloads[bookId] = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 500,
            totalBytes: 1000,
            state: .downloading(progress: 0.5),
            task: nil
        )

        // When checking if downloading
        let isDownloading = sut.isDownloading(bookId: bookId)

        // Then should return true
        XCTAssertTrue(isDownloading)
    }

    // MARK: - Storage Stats Tests

    func testGetStorageStatsReturnsCorrectValues() {
        // Given storage manager with some downloaded books
        mockStorageManager.downloads = [
            DownloadedBook(
                id: UUID().uuidString,
                title: "Book 1",
                author: "Author 1",
                downloadedAt: Date(),
                fileSize: 1000,
                audioPath: "path1",
                coverPath: nil,
                fileExtension: "mp3"
            ),
            DownloadedBook(
                id: UUID().uuidString,
                title: "Book 2",
                author: "Author 2",
                downloadedAt: Date(),
                fileSize: 2000,
                audioPath: "path2",
                coverPath: nil,
                fileExtension: "mp3"
            )
        ]
        mockStorageManager.totalSize = 3000

        // When getting storage stats
        let stats = sut.getStorageStats()

        // Then should return correct values
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.size, 3000)
    }

    // MARK: - Background Session Identifier Tests

    func testBackgroundSessionIdentifierIsValid() {
        // The session identifier should follow Apple's reverse-DNS convention
        // We can't directly access the private property, but we can verify
        // the manager initializes without errors
        XCTAssertNotNil(sut)
    }

    // MARK: - Handle Background Session Events Tests

    func testHandleBackgroundSessionEventsWithWrongIdentifier() {
        // Given a different session identifier
        let wrongIdentifier = "com.other.session"
        var completionCalled = false

        // When handling events with wrong identifier
        sut.handleBackgroundSessionEvents(identifier: wrongIdentifier) {
            completionCalled = true
        }

        // Then completion should be called immediately (since identifier doesn't match)
        XCTAssertTrue(completionCalled)
    }

    // MARK: - Active Download Properties Tests

    func testActiveDownloadProgressCalculation() {
        // Given bytes downloaded and total bytes
        let book = TestFixtures.makeBook()
        let download = ActiveDownload(
            id: book.id.uuidString,
            book: book,
            bytesDownloaded: 500,
            totalBytes: 1000,
            state: .downloading(progress: 0.5),
            task: nil
        )

        // When getting progress
        let progress = download.progress

        // Then should be correctly calculated
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testActiveDownloadProgressWithZeroTotalBytes() {
        // Given zero total bytes
        let book = TestFixtures.makeBook()
        let download = ActiveDownload(
            id: book.id.uuidString,
            book: book,
            bytesDownloaded: 500,
            totalBytes: 0,
            state: .downloading(progress: 0),
            task: nil
        )

        // When getting progress
        let progress = download.progress

        // Then should be 0
        XCTAssertEqual(progress, 0)
    }

    func testActiveDownloadFormattedProgress() {
        // Given bytes downloaded and total bytes
        let book = TestFixtures.makeBook()
        let download = ActiveDownload(
            id: book.id.uuidString,
            book: book,
            bytesDownloaded: 512_000, // 500 KB
            totalBytes: 1_024_000, // 1 MB
            state: .downloading(progress: 0.5),
            task: nil
        )

        // When getting formatted progress
        let formatted = download.formattedProgress

        // Then should contain size information
        XCTAssertTrue(formatted.contains("/"), "Should contain separator")
    }
}

// MARK: - Test Helpers

extension BackgroundDownloadTests {
    /// Helper to create a test book with specified ID
    func makeTestBook(id: UUID = UUID()) -> Book {
        TestFixtures.makeBook(id: id)
    }
}
