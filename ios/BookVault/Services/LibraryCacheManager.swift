//
//  LibraryCacheManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 8: Offline Mode Support
//

import Foundation

/// Persists user's library books to disk for offline access
@MainActor
class LibraryCacheManager: ObservableObject, LibraryCaching {
    static let shared = LibraryCacheManager()

    // MARK: - Storage

    private let cacheDirectory: URL
    private let cacheFileName = "library.json"
    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(cacheFileName)
    }

    /// Provider for current user ID (injected for testing)
    private let userIdProvider: () -> String?

    // MARK: - Cache Data Structure

    struct LibraryCache: Codable {
        var version: Int = 2 // Bumped to 2 for cache stats tracking
        var books: [LibraryBook]
        var lastSyncDate: Date
        var userId: String // Tied to user to avoid cross-account issues
        var createdAt: Date // When the cache was first created
        var lastAccessedAt: Date // When the cache was last read
        var accessCount: Int // Number of times the cache has been read

        // Custom decoder for backwards compatibility
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            books = try container.decode([LibraryBook].self, forKey: .books)
            lastSyncDate = try container.decode(Date.self, forKey: .lastSyncDate)
            userId = try container.decode(String.self, forKey: .userId)
            // Backwards compatibility: use lastSyncDate if no createdAt
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? lastSyncDate
            lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt) ?? Date()
            accessCount = try container.decodeIfPresent(Int.self, forKey: .accessCount) ?? 0
        }

        init(books: [LibraryBook], lastSyncDate: Date, userId: String, createdAt: Date, lastAccessedAt: Date, accessCount: Int) {
            self.version = 2
            self.books = books
            self.lastSyncDate = lastSyncDate
            self.userId = userId
            self.createdAt = createdAt
            self.lastAccessedAt = lastAccessedAt
            self.accessCount = accessCount
        }
    }

    /// Statistics about the library cache
    struct LibraryCacheStats {
        let bookCount: Int
        let createdAt: Date?
        let lastSyncDate: Date?
        let lastAccessedAt: Date?
        let accessCount: Int
    }

    // MARK: - Initialization

    /// Production singleton initializer
    private convenience init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsPath.appendingPathComponent("cache", isDirectory: true)
        self.init(
            cacheDirectory: cacheDir,
            userIdProvider: { AuthManager.shared.currentUser?.id.uuidString }
        )
    }

    /// Testable initializer that accepts cache directory and user ID provider
    /// - Parameters:
    ///   - cacheDirectory: Directory for cache files (Documents/cache in production)
    ///   - userIdProvider: Closure that returns current user ID (uses AuthManager in production)
    init(cacheDirectory: URL, userIdProvider: @escaping () -> String?) {
        self.cacheDirectory = cacheDirectory
        self.userIdProvider = userIdProvider

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        DebugLogger.storage("LibraryCacheManager initialized at: \(cacheDirectory.path)")
    }

    // MARK: - Public API

    /// Save library books to disk
    /// - Parameter books: Array of library books to cache
    func saveLibrary(books: [LibraryBook]) {
        guard let userId = getCurrentUserId() else {
            DebugLogger.warning("Cannot save library cache: no user logged in")
            return
        }

        // Try to load existing cache to preserve createdAt and accessCount
        let existingStats = getCacheStats()
        let now = Date()

        let cache = LibraryCache(
            books: books,
            lastSyncDate: now,
            userId: userId,
            createdAt: existingStats.createdAt ?? now, // Preserve or set new
            lastAccessedAt: existingStats.lastAccessedAt ?? now,
            accessCount: existingStats.accessCount
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheFileURL, options: .atomic)

            DebugLogger.success("Library cache saved: \(books.count) books")
        } catch {
            DebugLogger.error("Failed to save library cache", error: error)
        }
    }

    /// Load library books from disk
    /// - Returns: Array of cached library books, or nil if no valid cache exists
    func loadLibrary() -> [LibraryBook]? {
        guard let userId = getCurrentUserId() else {
            DebugLogger.warning("Cannot load library cache: no user logged in")
            return nil
        }

        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            DebugLogger.database("No library cache file exists")
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var cache = try decoder.decode(LibraryCache.self, from: data)

            // Verify cache belongs to current user
            guard cache.userId == userId else {
                DebugLogger.warning("Library cache belongs to different user, ignoring")
                return nil
            }

            // Update access stats and save back
            cache.lastAccessedAt = Date()
            cache.accessCount += 1
            updateCacheStats(cache)

            DebugLogger.database("Library cache HIT: \(cache.books.count) books (access #\(cache.accessCount))")
            return cache.books
        } catch {
            DebugLogger.error("Failed to load library cache", error: error)
            return nil
        }
    }

    /// Update only the stats portion of the cache (access time and count)
    private func updateCacheStats(_ cache: LibraryCache) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            DebugLogger.error("Failed to update cache stats", error: error)
        }
    }

    /// Check if valid cache exists for current user
    /// - Returns: True if cache exists and belongs to current user
    func isCacheValid() -> Bool {
        guard let userId = getCurrentUserId() else {
            return false
        }

        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(LibraryCache.self, from: data)

            return cache.userId == userId
        } catch {
            return false
        }
    }

    /// Get the last sync date for the cache
    /// - Returns: Date of last sync, or nil if no cache exists
    func getLastSyncDate() -> Date? {
        guard let userId = getCurrentUserId(),
              FileManager.default.fileExists(atPath: cacheFileURL.path)
        else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(LibraryCache.self, from: data)

            guard cache.userId == userId else {
                return nil
            }

            return cache.lastSyncDate
        } catch {
            return nil
        }
    }

    /// Get comprehensive cache statistics
    /// - Returns: LibraryCacheStats with all cache information
    func getCacheStats() -> LibraryCacheStats {
        guard let userId = getCurrentUserId(),
              FileManager.default.fileExists(atPath: cacheFileURL.path)
        else {
            return LibraryCacheStats(bookCount: 0, createdAt: nil, lastSyncDate: nil, lastAccessedAt: nil, accessCount: 0)
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(LibraryCache.self, from: data)

            guard cache.userId == userId else {
                return LibraryCacheStats(bookCount: 0, createdAt: nil, lastSyncDate: nil, lastAccessedAt: nil, accessCount: 0)
            }

            return LibraryCacheStats(
                bookCount: cache.books.count,
                createdAt: cache.createdAt,
                lastSyncDate: cache.lastSyncDate,
                lastAccessedAt: cache.lastAccessedAt,
                accessCount: cache.accessCount
            )
        } catch {
            return LibraryCacheStats(bookCount: 0, createdAt: nil, lastSyncDate: nil, lastAccessedAt: nil, accessCount: 0)
        }
    }

    /// Clear the library cache
    /// Called on logout to ensure clean state for next user
    func clearCache() {
        do {
            if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                try FileManager.default.removeItem(at: cacheFileURL)
                DebugLogger.success("Library cache cleared")
            }
        } catch {
            DebugLogger.error("Failed to clear library cache", error: error)
        }
    }

    // MARK: - Private Helpers

    /// Get current user's ID from the injected provider
    private func getCurrentUserId() -> String? {
        userIdProvider()
    }
}
