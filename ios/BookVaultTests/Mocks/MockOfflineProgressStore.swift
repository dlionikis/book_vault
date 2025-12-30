//
//  MockOfflineProgressStore.swift
//  BookVaultTests
//
//  Mock OfflineProgressStore for testing - simulates offline progress storage.
//  Phase 5: Offline Mode Tests
//

import Foundation
@testable import BookVault

/// Mock offline progress store for testing
@MainActor
class MockOfflineProgressStore: OfflineStoring {

    // MARK: - In-Memory Storage

    var progressData: [String: OfflineProgressStore.LocalProgress] = [:]

    // MARK: - Computed Properties

    var hasPendingSync: Bool {
        !getPendingSync().isEmpty
    }

    var pendingSyncCount: Int {
        getPendingSync().count
    }

    // MARK: - Call Tracking

    var saveProgressCalls: [(bookId: String, position: Double, completed: Bool)] = []
    var getProgressCalls: [String] = []
    var getPendingSyncCallCount: Int = 0
    var markSyncedCalls: [String] = []
    var updateFromServerCalls: [(bookId: String, position: Double, completed: Bool, lastPlayed: Date)] = []
    var clearCacheCalled: Bool = false

    // MARK: - Error Simulation

    var saveShouldFail: Bool = false

    // MARK: - Protocol Implementation

    func saveProgress(bookId: String, position: Double, completed: Bool = false) {
        saveProgressCalls.append((bookId, position, completed))

        if saveShouldFail {
            return
        }

        let progress = OfflineProgressStore.LocalProgress(
            bookId: bookId,
            positionSeconds: position,
            completed: completed,
            lastPlayed: Date(),
            needsSync: true
        )
        progressData[bookId] = progress
    }

    func getProgress(bookId: String) -> OfflineProgressStore.LocalProgress? {
        getProgressCalls.append(bookId)
        return progressData[bookId]
    }

    func getPendingSync() -> [OfflineProgressStore.LocalProgress] {
        getPendingSyncCallCount += 1
        return progressData.values.filter { $0.needsSync }
    }

    func markSynced(bookId: String) {
        markSyncedCalls.append(bookId)

        guard var progress = progressData[bookId] else {
            return
        }

        progress = OfflineProgressStore.LocalProgress(
            bookId: progress.bookId,
            positionSeconds: progress.positionSeconds,
            completed: progress.completed,
            lastPlayed: progress.lastPlayed,
            needsSync: false
        )
        progressData[bookId] = progress
    }

    func updateFromServer(bookId: String, position: Double, completed: Bool, lastPlayed: Date) {
        updateFromServerCalls.append((bookId, position, completed, lastPlayed))

        // Check if local progress is newer
        if let localProgress = progressData[bookId] {
            if localProgress.lastPlayed > lastPlayed {
                // Local is newer, keep it
                return
            }
        }

        // Server is newer, update local
        let serverProgress = OfflineProgressStore.LocalProgress(
            bookId: bookId,
            positionSeconds: position,
            completed: completed,
            lastPlayed: lastPlayed,
            needsSync: false
        )
        progressData[bookId] = serverProgress
    }

    func clearCache() {
        clearCacheCalled = true
        progressData = [:]
    }

    // MARK: - Test Helpers

    /// Simulate adding progress that's already synced
    func addSyncedProgress(bookId: String, position: Double, completed: Bool = false, lastPlayed: Date = Date()) {
        let progress = OfflineProgressStore.LocalProgress(
            bookId: bookId,
            positionSeconds: position,
            completed: completed,
            lastPlayed: lastPlayed,
            needsSync: false
        )
        progressData[bookId] = progress
    }

    /// Simulate adding progress that needs to be synced
    func addPendingProgress(bookId: String, position: Double, completed: Bool = false, lastPlayed: Date = Date()) {
        let progress = OfflineProgressStore.LocalProgress(
            bookId: bookId,
            positionSeconds: position,
            completed: completed,
            lastPlayed: lastPlayed,
            needsSync: true
        )
        progressData[bookId] = progress
    }

    // MARK: - Reset

    func reset() {
        progressData = [:]
        saveProgressCalls = []
        getProgressCalls = []
        getPendingSyncCallCount = 0
        markSyncedCalls = []
        updateFromServerCalls = []
        clearCacheCalled = false
        saveShouldFail = false
    }
}
