//
//  ChapterFetching.swift
//  BookVault
//
//  Protocol for ChapterManager to enable testing with dependency injection.
//

import Foundation

/// Chapter lookup, as `AudioPlayerManager` needs it.
///
/// Deliberately narrower than `ChapterManager`'s full surface: the player only
/// ever reads chapters, so this omits the `@Published` state the views bind to.
/// That keeps the player's dependency small and makes it trivial to fake in
/// tests.
@MainActor
protocol ChapterFetching {
    /// Fetch chapters for a book, using the cache when warm.
    /// - Returns: the chapters, or an empty array when the book has none.
    func fetchChapters(bookId: String) async -> [Chapter]

    /// Chapters already in the cache, without hitting the network.
    func getCachedChapters(bookId: String) -> [Chapter]

    /// Whether a cache entry exists for the book.
    func hasCachedChapters(bookId: String) -> Bool
}
