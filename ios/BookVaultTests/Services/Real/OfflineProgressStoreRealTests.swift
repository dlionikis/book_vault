//
//  OfflineProgressStoreRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 2: Real Services Testing - OfflineProgressStore
//

import XCTest
@testable import BookVault

final class OfflineProgressStoreRealTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!
    private var store: OfflineProgressStore!
    private var testUserId: String!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        // Create a unique temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineProgressStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create a test user ID
        testUserId = UUID().uuidString

        // Create store with test directory and user ID provider
        store = OfflineProgressStore(
            cacheDirectory: tempDirectory,
            userIdProvider: { [weak self] in self?.testUserId }
        )
    }

    @MainActor
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        tempDirectory = nil
        testUserId = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    @MainActor
    func testInitialization_CreatesCacheDirectory() {
        // Then: Cache directory should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    @MainActor
    func testInitialization_WithEmptyDirectory_HasNoProgress() {
        // Given: Fresh store
        // Then: No pending syncs
        XCTAssertFalse(store.hasPendingSync)
        XCTAssertEqual(store.pendingSyncCount, 0)
    }

    // MARK: - Save Progress Tests

    @MainActor
    func testSaveProgress_StoresProgressLocally() {
        // Given: A book ID and position
        let bookId = UUID().uuidString

        // When: Saving progress
        store.saveProgress(bookId: bookId, position: 120.5, completed: false)

        // Then: Progress can be retrieved
        let progress = store.getProgress(bookId: bookId)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.bookId, bookId)
        XCTAssertEqual(progress?.positionSeconds, 120.5)
        XCTAssertFalse(progress?.completed ?? true)
    }

    @MainActor
    func testSaveProgress_MarksAsNeedsSync() {
        // Given: A book ID
        let bookId = UUID().uuidString

        // When: Saving progress
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // Then: Progress is marked as needing sync
        let progress = store.getProgress(bookId: bookId)
        XCTAssertTrue(progress?.needsSync ?? false)
        XCTAssertTrue(store.hasPendingSync)
        XCTAssertEqual(store.pendingSyncCount, 1)
    }

    @MainActor
    func testSaveProgress_UpdatesExistingEntry() {
        // Given: Existing progress
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // When: Saving new progress for same book
        store.saveProgress(bookId: bookId, position: 180.0, completed: false)

        // Then: Progress is updated
        let progress = store.getProgress(bookId: bookId)
        XCTAssertEqual(progress?.positionSeconds, 180.0)

        // And: Still only one entry
        XCTAssertEqual(store.pendingSyncCount, 1)
    }

    @MainActor
    func testSaveProgress_WithCompletion_StoresCompletedStatus() {
        // Given: A book ID
        let bookId = UUID().uuidString

        // When: Saving as completed
        store.saveProgress(bookId: bookId, position: 3600.0, completed: true)

        // Then: Completed status is stored
        let progress = store.getProgress(bookId: bookId)
        XCTAssertTrue(progress?.completed ?? false)
    }

    @MainActor
    func testSaveProgress_WithNoUser_DoesNotSave() {
        // Given: No user logged in
        testUserId = nil

        // When: Attempting to save progress
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // Then: Nothing is saved
        XCTAssertNil(store.getProgress(bookId: bookId))
        XCTAssertFalse(store.hasPendingSync)
    }

    @MainActor
    func testSaveProgress_MultipleBooks_TracksAllSeparately() {
        // Given: Multiple books
        let bookId1 = UUID().uuidString
        let bookId2 = UUID().uuidString
        let bookId3 = UUID().uuidString

        // When: Saving progress for each
        store.saveProgress(bookId: bookId1, position: 100.0, completed: false)
        store.saveProgress(bookId: bookId2, position: 200.0, completed: false)
        store.saveProgress(bookId: bookId3, position: 300.0, completed: true)

        // Then: All progress is tracked
        XCTAssertEqual(store.getProgress(bookId: bookId1)?.positionSeconds, 100.0)
        XCTAssertEqual(store.getProgress(bookId: bookId2)?.positionSeconds, 200.0)
        XCTAssertEqual(store.getProgress(bookId: bookId3)?.positionSeconds, 300.0)
        XCTAssertEqual(store.pendingSyncCount, 3)
    }

    // MARK: - Get Progress Tests

    @MainActor
    func testGetProgress_WithNoUser_ReturnsNil() {
        // Given: Progress saved with user
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // When: User logs out
        testUserId = nil

        // Then: Progress is not accessible
        XCTAssertNil(store.getProgress(bookId: bookId))
    }

    @MainActor
    func testGetProgress_WithDifferentUser_ReturnsNil() {
        // Given: Progress saved with one user
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // When: Different user logs in
        testUserId = UUID().uuidString

        // Then: Progress is not accessible (cache mismatch)
        XCTAssertNil(store.getProgress(bookId: bookId))
    }

    @MainActor
    func testGetProgress_ForNonExistentBook_ReturnsNil() {
        // Given: Empty store
        // When: Getting progress for random book
        let progress = store.getProgress(bookId: UUID().uuidString)

        // Then: Returns nil
        XCTAssertNil(progress)
    }

    // MARK: - Pending Sync Tests

    @MainActor
    func testGetPendingSync_ReturnsOnlyUnsyncedEntries() {
        // Given: Mix of synced and unsynced entries
        let bookId1 = UUID().uuidString
        let bookId2 = UUID().uuidString

        store.saveProgress(bookId: bookId1, position: 100.0, completed: false)
        store.saveProgress(bookId: bookId2, position: 200.0, completed: false)
        store.markSynced(bookId: bookId1)

        // When: Getting pending sync
        let pending = store.getPendingSync()

        // Then: Only unsynced entry is returned
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.bookId, bookId2)
    }

    @MainActor
    func testGetPendingSync_WithNoUser_ReturnsEmpty() {
        // Given: Progress saved with user
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // When: User logs out
        testUserId = nil

        // Then: No pending sync
        XCTAssertTrue(store.getPendingSync().isEmpty)
    }

    // MARK: - Mark Synced Tests

    @MainActor
    func testMarkSynced_UpdatesNeedsSyncFlag() {
        // Given: Progress needing sync
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)
        XCTAssertTrue(store.getProgress(bookId: bookId)?.needsSync ?? false)

        // When: Marking as synced
        store.markSynced(bookId: bookId)

        // Then: No longer needs sync
        XCTAssertFalse(store.getProgress(bookId: bookId)?.needsSync ?? true)
        XCTAssertEqual(store.pendingSyncCount, 0)
    }

    @MainActor
    func testMarkSynced_ForNonExistentBook_DoesNothing() {
        // Given: Empty store
        // When: Marking non-existent book as synced
        store.markSynced(bookId: UUID().uuidString)

        // Then: No error occurs
        XCTAssertFalse(store.hasPendingSync)
    }

    // MARK: - Update From Server Tests

    @MainActor
    func testUpdateFromServer_WithNewerServerData_UpdatesLocal() {
        // Given: Local progress with old timestamp
        let bookId = UUID().uuidString
        let oldDate = Date().addingTimeInterval(-3600)  // 1 hour ago
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)

        // Simulate that local progress has old lastPlayed
        // (In reality, saveProgress sets lastPlayed to now, but we want to test the merge logic)

        // When: Updating from server with newer data
        let serverDate = Date()  // Now
        store.updateFromServer(bookId: bookId, position: 180.0, completed: true, lastPlayed: serverDate)

        // Then: Local is updated with server data
        let progress = store.getProgress(bookId: bookId)
        XCTAssertEqual(progress?.positionSeconds, 180.0)
        XCTAssertTrue(progress?.completed ?? false)
        XCTAssertFalse(progress?.needsSync ?? true)  // Already synced from server
    }

    @MainActor
    func testUpdateFromServer_WithNoLocalData_CreatesEntry() {
        // Given: No local progress
        let bookId = UUID().uuidString

        // When: Updating from server
        let serverDate = Date()
        store.updateFromServer(bookId: bookId, position: 300.0, completed: false, lastPlayed: serverDate)

        // Then: Entry is created
        let progress = store.getProgress(bookId: bookId)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.positionSeconds, 300.0)
        XCTAssertFalse(progress?.needsSync ?? true)
    }

    @MainActor
    func testUpdateFromServer_WithNoUser_DoesNothing() {
        // Given: No user
        testUserId = nil
        let bookId = UUID().uuidString

        // When: Updating from server
        store.updateFromServer(bookId: bookId, position: 100.0, completed: false, lastPlayed: Date())

        // Then: Nothing saved
        // Need to set user to check
        testUserId = UUID().uuidString
        XCTAssertNil(store.getProgress(bookId: bookId))
    }

    // MARK: - Clear Cache Tests

    @MainActor
    func testClearCache_RemovesAllProgress() {
        // Given: Multiple progress entries
        store.saveProgress(bookId: UUID().uuidString, position: 100.0, completed: false)
        store.saveProgress(bookId: UUID().uuidString, position: 200.0, completed: false)
        XCTAssertEqual(store.pendingSyncCount, 2)

        // When: Clearing cache
        store.clearCache()

        // Then: All progress is removed
        XCTAssertFalse(store.hasPendingSync)
        XCTAssertEqual(store.pendingSyncCount, 0)
    }

    @MainActor
    func testClearCache_RemovesCacheFile() {
        // Given: Progress saved to disk
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 100.0, completed: false)

        let cacheFile = tempDirectory.appendingPathComponent("progress.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        // When: Clearing cache
        store.clearCache()

        // Then: Cache file is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    // MARK: - Persistence Tests

    @MainActor
    func testProgress_PersistsAcrossInstances() {
        // Given: Progress saved
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 456.7, completed: false)

        // When: Creating new store with same directory and user
        let newStore = OfflineProgressStore(
            cacheDirectory: tempDirectory,
            userIdProvider: { [weak self] in self?.testUserId }
        )

        // Then: Progress is loaded
        let progress = newStore.getProgress(bookId: bookId)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.positionSeconds, 456.7)
    }

    @MainActor
    func testProgress_WithDifferentUserOnReload_NotAccessible() {
        // Given: Progress saved with one user
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 456.7, completed: false)

        // When: Creating new store with different user
        let differentUserId = UUID().uuidString
        let newStore = OfflineProgressStore(
            cacheDirectory: tempDirectory,
            userIdProvider: { differentUserId }
        )

        // Then: Progress is not accessible
        XCTAssertNil(newStore.getProgress(bookId: bookId))
    }

    // MARK: - Has Pending Sync Tests

    @MainActor
    func testHasPendingSync_WithNoEntries_ReturnsFalse() {
        XCTAssertFalse(store.hasPendingSync)
    }

    @MainActor
    func testHasPendingSync_WithUnsyncedEntries_ReturnsTrue() {
        store.saveProgress(bookId: UUID().uuidString, position: 60.0, completed: false)
        XCTAssertTrue(store.hasPendingSync)
    }

    @MainActor
    func testHasPendingSync_AfterAllSynced_ReturnsFalse() {
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)
        store.markSynced(bookId: bookId)
        XCTAssertFalse(store.hasPendingSync)
    }

    // MARK: - Last Played Date Tests

    @MainActor
    func testSaveProgress_UpdatesLastPlayedDate() {
        // Given: Progress saved at a specific time
        let bookId = UUID().uuidString
        let beforeSave = Date()
        store.saveProgress(bookId: bookId, position: 60.0, completed: false)
        let afterSave = Date()

        // Then: Last played is between before and after
        let progress = store.getProgress(bookId: bookId)
        XCTAssertNotNil(progress?.lastPlayed)
        XCTAssertGreaterThanOrEqual(progress!.lastPlayed, beforeSave)
        XCTAssertLessThanOrEqual(progress!.lastPlayed, afterSave)
    }

    @MainActor
    func testUpdateFromServer_PreservesServerLastPlayed() {
        // Given: A specific server date
        let bookId = UUID().uuidString
        let serverDate = Date(timeIntervalSince1970: 1700000000)  // Fixed date

        // When: Updating from server
        store.updateFromServer(bookId: bookId, position: 100.0, completed: false, lastPlayed: serverDate)

        // Then: Server date is preserved
        let progress = store.getProgress(bookId: bookId)
        XCTAssertEqual(progress?.lastPlayed, serverDate)
    }

    // MARK: - Edge Cases

    @MainActor
    func testSaveProgress_WithZeroPosition_Works() {
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: 0.0, completed: false)

        let progress = store.getProgress(bookId: bookId)
        XCTAssertEqual(progress?.positionSeconds, 0.0)
    }

    @MainActor
    func testSaveProgress_WithVeryLargePosition_Works() {
        let bookId = UUID().uuidString
        let largePosition = 86400.0  // 24 hours in seconds
        store.saveProgress(bookId: bookId, position: largePosition, completed: false)

        let progress = store.getProgress(bookId: bookId)
        XCTAssertEqual(progress?.positionSeconds, largePosition)
    }

    @MainActor
    func testSaveProgress_WithNegativePosition_Works() {
        // Edge case: negative positions shouldn't happen but should be handled
        let bookId = UUID().uuidString
        store.saveProgress(bookId: bookId, position: -10.0, completed: false)

        let progress = store.getProgress(bookId: bookId)
        XCTAssertEqual(progress?.positionSeconds, -10.0)
    }
}
