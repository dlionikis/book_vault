//
//  OfflineProgressStoreTests.swift
//  BookVaultTests
//
//  Tests for OfflineProgressStore functionality.
//  Phase 5: Offline Mode Tests
//

import XCTest
@testable import BookVault

@MainActor
final class OfflineProgressStoreTests: XCTestCase {
    var sut: MockOfflineProgressStore!

    override func setUp() async throws {
        try await super.setUp()
        sut = MockOfflineProgressStore()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Save Progress Tests

    func testSaveProgressStoresLocally() {
        // Given a book ID and position
        let bookId = TestFixtures.testBookId.uuidString
        let position = 123.45

        // When saveProgress is called
        sut.saveProgress(bookId: bookId, position: position, completed: false)

        // Then progress should be retrievable
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.positionSeconds, position, accuracy: 0.01)
        XCTAssertEqual(saved?.bookId, bookId)
        XCTAssertFalse(saved?.completed ?? true)
    }

    func testSaveProgressMarksAsNeedingSync() {
        // Given a book ID
        let bookId = TestFixtures.testBookId.uuidString

        // When saveProgress is called
        sut.saveProgress(bookId: bookId, position: 100.0, completed: false)

        // Then progress should be marked as needing sync
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertTrue(saved?.needsSync ?? false)
    }

    func testSaveProgressUpdatesExisting() {
        // Given existing progress
        let bookId = TestFixtures.testBookId.uuidString
        sut.saveProgress(bookId: bookId, position: 100.0, completed: false)

        // When saveProgress is called with new position
        sut.saveProgress(bookId: bookId, position: 200.0, completed: false)

        // Then position should be updated
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.positionSeconds, 200.0, accuracy: 0.01)
    }

    func testSaveProgressTracksCompleted() {
        // Given a book ID
        let bookId = TestFixtures.testBookId.uuidString

        // When saveProgress is called with completed = true
        sut.saveProgress(bookId: bookId, position: 3600.0, completed: true)

        // Then progress should be marked as completed
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertTrue(saved?.completed ?? false)
    }

    func testSaveProgressTracksCalls() {
        // Given two books
        let bookId1 = UUID().uuidString
        let bookId2 = UUID().uuidString

        // When saving progress for both
        sut.saveProgress(bookId: bookId1, position: 100.0, completed: false)
        sut.saveProgress(bookId: bookId2, position: 200.0, completed: true)

        // Then calls should be tracked
        XCTAssertEqual(sut.saveProgressCalls.count, 2)
        XCTAssertEqual(sut.saveProgressCalls[0].bookId, bookId1)
        XCTAssertEqual(sut.saveProgressCalls[0].position, 100.0)
        XCTAssertEqual(sut.saveProgressCalls[1].bookId, bookId2)
        XCTAssertTrue(sut.saveProgressCalls[1].completed)
    }

    // MARK: - Get Progress Tests

    func testGetProgressReturnsNilForUnknownBook() {
        // Given no saved progress
        let unknownId = UUID().uuidString

        // When getProgress is called
        let result = sut.getProgress(bookId: unknownId)

        // Then should return nil
        XCTAssertNil(result)
    }

    func testGetProgressTracksCalls() {
        // Given a book ID
        let bookId = TestFixtures.testBookId.uuidString

        // When getProgress is called multiple times
        _ = sut.getProgress(bookId: bookId)
        _ = sut.getProgress(bookId: bookId)
        _ = sut.getProgress(bookId: bookId)

        // Then calls should be tracked
        XCTAssertEqual(sut.getProgressCalls.count, 3)
    }

    // MARK: - Pending Sync Tests

    func testNewProgressMarkedAsPendingSync() {
        // Given a fresh save
        let bookId = TestFixtures.testBookId.uuidString
        sut.saveProgress(bookId: bookId, position: 100.0, completed: false)

        // When getAllPendingSync is called
        let pending = sut.getPendingSync()

        // Then should include the new progress
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.bookId, bookId)
    }

    func testMarkAsSyncedRemovesFromPending() {
        // Given pending progress
        let bookId = TestFixtures.testBookId.uuidString
        sut.saveProgress(bookId: bookId, position: 100.0, completed: false)
        XCTAssertEqual(sut.getPendingSync().count, 1)

        // When markAsSynced is called
        sut.markSynced(bookId: bookId)

        // Then should no longer be in pending list
        XCTAssertEqual(sut.getPendingSync().count, 0)
    }

    func testMarkSyncedTracksCalls() {
        // Given a book ID
        let bookId = TestFixtures.testBookId.uuidString
        sut.saveProgress(bookId: bookId, position: 100.0, completed: false)

        // When markSynced is called
        sut.markSynced(bookId: bookId)

        // Then call should be tracked
        XCTAssertEqual(sut.markSyncedCalls.count, 1)
        XCTAssertEqual(sut.markSyncedCalls.first, bookId)
    }

    func testHasPendingSyncReturnsCorrectValue() {
        // Given no progress
        XCTAssertFalse(sut.hasPendingSync)

        // When saving progress
        sut.saveProgress(bookId: UUID().uuidString, position: 100.0, completed: false)

        // Then hasPendingSync should be true
        XCTAssertTrue(sut.hasPendingSync)

        // When marking as synced
        sut.markSynced(bookId: sut.getPendingSync().first!.bookId)

        // Then hasPendingSync should be false
        XCTAssertFalse(sut.hasPendingSync)
    }

    func testPendingSyncCountReturnsCorrectValue() {
        // Given no progress
        XCTAssertEqual(sut.pendingSyncCount, 0)

        // When saving multiple progress entries
        sut.saveProgress(bookId: UUID().uuidString, position: 100.0, completed: false)
        sut.saveProgress(bookId: UUID().uuidString, position: 200.0, completed: false)
        sut.saveProgress(bookId: UUID().uuidString, position: 300.0, completed: false)

        // Then pendingSyncCount should be 3
        XCTAssertEqual(sut.pendingSyncCount, 3)
    }

    // MARK: - Update From Server Tests

    func testUpdateFromServerUpdatesLocalProgress() {
        // Given no local progress
        let bookId = TestFixtures.testBookId.uuidString
        let serverDate = Date()

        // When updateFromServer is called
        sut.updateFromServer(bookId: bookId, position: 500.0, completed: false, lastPlayed: serverDate)

        // Then local progress should be updated
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.positionSeconds, 500.0, accuracy: 0.01)
    }

    func testUpdateFromServerPreservesNewerLocalProgress() {
        // Given local progress that is newer
        let bookId = TestFixtures.testBookId.uuidString
        let localDate = Date()
        sut.addPendingProgress(bookId: bookId, position: 600.0, lastPlayed: localDate)

        // When updateFromServer is called with older data
        let olderServerDate = Date().addingTimeInterval(-3600) // 1 hour ago
        sut.updateFromServer(bookId: bookId, position: 300.0, completed: false, lastPlayed: olderServerDate)

        // Then local progress should be preserved
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.positionSeconds, 600.0, accuracy: 0.01)
    }

    func testUpdateFromServerMarksAsNotNeedingSync() {
        // Given no local progress
        let bookId = TestFixtures.testBookId.uuidString

        // When updateFromServer is called
        sut.updateFromServer(bookId: bookId, position: 500.0, completed: false, lastPlayed: Date())

        // Then progress should not need sync
        let saved = sut.getProgress(bookId: bookId)
        XCTAssertFalse(saved?.needsSync ?? true)
    }

    func testUpdateFromServerTracksCalls() {
        // Given a book ID
        let bookId = TestFixtures.testBookId.uuidString
        let date = Date()

        // When updateFromServer is called
        sut.updateFromServer(bookId: bookId, position: 500.0, completed: true, lastPlayed: date)

        // Then call should be tracked
        XCTAssertEqual(sut.updateFromServerCalls.count, 1)
        XCTAssertEqual(sut.updateFromServerCalls.first?.bookId, bookId)
        XCTAssertEqual(sut.updateFromServerCalls.first?.position, 500.0)
        XCTAssertTrue(sut.updateFromServerCalls.first?.completed ?? false)
    }

    // MARK: - Clear Cache Tests

    func testClearCacheRemovesAllData() {
        // Given saved progress
        sut.saveProgress(bookId: UUID().uuidString, position: 100.0, completed: false)
        sut.saveProgress(bookId: UUID().uuidString, position: 200.0, completed: false)
        XCTAssertEqual(sut.pendingSyncCount, 2)

        // When clearCache is called
        sut.clearCache()

        // Then all progress should be removed
        XCTAssertEqual(sut.pendingSyncCount, 0)
        XCTAssertTrue(sut.clearCacheCalled)
    }

    // MARK: - Test Helper Tests

    func testAddSyncedProgressDoesNotNeedSync() {
        // Given synced progress added via helper
        let bookId = TestFixtures.testBookId.uuidString
        sut.addSyncedProgress(bookId: bookId, position: 100.0)

        // When checking pending sync
        let pending = sut.getPendingSync()

        // Then it should not be in pending
        XCTAssertEqual(pending.count, 0)
    }

    func testAddPendingProgressNeedsSync() {
        // Given pending progress added via helper
        let bookId = TestFixtures.testBookId.uuidString
        sut.addPendingProgress(bookId: bookId, position: 100.0)

        // When checking pending sync
        let pending = sut.getPendingSync()

        // Then it should be in pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.bookId, bookId)
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() {
        // Given state
        sut.saveProgress(bookId: UUID().uuidString, position: 100.0, completed: false)
        _ = sut.getProgress(bookId: UUID().uuidString)
        _ = sut.getPendingSync()
        sut.markSynced(bookId: UUID().uuidString)
        sut.updateFromServer(bookId: UUID().uuidString, position: 100.0, completed: false, lastPlayed: Date())
        sut.clearCache()
        sut.saveShouldFail = true

        // When resetting
        sut.reset()

        // Then all state should be cleared
        XCTAssertTrue(sut.progressData.isEmpty)
        XCTAssertTrue(sut.saveProgressCalls.isEmpty)
        XCTAssertTrue(sut.getProgressCalls.isEmpty)
        XCTAssertEqual(sut.getPendingSyncCallCount, 0)
        XCTAssertTrue(sut.markSyncedCalls.isEmpty)
        XCTAssertTrue(sut.updateFromServerCalls.isEmpty)
        XCTAssertFalse(sut.clearCacheCalled)
        XCTAssertFalse(sut.saveShouldFail)
    }
}
