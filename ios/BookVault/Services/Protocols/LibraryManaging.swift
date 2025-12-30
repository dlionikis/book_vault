//
//  LibraryManaging.swift
//  BookVault
//
//  Protocol for LibraryManager to enable testing with dependency injection.
//  Phase 3: DI-Enabled Services
//

import Foundation

/// Protocol for LibraryManager to enable testing
@MainActor
protocol LibraryManaging {
    /// Whether the manager is currently loading
    var isLoading: Bool { get }

    /// Current error, if any
    var error: Error? { get }

    /// Library version counter (increments on changes)
    var libraryVersion: Int { get }

    /// Whether current data is from cache
    var isShowingCachedData: Bool { get }

    /// Fetch user's library books
    /// - Parameter forceRefresh: If true, bypasses cache
    /// - Returns: Array of books in user's library
    func fetchLibraryBooks(forceRefresh: Bool) async throws -> [Book]

    /// Add book to user's library
    /// - Parameter bookId: The book's ID string
    func addToLibrary(bookId: String) async throws

    /// Remove book from user's library
    /// - Parameter bookId: The book's ID string
    func removeFromLibrary(bookId: String) async throws

    /// Check if a book is in the user's library
    /// - Parameter bookId: The book's ID string
    /// - Returns: True if book is in library
    func isInLibrary(bookId: String) async throws -> Bool

    /// Force refresh the cache
    func refreshCache() async throws
}

// Default parameter extension
extension LibraryManaging {
    func fetchLibraryBooks() async throws -> [Book] {
        try await fetchLibraryBooks(forceRefresh: false)
    }
}
