//
//  SyncManaging.swift
//  BookVault
//
//  Protocol for SyncManager to enable testing.
//  Phase 5: Offline Mode Tests
//

import Foundation

/// Protocol for sync management to enable testing with mocks
@MainActor
protocol SyncManaging: ObservableObject {
    /// Whether a sync is currently in progress
    var isSyncing: Bool { get }

    /// The date of the last successful sync
    var lastSyncDate: Date? { get }

    /// Number of items pending sync
    var pendingSyncCount: Int { get }

    /// Start monitoring network state for sync opportunities
    /// Should be called once at app launch
    func startMonitoring()

    /// Stop monitoring network state
    func stopMonitoring()

    /// Manually trigger sync of pending progress
    /// Call this to force sync attempt
    func syncPendingProgress() async

    /// Force refresh library cache when back online
    func refreshLibraryCache() async
}
