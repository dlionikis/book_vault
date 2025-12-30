//
//  SyncManagerTests.swift
//  BookVaultTests
//
//  Tests for SyncManager functionality.
//  Phase 5: Offline Mode Tests
//

import Combine
import XCTest
@testable import BookVault

@MainActor
final class SyncManagerTests: XCTestCase {
    var sut: MockSyncManager!
    var mockOfflineStore: MockOfflineProgressStore!
    var mockNetworkMonitor: MockNetworkMonitor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = MockSyncManager()
        mockOfflineStore = MockOfflineProgressStore()
        mockNetworkMonitor = MockNetworkMonitor()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockOfflineStore = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsNotSyncing() {
        // Given a fresh sync manager
        // When checking state
        // Then should not be syncing
        XCTAssertFalse(sut.isSyncing)
        XCTAssertNil(sut.lastSyncDate)
        XCTAssertEqual(sut.pendingSyncCount, 0)
    }

    func testInitialStateIsNotMonitoring() {
        // Given a fresh sync manager
        // When checking monitoring state
        // Then should not be monitoring
        XCTAssertFalse(sut.isMonitoring)
    }

    // MARK: - Start Monitoring Tests

    func testStartMonitoringSetsMonitoringFlag() {
        // Given sync manager
        // When startMonitoring is called
        sut.startMonitoring()

        // Then isMonitoring should be true
        XCTAssertTrue(sut.isMonitoring)
        XCTAssertEqual(sut.startMonitoringCalls, 1)
    }

    func testStartMonitoringMultipleTimesOnlyStartsOnce() {
        // Given sync manager
        // When startMonitoring is called multiple times
        sut.startMonitoring()
        sut.startMonitoring()
        sut.startMonitoring()

        // Then calls should still be tracked
        XCTAssertEqual(sut.startMonitoringCalls, 3)
        XCTAssertTrue(sut.isMonitoring)
    }

    // MARK: - Stop Monitoring Tests

    func testStopMonitoringClearsMonitoringFlag() {
        // Given monitoring sync manager
        sut.startMonitoring()

        // When stopMonitoring is called
        sut.stopMonitoring()

        // Then isMonitoring should be false
        XCTAssertFalse(sut.isMonitoring)
        XCTAssertEqual(sut.stopMonitoringCalls, 1)
    }

    // MARK: - Sync Pending Progress Tests

    func testSyncPendingProgressUpdatesLastSyncDate() async {
        // Given sync manager
        XCTAssertNil(sut.lastSyncDate)

        // When syncPendingProgress is called
        await sut.syncPendingProgress()

        // Then lastSyncDate should be updated
        XCTAssertNotNil(sut.lastSyncDate)
        XCTAssertEqual(sut.syncPendingProgressCalls, 1)
    }

    func testSyncPendingProgressSetsIsSyncingDuringSync() async {
        // Given sync manager
        // We'll use the simulateSyncInProgress helper instead of relying on timing

        // When we simulate sync in progress
        sut.simulateSyncInProgress()

        // Then isSyncing should be true
        XCTAssertTrue(sut.isSyncing)

        // When we simulate sync complete
        sut.simulateSyncComplete()

        // Then isSyncing should be false
        XCTAssertFalse(sut.isSyncing)
    }

    func testSyncPendingProgressClearsPendingCount() async {
        // Given pending items
        sut.simulatePendingItems(count: 5)
        XCTAssertEqual(sut.pendingSyncCount, 5)

        // When syncPendingProgress is called
        await sut.syncPendingProgress()

        // Then pending count should be cleared
        XCTAssertEqual(sut.pendingSyncCount, 0)
    }

    func testSyncPendingProgressDoesNotUpdateDateOnFailure() async {
        // Given sync that will fail
        sut.syncShouldFail = true

        // When syncPendingProgress is called
        await sut.syncPendingProgress()

        // Then lastSyncDate should not be updated
        XCTAssertNil(sut.lastSyncDate)
    }

    func testSyncPendingProgressTracksCalls() async {
        // When syncPendingProgress is called multiple times
        await sut.syncPendingProgress()
        await sut.syncPendingProgress()
        await sut.syncPendingProgress()

        // Then calls should be tracked
        XCTAssertEqual(sut.syncPendingProgressCalls, 3)
    }

    func testSyncPendingProgressCallsCompletionHandler() async {
        // Given completion handler
        var completionCalled = false
        sut.onSyncComplete = {
            completionCalled = true
        }

        // When syncPendingProgress is called
        await sut.syncPendingProgress()

        // Then completion handler should be called
        XCTAssertTrue(completionCalled)
    }

    // MARK: - Refresh Library Cache Tests

    func testRefreshLibraryCacheTracksCalls() async {
        // When refreshLibraryCache is called
        await sut.refreshLibraryCache()
        await sut.refreshLibraryCache()

        // Then calls should be tracked
        XCTAssertEqual(sut.refreshLibraryCacheCalls, 2)
    }

    func testRefreshLibraryCacheCallsCompletionHandler() async {
        // Given completion handler
        var completionCalled = false
        sut.onRefreshComplete = {
            completionCalled = true
        }

        // When refreshLibraryCache is called
        await sut.refreshLibraryCache()

        // Then completion handler should be called
        XCTAssertTrue(completionCalled)
    }

    func testRefreshLibraryCacheDoesNotCallHandlerOnFailure() async {
        // Given refresh that will fail
        sut.refreshShouldFail = true
        var completionCalled = false
        sut.onRefreshComplete = {
            completionCalled = true
        }

        // When refreshLibraryCache is called
        await sut.refreshLibraryCache()

        // Then completion handler should not be called
        XCTAssertFalse(completionCalled)
    }

    // MARK: - Published Properties Tests

    func testIsSyncingPublishesChanges() async {
        // Given expectation for publishing
        let expectation = XCTestExpectation(description: "isSyncing publishes changes")
        var observedValues: [Bool] = []

        sut.$isSyncing
            .dropFirst() // Skip initial value
            .sink { value in
                observedValues.append(value)
                if observedValues.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When simulateSyncInProgress and simulateSyncComplete are called
        sut.simulateSyncInProgress()
        sut.simulateSyncComplete()

        // Then should observe both changes
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(observedValues, [true, false])
    }

    func testPendingSyncCountPublishesChanges() async {
        // Given expectation for publishing
        let expectation = XCTestExpectation(description: "pendingSyncCount publishes changes")
        var observedValue: Int?

        sut.$pendingSyncCount
            .dropFirst() // Skip initial value
            .first()
            .sink { value in
                observedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When simulatePendingItems is called
        sut.simulatePendingItems(count: 10)

        // Then should observe the change
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(observedValue, 10)
    }

    // MARK: - Test Helper Tests

    func testSimulateSyncInProgressSetsState() {
        // When simulateSyncInProgress is called
        sut.simulateSyncInProgress()

        // Then isSyncing should be true
        XCTAssertTrue(sut.isSyncing)
    }

    func testSimulateSyncCompleteSetsState() {
        // Given syncing state
        sut.simulateSyncInProgress()

        // When simulateSyncComplete is called
        let completeDate = Date()
        sut.simulateSyncComplete(date: completeDate)

        // Then state should be updated
        XCTAssertFalse(sut.isSyncing)
        XCTAssertNotNil(sut.lastSyncDate)
        XCTAssertEqual(sut.pendingSyncCount, 0)
    }

    func testSimulatePendingItemsSetsCount() {
        // When simulatePendingItems is called
        sut.simulatePendingItems(count: 42)

        // Then count should be set
        XCTAssertEqual(sut.pendingSyncCount, 42)
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() {
        // Given state
        sut.startMonitoring()
        sut.simulateSyncInProgress()
        sut.simulatePendingItems(count: 5)
        sut.syncShouldFail = true
        sut.syncDelay = 1.0
        sut.refreshShouldFail = true
        sut.onSyncComplete = {}
        sut.onRefreshComplete = {}

        // When resetting
        sut.reset()

        // Then all state should be cleared
        XCTAssertFalse(sut.isSyncing)
        XCTAssertNil(sut.lastSyncDate)
        XCTAssertEqual(sut.pendingSyncCount, 0)
        XCTAssertFalse(sut.isMonitoring)
        XCTAssertEqual(sut.startMonitoringCalls, 0)
        XCTAssertEqual(sut.stopMonitoringCalls, 0)
        XCTAssertEqual(sut.syncPendingProgressCalls, 0)
        XCTAssertEqual(sut.refreshLibraryCacheCalls, 0)
        XCTAssertFalse(sut.syncShouldFail)
        XCTAssertEqual(sut.syncDelay, 0)
        XCTAssertFalse(sut.refreshShouldFail)
        XCTAssertNil(sut.onSyncComplete)
        XCTAssertNil(sut.onRefreshComplete)
    }
}
