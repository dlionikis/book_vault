//
//  CoverCacheManager.swift
//  BookVault
//
//  Created by Claude Code on 12/31/25.
//  Phase 2: Cover Image Caching for Presigned URLs
//

import Foundation
import UIKit

/// Caches cover images to disk by book ID, solving presigned URL expiry issues
/// - Images are keyed by book ID, not URL, so presigned URL expiry doesn't affect cache hits
/// - In-memory cache provides fast access for visible images
/// - Disk cache persists across app launches
@MainActor
class CoverCacheManager: ObservableObject, CoverCaching {
    static let shared = CoverCacheManager()

    // MARK: - Storage

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    // In-memory cache for fast access
    private var memoryCache: [UUID: UIImage] = [:]
    private let maxMemoryCacheSize = 50

    /// Provider for current user ID (injected for testing)
    private let userIdProvider: () -> String?

    // MARK: - Initialization

    /// Production singleton initializer
    private convenience init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsPath.appendingPathComponent("covers", isDirectory: true)
        self.init(
            cacheDirectory: cacheDir,
            userIdProvider: { AuthManager.shared.currentUser?.id.uuidString }
        )
    }

    /// Testable initializer that accepts cache directory and user ID provider
    /// - Parameters:
    ///   - cacheDirectory: Directory for cache files (Documents/covers in production)
    ///   - userIdProvider: Closure that returns current user ID (uses AuthManager in production)
    init(cacheDirectory: URL, userIdProvider: @escaping () -> String?) {
        self.cacheDirectory = cacheDirectory
        self.userIdProvider = userIdProvider

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        DebugLogger.storage("CoverCacheManager initialized at: \(cacheDirectory.path)")
    }

    // MARK: - Public API

    /// Get cached cover image for a book
    /// - Parameter bookId: UUID of the book
    /// - Returns: Cached UIImage or nil if not cached
    func getCover(for bookId: UUID) -> UIImage? {
        // Check memory cache first
        if let cached = memoryCache[bookId] {
            return cached
        }

        // Check disk cache
        let fileURL = coverFileURL(for: bookId)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data)
        else {
            return nil
        }

        // Add to memory cache
        addToMemoryCache(bookId: bookId, image: image)
        return image
    }

    /// Check if cover is cached for a book
    /// - Parameter bookId: UUID of the book
    /// - Returns: True if cover is in memory or disk cache
    func hasCover(for bookId: UUID) -> Bool {
        memoryCache[bookId] != nil || fileManager.fileExists(atPath: coverFileURL(for: bookId).path)
    }

    /// Get local file URL for cached cover (for use with SwiftUI Image if needed)
    /// - Parameter bookId: UUID of the book
    /// - Returns: Local file URL or nil if not cached
    func localCoverURL(for bookId: UUID) -> URL? {
        let fileURL = coverFileURL(for: bookId)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// Download and cache cover image from URL
    /// - Parameters:
    ///   - bookId: UUID of the book
    ///   - url: Remote URL to download from (presigned S3 URL)
    /// - Throws: CoverCacheError if download fails
    func cacheCover(for bookId: UUID, from url: URL) async throws {
        // Skip if already cached
        guard !hasCover(for: bookId) else { return }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let image = UIImage(data: data)
        else {
            throw CoverCacheError.downloadFailed
        }

        // Save to disk
        let fileURL = coverFileURL(for: bookId)
        try data.write(to: fileURL)

        // Add to memory cache
        addToMemoryCache(bookId: bookId, image: image)

        DebugLogger.storage("Cached cover for book: \(bookId)")
    }

    /// Delete cached cover for a book
    /// - Parameter bookId: UUID of the book
    func deleteCover(for bookId: UUID) {
        memoryCache.removeValue(forKey: bookId)
        let fileURL = coverFileURL(for: bookId)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Clear all cached covers
    /// Called on logout to ensure clean state for next user
    func clearCache() {
        memoryCache.removeAll()
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                DebugLogger.success("Cover cache cleared")
            }
        } catch {
            DebugLogger.error("Failed to clear cover cache", error: error)
        }
    }

    /// Get the number of cached covers (for diagnostics)
    /// - Returns: Number of cover images stored on disk
    func getCacheCount() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        else {
            return 0
        }
        return files.filter { $0.pathExtension == "jpg" }.count
    }

    /// Get cache size in bytes (for diagnostics)
    /// - Returns: Total size of all cached cover images
    func getCacheSize() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        else {
            return 0
        }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    // MARK: - Private Helpers

    private func coverFileURL(for bookId: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(bookId.uuidString).jpg")
    }

    private func addToMemoryCache(bookId: UUID, image: UIImage) {
        // Evict oldest if at capacity
        if memoryCache.count >= maxMemoryCacheSize {
            memoryCache.removeValue(forKey: memoryCache.keys.first!)
        }
        memoryCache[bookId] = image
    }
}

// MARK: - Errors

enum CoverCacheError: LocalizedError {
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download cover image"
        }
    }
}
