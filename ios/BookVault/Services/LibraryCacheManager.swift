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
        var version: Int = 1
        var books: [LibraryBook]
        var lastSyncDate: Date
        var userId: String // Tied to user to avoid cross-account issues
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

        let cache = LibraryCache(
            version: 1,
            books: books,
            lastSyncDate: Date(),
            userId: userId
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
            let cache = try decoder.decode(LibraryCache.self, from: data)

            // Verify cache belongs to current user
            guard cache.userId == userId else {
                DebugLogger.warning("Library cache belongs to different user, ignoring")
                return nil
            }

            DebugLogger.database("Library cache loaded: \(cache.books.count) books (synced: \(cache.lastSyncDate))")
            return cache.books
        } catch {
            DebugLogger.error("Failed to load library cache", error: error)
            return nil
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
