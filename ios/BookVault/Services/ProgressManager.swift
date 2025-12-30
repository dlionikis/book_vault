//
//  ProgressManager.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 4: Progress Sync
//

import Combine
import Foundation

/// Manages user progress sync with backend API
/// This is a lightweight wrapper around APIClient for progress-related operations
/// Phase 8: Now supports local-first saving with offline sync
class ProgressManager: ObservableObject, ProgressManaging {
    static let shared = ProgressManager()

    @MainActor @Published var isLoading = false
    @MainActor @Published var error: Error?

    private let apiClient: any APIClientProtocol
    private let offlineProgressStore: any OfflineStoring
    private let networkMonitor: any NetworkMonitoring

    /// Production singleton initializer
    private convenience init() {
        self.init(
            apiClient: APIClient.shared,
            offlineStore: OfflineProgressStore.shared,
            networkMonitor: NetworkMonitor.shared
        )
    }

    /// Testable initializer with dependency injection
    /// - Parameters:
    ///   - apiClient: API client for server communication
    ///   - offlineStore: Offline progress storage
    ///   - networkMonitor: Network connectivity monitor
    @MainActor
    init(
        apiClient: any APIClientProtocol,
        offlineStore: any OfflineStoring,
        networkMonitor: any NetworkMonitoring
    ) {
        self.apiClient = apiClient
        self.offlineProgressStore = offlineStore
        self.networkMonitor = networkMonitor
    }

    /// Fetch user's progress for a book
    /// When online, fetches from server and merges with local
    /// When offline, returns local progress only
    /// - Parameter bookId: The book's UUID string
    /// - Returns: UserProgress with position and completion status
    @MainActor
    func fetchProgress(for bookId: String) async throws -> UserProgress {
        // If offline, return local progress only
        if !networkMonitor.isConnected {
            if let localProgress = offlineProgressStore.getProgress(bookId: bookId) {
                DebugLogger.database("Using local progress (offline): \(localProgress.positionSeconds)s")
                return UserProgress(
                    positionSeconds: localProgress.positionSeconds,
                    completed: localProgress.completed,
                    lastPlayed: localProgress.lastPlayed
                )
            }
            // No local progress, return zero
            return UserProgress(positionSeconds: 0, completed: false, lastPlayed: nil)
        }

        // Online: fetch from server and merge with local
        isLoading = true
        defer { isLoading = false }

        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        DebugLogger.database("Fetching progress for book: \(bookId)")

        let response = try await apiClient.fetchProgress(bookId: uuid)
        let serverProgress = UserProgress(
            positionSeconds: response.positionSeconds,
            completed: response.completed,
            lastPlayed: response.lastPlayed
        )

        // Check if local progress is newer
        if let localProgress = offlineProgressStore.getProgress(bookId: bookId) {
            if let serverLastPlayed = serverProgress.lastPlayed,
               localProgress.lastPlayed > serverLastPlayed {
                // Local is newer, return local and it will sync later
                DebugLogger
                    .database(
                        "Using local progress (newer): \(localProgress.positionSeconds)s vs server: \(serverProgress.positionSeconds)s"
                    )
                return UserProgress(
                    positionSeconds: localProgress.positionSeconds,
                    completed: localProgress.completed,
                    lastPlayed: localProgress.lastPlayed
                )
            }
        }

        // Server is newer or no local, update local cache from server
        if let lastPlayed = serverProgress.lastPlayed {
            offlineProgressStore.updateFromServer(
                bookId: bookId,
                position: serverProgress.positionSeconds,
                completed: serverProgress.completed,
                lastPlayed: lastPlayed
            )
        }

        DebugLogger.database("Fetched progress: \(response.positionSeconds)s, completed: \(response.completed)")

        return serverProgress
    }

    /// Save user's current playback position
    /// Local-first: Always saves locally, then syncs to server if online
    /// - Parameters:
    ///   - bookId: The book's UUID string
    ///   - positionSeconds: Current playback position in seconds
    ///   - timestamp: Optional timestamp for conflict resolution (not currently used by APIClient)
    /// - Returns: SaveProgressResponse with updated status
    @discardableResult
    @MainActor
    func saveProgress(
        for bookId: String,
        positionSeconds: Double,
        timestamp _: Date? = nil
    ) async throws -> SaveProgressResponse {
        // Always save locally first (local-first approach)
        offlineProgressStore.saveProgress(bookId: bookId, position: positionSeconds, completed: false)

        // If offline, return a synthetic response
        if !networkMonitor.isConnected {
            DebugLogger.database("Progress saved locally (offline): \(positionSeconds)s")
            let formatter = ISO8601DateFormatter()
            return SaveProgressResponse(
                positionSeconds: positionSeconds,
                completed: false,
                lastPlayed: formatter.string(from: Date()),
                updated: true
            )
        }

        // Online: sync to server
        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        DebugLogger.database("Saving progress to server: \(positionSeconds)s for book: \(bookId)")

        do {
            let response = try await apiClient.updateProgress(bookId: uuid, positionSeconds: positionSeconds)

            // Mark as synced since server accepted it
            offlineProgressStore.markSynced(bookId: bookId)

            if response.updated {
                DebugLogger.success("Progress saved and synced successfully")
            } else {
                DebugLogger.warning("Progress not updated (conflict detected)")
            }

            // Convert API response to SaveProgressResponse
            let formatter = ISO8601DateFormatter()
            let lastPlayedString = formatter.string(from: response.lastPlayed)

            return SaveProgressResponse(
                positionSeconds: response.positionSeconds,
                completed: response.completed,
                lastPlayed: lastPlayedString,
                updated: response.updated
            )
        } catch {
            // Server sync failed, but local save succeeded
            DebugLogger.error("Progress sync failed, will retry later", error: error)

            // Return local progress as the response
            let formatter = ISO8601DateFormatter()
            return SaveProgressResponse(
                positionSeconds: positionSeconds,
                completed: false,
                lastPlayed: formatter.string(from: Date()),
                updated: true
            )
        }
    }

    /// Mark a book as completed
    /// - Parameter bookId: The book's UUID string
    @MainActor
    func markCompleted(bookId: String) async throws {
        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        DebugLogger.database("Marking book as completed: \(bookId)")

        _ = try await apiClient.setProgressStatus(bookId: uuid, status: .completed)
    }

    /// Reset a book's progress (mark as not started)
    /// - Parameter bookId: The book's UUID string
    @MainActor
    func resetProgress(bookId: String) async throws {
        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        DebugLogger.database("Resetting progress for book: \(bookId)")

        _ = try await apiClient.setProgressStatus(bookId: uuid, status: .notStarted)
    }
}
