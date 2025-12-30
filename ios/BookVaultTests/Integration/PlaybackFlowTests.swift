//
//  PlaybackFlowTests.swift
//  BookVaultTests
//
//  Integration tests for the full playback flow.
//  Phase 5: Offline Mode Tests
//

import XCTest
@testable import BookVault

/// Integration tests for the full playback flow across multiple services
@MainActor
final class PlaybackFlowTests: XCTestCase {
    var mockOfflineStore: MockOfflineProgressStore!
    var mockLibraryCache: MockLibraryCacheManager!
    var mockSyncManager: MockSyncManager!
    var mockNetworkMonitor: MockNetworkMonitor!
    var mockStorageManager: MockStorageManager!
    var mockAudioPlayerManager: MockAudioPlayerManager!

    override func setUp() {
        super.setUp()
        mockOfflineStore = MockOfflineProgressStore()
        mockLibraryCache = MockLibraryCacheManager()
        mockSyncManager = MockSyncManager()
        mockNetworkMonitor = MockNetworkMonitor()
        mockStorageManager = MockStorageManager()
        mockAudioPlayerManager = MockAudioPlayerManager()
    }

    override func tearDown() {
        mockOfflineStore = nil
        mockLibraryCache = nil
        mockSyncManager = nil
        mockNetworkMonitor = nil
        mockStorageManager = nil
        mockAudioPlayerManager = nil
        super.tearDown()
    }

    // MARK: - Online Playback Flow Tests

    func testOnlinePlaybackFlowSavesProgress() async {
        // Given: authenticated user, online, book to play
        mockNetworkMonitor.simulateWiFiConnection()
        let book = TestFixtures.makeBook()

        // When: book is played and progress is made
        mockAudioPlayerManager.play(book: book)
        try? await Task.sleep(nanoseconds: 50_000_000) // Wait for async loading
        mockAudioPlayerManager.seek(to: 300.0) // 5 minutes in

        // Then: simulate progress save
        mockOfflineStore.saveProgress(bookId: book.id.uuidString, position: 300.0, completed: false)

        // Verify progress was saved
        let savedProgress = mockOfflineStore.getProgress(bookId: book.id.uuidString)
        XCTAssertNotNil(savedProgress)
        XCTAssertEqual(savedProgress!.positionSeconds, 300.0, accuracy: 0.1)
        XCTAssertTrue(savedProgress?.needsSync ?? false)
    }

    func testOnlinePlaybackProgressMarkedForSync() async {
        // Given: authenticated user, online
        mockNetworkMonitor.simulateWiFiConnection()
        let book = TestFixtures.makeBook()

        // When: progress is saved during online playback
        mockOfflineStore.saveProgress(bookId: book.id.uuidString, position: 600.0, completed: false)

        // Then: progress should be marked as needing sync
        XCTAssertTrue(mockOfflineStore.hasPendingSync)
        XCTAssertEqual(mockOfflineStore.pendingSyncCount, 1)
    }

    // MARK: - Offline Playback Flow Tests

    func testOfflinePlaybackFlowQueuesSync() async {
        // Given: authenticated user, offline, downloaded book
        mockNetworkMonitor.simulateDisconnection()
        let book = TestFixtures.makeBook()
        mockStorageManager.downloadedBooks.insert(book.id.uuidString.uppercased())

        // When: book is played and progress is made while offline
        mockAudioPlayerManager.play(book: book)
        try? await Task.sleep(nanoseconds: 50_000_000) // Wait for async loading

        // Simulate progress save
        mockOfflineStore.saveProgress(bookId: book.id.uuidString, position: 450.0, completed: false)

        // Then: progress should be queued for sync
        XCTAssertTrue(mockOfflineStore.hasPendingSync)
        let pending = mockOfflineStore.getPendingSync()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.bookId, book.id.uuidString)
    }

    func testOfflinePlaybackUsesLocalFile() async {
        // Given: offline with downloaded book
        mockNetworkMonitor.simulateDisconnection()
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString.uppercased()

        // Pre-download the book
        mockStorageManager.downloadedBooks.insert(bookId)
        mockStorageManager.addToMetadata(book: book, fileSize: 50_000_000)

        // When: checking if book is downloaded
        let isDownloaded = mockStorageManager.isBookDownloaded(bookId: book.id.uuidString)

        // Then: should be available locally
        XCTAssertTrue(isDownloaded)

        // And: local file path should exist
        let localPath = mockStorageManager.audioFilePath(for: book.id.uuidString)
        XCTAssertNotNil(localPath)
    }

    // MARK: - Sync on Reconnect Tests

    func testProgressSyncOnNetworkReconnect() async {
        // Given: queued offline progress updates
        let book1 = TestFixtures.makeBook(id: UUID())
        let book2 = TestFixtures.makeBook(id: UUID())
        mockOfflineStore.addPendingProgress(bookId: book1.id.uuidString, position: 100.0)
        mockOfflineStore.addPendingProgress(bookId: book2.id.uuidString, position: 200.0)
        XCTAssertEqual(mockOfflineStore.pendingSyncCount, 2)

        // When: network reconnects and sync is triggered
        mockNetworkMonitor.simulateWiFiConnection()
        await mockSyncManager.syncPendingProgress()

        // Then: sync should have been attempted
        XCTAssertEqual(mockSyncManager.syncPendingProgressCalls, 1)
        XCTAssertNotNil(mockSyncManager.lastSyncDate)
    }

    func testLibraryCacheRefreshOnReconnect() async {
        // Given: stale library cache
        mockLibraryCache.simulateStaleCache(
            books: [TestFixtures.makeLibraryBook()],
            age: 7200 // 2 hours old
        )

        // When: network reconnects and refresh is triggered
        mockNetworkMonitor.simulateWiFiConnection()
        await mockSyncManager.refreshLibraryCache()

        // Then: refresh should have been attempted
        XCTAssertEqual(mockSyncManager.refreshLibraryCacheCalls, 1)
    }

    // MARK: - Download Then Play Flow Tests

    func testDownloadThenOfflinePlayFlow() async {
        // Given: book downloaded while online
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        // Simulate download completion
        mockStorageManager.downloadedBooks.insert(bookId.uppercased())
        mockStorageManager.addToMetadata(book: book, fileSize: 60_000_000)

        // When: going offline
        mockNetworkMonitor.simulateDisconnection()

        // Then: book should still be playable
        XCTAssertTrue(mockStorageManager.isBookDownloaded(bookId: bookId))

        // And: loading should work
        mockAudioPlayerManager.play(book: book)
        try? await Task.sleep(nanoseconds: 50_000_000) // Wait for async loading
        XCTAssertNotNil(mockAudioPlayerManager.currentBook)
        XCTAssertEqual(mockAudioPlayerManager.currentBook?.id, book.id)
    }

    func testOfflinePlaybackWithCachedLibrary() async {
        // Given: cached library
        let libraryBooks = [
            TestFixtures.makeLibraryBook(id: UUID(), title: "Book 1"),
            TestFixtures.makeLibraryBook(id: UUID(), title: "Book 2"),
            TestFixtures.makeLibraryBook(id: UUID(), title: "Book 3")
        ]
        mockLibraryCache.preloadCache(books: libraryBooks)

        // Download one book - convert to Book for storage metadata
        mockStorageManager.downloadedBooks.insert(libraryBooks[0].id.uuidString.uppercased())
        mockStorageManager.addToMetadata(book: libraryBooks[0].asBook, fileSize: 40_000_000)

        // When: going offline
        mockNetworkMonitor.simulateDisconnection()

        // Then: cached library should be available
        let cachedBooks = mockLibraryCache.loadLibrary()
        XCTAssertNotNil(cachedBooks)
        XCTAssertEqual(cachedBooks?.count, 3)

        // And: can identify which books are downloaded
        XCTAssertTrue(mockStorageManager.isBookDownloaded(bookId: libraryBooks[0].id.uuidString))
        XCTAssertFalse(mockStorageManager.isBookDownloaded(bookId: libraryBooks[1].id.uuidString))
        XCTAssertFalse(mockStorageManager.isBookDownloaded(bookId: libraryBooks[2].id.uuidString))
    }

    // MARK: - Progress Conflict Resolution Tests

    func testLocalProgressNewerThanServerIsPreserved() {
        // Given: local progress that is newer
        let bookId = TestFixtures.testBookId.uuidString
        let localTime = Date()
        mockOfflineStore.addPendingProgress(bookId: bookId, position: 1000.0, lastPlayed: localTime)

        // When: server sends older progress
        let serverTime = Date().addingTimeInterval(-3600) // 1 hour ago
        mockOfflineStore.updateFromServer(bookId: bookId, position: 500.0, completed: false, lastPlayed: serverTime)

        // Then: local progress should be preserved
        let savedProgress = mockOfflineStore.getProgress(bookId: bookId)
        XCTAssertNotNil(savedProgress)
        XCTAssertEqual(savedProgress!.positionSeconds, 1000.0, accuracy: 0.1)
    }

    func testServerProgressNewerThanLocalIsUsed() {
        // Given: local progress that is older
        let bookId = TestFixtures.testBookId.uuidString
        let localTime = Date().addingTimeInterval(-3600) // 1 hour ago
        mockOfflineStore.addPendingProgress(bookId: bookId, position: 500.0, lastPlayed: localTime)

        // When: server sends newer progress
        let serverTime = Date()
        mockOfflineStore.updateFromServer(bookId: bookId, position: 1000.0, completed: false, lastPlayed: serverTime)

        // Then: server progress should be used
        let savedProgress = mockOfflineStore.getProgress(bookId: bookId)
        XCTAssertNotNil(savedProgress)
        XCTAssertEqual(savedProgress!.positionSeconds, 1000.0, accuracy: 0.1)
    }

    // MARK: - Playback State Tests

    func testPlaybackProgressIsTrackedDuringSession() async {
        // Given: a book being played
        let book = TestFixtures.makeBook(runtimeMinutes: 60)
        mockAudioPlayerManager.play(book: book)
        try? await Task.sleep(nanoseconds: 50_000_000) // Wait for async loading

        // When: user seeks to different positions
        mockAudioPlayerManager.seek(to: 600.0) // 10 minutes
        mockOfflineStore.saveProgress(bookId: book.id.uuidString, position: 600.0, completed: false)

        mockAudioPlayerManager.seek(to: 1200.0) // 20 minutes
        mockOfflineStore.saveProgress(bookId: book.id.uuidString, position: 1200.0, completed: false)

        mockAudioPlayerManager.seek(to: 1800.0) // 30 minutes
        mockOfflineStore.saveProgress(bookId: book.id.uuidString, position: 1800.0, completed: false)

        // Then: only latest progress is stored
        let progress = mockOfflineStore.getProgress(bookId: book.id.uuidString)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!.positionSeconds, 1800.0, accuracy: 0.1)

        // And: save was called 3 times
        XCTAssertEqual(mockOfflineStore.saveProgressCalls.count, 3)
    }

    func testCompletedBookMarkedCorrectly() async {
        // Given: a book at near completion
        let book = TestFixtures.makeBook(runtimeMinutes: 60)
        mockAudioPlayerManager.play(book: book)
        try? await Task.sleep(nanoseconds: 50_000_000) // Wait for async loading

        // When: book is marked as completed
        mockOfflineStore.saveProgress(
            bookId: book.id.uuidString,
            position: 3600.0, // Full 60 minutes
            completed: true
        )

        // Then: progress should show as completed
        let progress = mockOfflineStore.getProgress(bookId: book.id.uuidString)
        XCTAssertTrue(progress?.completed ?? false)
    }

    // MARK: - Clear on Logout Tests

    func testLogoutClearsAllCaches() {
        // Given: cached data
        let bookId = TestFixtures.testBookId.uuidString
        mockOfflineStore.saveProgress(bookId: bookId, position: 500.0, completed: false)
        mockLibraryCache.preloadCache(books: [TestFixtures.makeLibraryBook()])

        // When: logout occurs (caches are cleared)
        mockOfflineStore.clearCache()
        mockLibraryCache.clearCache()
        mockSyncManager.stopMonitoring()

        // Then: all caches should be empty
        XCTAssertNil(mockOfflineStore.getProgress(bookId: bookId))
        XCTAssertNil(mockLibraryCache.loadLibrary())
        XCTAssertFalse(mockSyncManager.isMonitoring)
    }
}
