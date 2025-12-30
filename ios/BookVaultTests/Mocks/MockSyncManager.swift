//
//  MockSyncManager.swift
//  BookVaultTests
//
//  Mock SyncManager for testing - simulates sync operations.
//  Phase 5: Offline Mode Tests
//

import Combine
import Foundation
@testable import BookVault

/// Mock sync manager for testing
@MainActor
class MockSyncManager: ObservableObject, SyncManaging {
    // MARK: - Published Properties

    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var pendingSyncCount: Int = 0

    // MARK: - Internal State

    var isMonitoring: Bool = false

    // MARK: - Call Tracking

    var startMonitoringCalls: Int = 0
    var stopMonitoringCalls: Int = 0
    var syncPendingProgressCalls: Int = 0
    var refreshLibraryCacheCalls: Int = 0

    // MARK: - Behavior Configuration

    var syncShouldFail: Bool = false
    var syncDelay: TimeInterval = 0
    var refreshShouldFail: Bool = false

    // MARK: - Completion Handlers for Testing

    var onSyncComplete: (() -> Void)?
    var onRefreshComplete: (() -> Void)?

    // MARK: - Protocol Implementation

    func startMonitoring() {
        startMonitoringCalls += 1
        isMonitoring = true
    }

    func stopMonitoring() {
        stopMonitoringCalls += 1
        isMonitoring = false
    }

    func syncPendingProgress() async {
        syncPendingProgressCalls += 1

        if syncDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(syncDelay * 1_000_000_000))
        }

        if syncShouldFail {
            // Simulate failure - don't update lastSyncDate
            return
        }

        isSyncing = true
        // Simulate sync work
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        isSyncing = false
        lastSyncDate = Date()
        pendingSyncCount = 0

        onSyncComplete?()
    }

    func refreshLibraryCache() async {
        refreshLibraryCacheCalls += 1

        if refreshShouldFail {
            return
        }

        // Simulate refresh work
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        onRefreshComplete?()
    }

    // MARK: - Test Helpers

    /// Simulate sync in progress
    func simulateSyncInProgress() {
        isSyncing = true
    }

    /// Simulate sync completion
    func simulateSyncComplete(date: Date = Date()) {
        isSyncing = false
        lastSyncDate = date
        pendingSyncCount = 0
    }

    /// Simulate pending items
    func simulatePendingItems(count: Int) {
        pendingSyncCount = count
    }

    // MARK: - Reset

    func reset() {
        isSyncing = false
        lastSyncDate = nil
        pendingSyncCount = 0
        isMonitoring = false
        startMonitoringCalls = 0
        stopMonitoringCalls = 0
        syncPendingProgressCalls = 0
        refreshLibraryCacheCalls = 0
        syncShouldFail = false
        syncDelay = 0
        refreshShouldFail = false
        onSyncComplete = nil
        onRefreshComplete = nil
    }
}
