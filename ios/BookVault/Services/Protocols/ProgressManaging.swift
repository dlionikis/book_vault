//
//  ProgressManaging.swift
//  BookVault
//
//  Protocol for ProgressManager to enable testing with dependency injection.
//

import Foundation

// MARK: - ProgressManaging

// Note: UserProgress and SaveProgressResponse are defined in BookVault/Models/UserProgress.swift

/// Protocol for ProgressManager to enable testing
@MainActor
protocol ProgressManaging {
    var isLoading: Bool { get }
    var error: Error? { get }

    /// Fetch user's progress for a book
    /// - Parameter bookId: The book's UUID string
    /// - Returns: UserProgress with position and completion status
    func fetchProgress(for bookId: String) async throws -> UserProgress

    /// Save user's current playback position
    /// - Parameters:
    ///   - bookId: The book's UUID string
    ///   - positionSeconds: Current playback position in seconds
    ///   - timestamp: Optional timestamp for conflict resolution
    /// - Returns: SaveProgressResponse with updated status
    @discardableResult
    func saveProgress(for bookId: String, positionSeconds: Double, timestamp: Date?) async throws
        -> SaveProgressResponse

    /// Mark a book as completed
    /// - Parameter bookId: The book's UUID string
    func markCompleted(bookId: String) async throws

    /// Reset a book's progress (mark as not started)
    /// - Parameter bookId: The book's UUID string
    func resetProgress(bookId: String) async throws

    /// Clear all cached progress (call on logout)
    func clearCache()
}

// Default parameter extension
extension ProgressManaging {
    @discardableResult
    func saveProgress(for bookId: String, positionSeconds: Double) async throws -> SaveProgressResponse {
        try await saveProgress(for: bookId, positionSeconds: positionSeconds, timestamp: nil)
    }
}
