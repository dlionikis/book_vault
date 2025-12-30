//
//  LibraryCaching.swift
//  BookVault
//
//  Protocol for LibraryCacheManager to enable testing.
//  Phase 5: Offline Mode Tests
//

import Foundation

/// Protocol for library cache management to enable testing with mocks
@MainActor
protocol LibraryCaching {
    /// Save library books to disk
    /// - Parameter books: Array of library books to cache
    func saveLibrary(books: [LibraryBook])

    /// Load library books from disk
    /// - Returns: Array of cached library books, or nil if no valid cache exists
    func loadLibrary() -> [LibraryBook]?

    /// Check if valid cache exists for current user
    /// - Returns: True if cache exists and belongs to current user
    func isCacheValid() -> Bool

    /// Get the last sync date for the cache
    /// - Returns: Date of last sync, or nil if no cache exists
    func getLastSyncDate() -> Date?

    /// Clear the library cache
    /// Called on logout to ensure clean state for next user
    func clearCache()
}
