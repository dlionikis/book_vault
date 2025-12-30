//
//  SyncManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 8: Offline Mode Support
//

import Foundation
import Combine

/// Manages background sync when connectivity returns
/// Monitors network state and syncs pending progress when online
@MainActor
class SyncManager: ObservableObject, SyncManaging {
    static let shared = SyncManager()

    // MARK: - Published Properties

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var pendingSyncCount: Int = 0

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false

    // MARK: - Dependencies

    private let networkMonitor: any NetworkMonitoring
    private let offlineProgressStore: any OfflineStoring
    private let progressManager: any ProgressManaging
    private let libraryManager: any LibraryManaging

    // MARK: - Initialization

    /// Production singleton initializer
    private convenience init() {
        self.init(
            networkMonitor: NetworkMonitor.shared,
            offlineProgressStore: OfflineProgressStore.shared,
            progressManager: ProgressManager.shared,
            libraryManager: LibraryManager.shared
        )
    }

    /// Testable initializer with dependency injection
    /// - Parameters:
    ///   - networkMonitor: Network connectivity monitor
    ///   - offlineProgressStore: Offline progress storage
    ///   - progressManager: Progress manager for syncing
    ///   - libraryManager: Library manager for cache refresh
    init(
        networkMonitor: any NetworkMonitoring,
        offlineProgressStore: any OfflineStoring,
        progressManager: any ProgressManaging,
        libraryManager: any LibraryManaging
    ) {
        self.networkMonitor = networkMonitor
        self.offlineProgressStore = offlineProgressStore
        self.progressManager = progressManager
        self.libraryManager = libraryManager
        // Update pending count on init
        updatePendingSyncCount()
    }

    // MARK: - Public API

    /// Start monitoring network state for sync opportunities
    /// Should be called once at app launch
    func startMonitoring() {
        guard !isMonitoring else {
            DebugLogger.network("SyncManager already monitoring")
            return
        }

        isMonitoring = true

        // Monitor network connectivity changes
        // For production, we cast to NetworkMonitor to access the publisher
        // For testing, use triggerSyncIfOnline() directly
        if let realMonitor = networkMonitor as? NetworkMonitor {
            realMonitor.$isConnected
                .removeDuplicates()
                .filter { $0 }  // Only when becomes connected
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)  // Wait for stable connection
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.syncPendingProgress()
                    }
                }
                .store(in: &cancellables)
        }

        DebugLogger.network("SyncManager monitoring started")

        // Attempt initial sync if already connected
        if networkMonitor.isConnected {
            Task {
                await syncPendingProgress()
            }
        }
    }

    /// Trigger sync if online - for testing purposes
    /// In production, this is called automatically via Combine subscription
    func triggerSyncIfOnline() async {
        if networkMonitor.isConnected {
            await syncPendingProgress()
        }
    }

    /// Stop monitoring network state
    func stopMonitoring() {
        cancellables.removeAll()
        isMonitoring = false
        DebugLogger.network("SyncManager monitoring stopped")
    }

    /// Manually trigger sync of pending progress
    /// Call this to force sync attempt
    func syncPendingProgress() async {
        guard networkMonitor.isConnected else {
            DebugLogger.network("Cannot sync: offline")
            return
        }

        guard !isSyncing else {
            DebugLogger.network("Sync already in progress")
            return
        }

        let pending = offlineProgressStore.getPendingSync()

        guard !pending.isEmpty else {
            DebugLogger.database("No pending progress to sync")
            updatePendingSyncCount()
            return
        }

        isSyncing = true
        DebugLogger.database("Starting sync of \(pending.count) progress entries")

        var successCount = 0
        var failCount = 0

        for progress in pending {
            do {
                // Use ProgressManager to sync - it handles marking as synced
                _ = try await progressManager.saveProgress(
                    for: progress.bookId,
                    positionSeconds: progress.positionSeconds
                )
                successCount += 1
            } catch {
                failCount += 1
                DebugLogger.error("Failed to sync progress for \(progress.bookId.prefix(8))...", error: error)
            }
        }

        isSyncing = false
        lastSyncDate = Date()
        updatePendingSyncCount()

        if failCount == 0 {
            DebugLogger.success("Synced \(successCount) progress entries")
        } else {
            DebugLogger.warning("Synced \(successCount)/\(pending.count) progress entries (\(failCount) failed)")
        }
    }

    /// Force refresh library cache when back online
    func refreshLibraryCache() async {
        guard networkMonitor.isConnected else {
            return
        }

        do {
            try await libraryManager.refreshCache()
            DebugLogger.success("Library cache refreshed after coming online")
        } catch {
            DebugLogger.error("Failed to refresh library cache", error: error)
        }
    }

    // MARK: - Private Helpers

    private func updatePendingSyncCount() {
        pendingSyncCount = offlineProgressStore.pendingSyncCount
    }
}
