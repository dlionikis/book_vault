//
//  ProgressManager.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 4: Progress Sync
//

import Foundation
import Combine

/// Manages user progress sync with backend API
/// This is a lightweight wrapper around APIClient for progress-related operations
class ProgressManager: ObservableObject {
    static let shared = ProgressManager()

    @MainActor @Published var isLoading = false
    @MainActor @Published var error: Error?

    private let apiClient = APIClient.shared

    private init() {}

    /// Fetch user's progress for a book
    /// - Parameter bookId: The book's UUID string
    /// - Returns: UserProgress with position and completion status
    @MainActor
    func fetchProgress(for bookId: String) async throws -> UserProgress {
        isLoading = true
        defer { isLoading = false }

        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        DebugLogger.database("Fetching progress for book: \(bookId)")

        let response = try await apiClient.fetchProgress(bookId: uuid)

        DebugLogger.database("Fetched progress: \(response.positionSeconds)s, completed: \(response.completed)")

        // Convert API response to UserProgress
        return UserProgress(
            positionSeconds: response.positionSeconds,
            completed: response.completed,
            lastPlayed: response.lastPlayed
        )
    }

    /// Save user's current playback position
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
        timestamp: Date? = nil
    ) async throws -> SaveProgressResponse {
        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        DebugLogger.database("Saving progress: \(positionSeconds)s for book: \(bookId)")

        let response = try await apiClient.updateProgress(bookId: uuid, positionSeconds: positionSeconds)

        if response.updated {
            DebugLogger.success("Progress saved successfully")
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
