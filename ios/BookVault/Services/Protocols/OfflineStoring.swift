//
//  OfflineStoring.swift
//  BookVault
//
//  Protocol for OfflineProgressStore to enable testing.
//  Phase 5: Offline Mode Tests
//

import Foundation

/// Protocol for offline progress storage to enable testing with mocks
@MainActor
protocol OfflineStoring {
    /// Local progress data structure
    typealias LocalProgress = OfflineProgressStore.LocalProgress

    /// Save progress locally (called on every playback position update)
    /// - Parameters:
    ///   - bookId: The book's ID
    ///   - position: Current playback position in seconds
    ///   - completed: Whether the book is completed
    func saveProgress(bookId: String, position: Double, completed: Bool)

    /// Get local progress for a book
    /// - Parameter bookId: The book's ID
    /// - Returns: Local progress if available
    func getProgress(bookId: String) -> LocalProgress?

    /// Get all entries that need to be synced to the server
    /// - Returns: Array of progress entries with needsSync = true
    func getPendingSync() -> [LocalProgress]

    /// Mark a progress entry as synced (called after successful API sync)
    /// - Parameter bookId: The book's ID
    func markSynced(bookId: String)

    /// Update local progress from server data (for merge scenarios)
    /// - Parameters:
    ///   - bookId: The book's ID
    ///   - position: Position from server
    ///   - completed: Completed status from server
    ///   - lastPlayed: Last played date from server
    func updateFromServer(bookId: String, position: Double, completed: Bool, lastPlayed: Date)

    /// Check if there are any pending sync items
    var hasPendingSync: Bool { get }

    /// Get count of pending sync items
    var pendingSyncCount: Int { get }

    /// Clear all cached progress
    /// Called on logout to ensure clean state for next user
    func clearCache()
}
