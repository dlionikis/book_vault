//
//  OfflineProgressStore.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 8: Offline Mode Support
//

import Foundation

/// Local playback progress with sync queue for offline support
@MainActor
class OfflineProgressStore: ObservableObject {
    static let shared = OfflineProgressStore()

    // MARK: - Storage

    private let cacheDirectory: URL
    private let cacheFileName = "progress.json"
    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(cacheFileName)
    }

    // MARK: - Data Structures

    struct LocalProgress: Codable {
        let bookId: String
        var positionSeconds: Double
        var completed: Bool
        var lastPlayed: Date
        var needsSync: Bool  // True if not yet synced to server
    }

    struct ProgressCache: Codable {
        var version: Int = 1
        var progress: [String: LocalProgress]  // bookId -> progress
        var userId: String
    }

    // MARK: - In-Memory Cache

    private var progressCache: ProgressCache?

    // MARK: - Initialization

    private init() {
        // Create cache directory in Documents folder
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("cache", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load existing cache into memory
        loadCacheFromDisk()

        DebugLogger.storage("OfflineProgressStore initialized at: \(cacheDirectory.path)")
    }

    // MARK: - Public API

    /// Save progress locally (called on every playback position update)
    /// - Parameters:
    ///   - bookId: The book's ID
    ///   - position: Current playback position in seconds
    ///   - completed: Whether the book is completed
    func saveProgress(bookId: String, position: Double, completed: Bool = false) {
        guard let userId = getCurrentUserId() else {
            DebugLogger.warning("Cannot save progress: no user logged in")
            return
        }

        // Initialize cache if needed
        if progressCache == nil || progressCache?.userId != userId {
            progressCache = ProgressCache(version: 1, progress: [:], userId: userId)
        }

        // Update or create progress entry
        let localProgress = LocalProgress(
            bookId: bookId,
            positionSeconds: position,
            completed: completed,
            lastPlayed: Date(),
            needsSync: true  // Mark as needing sync
        )

        progressCache?.progress[bookId] = localProgress

        // Persist to disk
        saveCacheToDisk()

        DebugLogger.database("Progress saved locally: \(position)s for book \(bookId.prefix(8))...")
    }

    /// Get local progress for a book
    /// - Parameter bookId: The book's ID
    /// - Returns: Local progress if available
    func getProgress(bookId: String) -> LocalProgress? {
        guard let userId = getCurrentUserId(),
              let cache = progressCache,
              cache.userId == userId else {
            return nil
        }

        return cache.progress[bookId]
    }

    /// Get all entries that need to be synced to the server
    /// - Returns: Array of progress entries with needsSync = true
    func getPendingSync() -> [LocalProgress] {
        guard let userId = getCurrentUserId(),
              let cache = progressCache,
              cache.userId == userId else {
            return []
        }

        return cache.progress.values.filter { $0.needsSync }
    }

    /// Mark a progress entry as synced (called after successful API sync)
    /// - Parameter bookId: The book's ID
    func markSynced(bookId: String) {
        guard var progress = progressCache?.progress[bookId] else {
            return
        }

        progress.needsSync = false
        progressCache?.progress[bookId] = progress

        saveCacheToDisk()

        DebugLogger.database("Progress marked as synced for book \(bookId.prefix(8))...")
    }

    /// Update local progress from server data (for merge scenarios)
    /// - Parameters:
    ///   - bookId: The book's ID
    ///   - serverProgress: Progress data from server
    func updateFromServer(bookId: String, position: Double, completed: Bool, lastPlayed: Date) {
        guard let userId = getCurrentUserId() else {
            return
        }

        // Initialize cache if needed
        if progressCache == nil || progressCache?.userId != userId {
            progressCache = ProgressCache(version: 1, progress: [:], userId: userId)
        }

        // Check if local progress is newer
        if let localProgress = progressCache?.progress[bookId] {
            if localProgress.lastPlayed > lastPlayed {
                // Local is newer, keep it but mark for sync
                DebugLogger.database("Keeping local progress (newer) for book \(bookId.prefix(8))...")
                return
            }
        }

        // Server is newer, update local
        let serverProgress = LocalProgress(
            bookId: bookId,
            positionSeconds: position,
            completed: completed,
            lastPlayed: lastPlayed,
            needsSync: false  // Already synced from server
        )

        progressCache?.progress[bookId] = serverProgress
        saveCacheToDisk()

        DebugLogger.database("Progress updated from server for book \(bookId.prefix(8))...")
    }

    /// Check if there are any pending sync items
    var hasPendingSync: Bool {
        !getPendingSync().isEmpty
    }

    /// Get count of pending sync items
    var pendingSyncCount: Int {
        getPendingSync().count
    }

    /// Clear all cached progress
    /// Called on logout to ensure clean state for next user
    func clearCache() {
        progressCache = nil

        do {
            if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                try FileManager.default.removeItem(at: cacheFileURL)
                DebugLogger.success("Progress cache cleared")
            }
        } catch {
            DebugLogger.error("Failed to clear progress cache", error: error)
        }
    }

    // MARK: - Private Helpers

    /// Get current user's ID from AuthManager
    private func getCurrentUserId() -> String? {
        AuthManager.shared.currentUser?.id.uuidString
    }

    /// Load cache from disk into memory
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            progressCache = try decoder.decode(ProgressCache.self, from: data)

            DebugLogger.database("Progress cache loaded: \(progressCache?.progress.count ?? 0) entries")
        } catch {
            DebugLogger.error("Failed to load progress cache", error: error)
        }
    }

    /// Save in-memory cache to disk
    private func saveCacheToDisk() {
        guard let cache = progressCache else {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            DebugLogger.error("Failed to save progress cache", error: error)
        }
    }
}
