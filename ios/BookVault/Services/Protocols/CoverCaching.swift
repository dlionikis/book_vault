//
//  CoverCaching.swift
//  BookVault
//
//  Protocol for CoverCacheManager to enable testing.
//  Phase 2: Cover Image Caching for Presigned URLs
//

import Foundation
import UIKit

/// Protocol for cover image cache management to enable testing with mocks
@MainActor
protocol CoverCaching {
    /// Get cached cover image for a book
    /// - Parameter bookId: UUID of the book
    /// - Returns: Cached UIImage or nil if not cached
    func getCover(for bookId: UUID) -> UIImage?

    /// Check if cover is cached for a book
    /// - Parameter bookId: UUID of the book
    /// - Returns: True if cover is in memory or disk cache
    func hasCover(for bookId: UUID) -> Bool

    /// Get local file URL for cached cover
    /// - Parameter bookId: UUID of the book
    /// - Returns: Local file URL or nil if not cached
    func localCoverURL(for bookId: UUID) -> URL?

    /// Download and cache cover image from URL
    /// - Parameters:
    ///   - bookId: UUID of the book
    ///   - url: Remote URL to download from
    /// - Throws: CoverCacheError if download fails
    func cacheCover(for bookId: UUID, from url: URL) async throws

    /// Delete cached cover for a book
    /// - Parameter bookId: UUID of the book
    func deleteCover(for bookId: UUID)

    /// Clear all cached covers
    func clearCache()

    /// Get the number of cached covers (for diagnostics)
    /// - Returns: Number of cover images stored on disk
    func getCacheCount() -> Int

    /// Get cache size in bytes (for diagnostics)
    /// - Returns: Total size of all cached cover images
    func getCacheSize() -> Int64
}
