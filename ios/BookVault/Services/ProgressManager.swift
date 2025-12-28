//
//  ProgressManager.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 4: Progress Sync
//

import Foundation

/// Manages user progress sync with backend API
@MainActor
class ProgressManager: ObservableObject {
    static let shared = ProgressManager()

    @Published var isLoading = false
    @Published var error: Error?

    private let apiClient = APIClient.shared

    private init() {}

    /// Fetch user's progress for a book
    /// - Parameter bookId: The book's UUID
    /// - Returns: UserProgress with position and completion status
    func fetchProgress(for bookId: String) async throws -> UserProgress {
        isLoading = true
        defer { isLoading = false }

        guard let token = AuthManager.shared.token else {
            throw NSError(domain: "ProgressManager", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }

        guard let url = URL(string: "\(APIClient.baseURL)/api/progress?bookId=\(bookId)") else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        #if DEBUG
        print("🔄 Fetching progress for book: \(bookId)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ProgressManager", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response"
            ])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "ProgressManager", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Failed to fetch progress: HTTP \(httpResponse.statusCode)"
            ])
        }

        let decoder = JSONDecoder()
        let progress = try decoder.decode(UserProgress.self, from: data)

        #if DEBUG
        print("✅ Fetched progress: \(progress.positionSeconds)s, completed: \(progress.completed)")
        #endif

        return progress
    }

    /// Save user's current playback position
    /// - Parameters:
    ///   - bookId: The book's UUID
    ///   - positionSeconds: Current playback position in seconds
    ///   - timestamp: Optional timestamp for conflict resolution
    /// - Returns: SaveProgressResponse with updated status
    @discardableResult
    func saveProgress(
        for bookId: String,
        positionSeconds: Double,
        timestamp: Date? = nil
    ) async throws -> SaveProgressResponse {
        guard let token = AuthManager.shared.token else {
            throw NSError(domain: "ProgressManager", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }

        guard let url = URL(string: "\(APIClient.baseURL)/api/progress") else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])
        }

        let requestBody = SaveProgressRequest(
            bookId: bookId,
            positionSeconds: positionSeconds,
            timestamp: timestamp ?? Date()
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        #if DEBUG
        print("💾 Saving progress: \(positionSeconds)s for book: \(bookId)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ProgressManager", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response"
            ])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "ProgressManager", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Failed to save progress: HTTP \(httpResponse.statusCode)"
            ])
        }

        let decoder = JSONDecoder()
        let progressResponse = try decoder.decode(SaveProgressResponse.self, from: data)

        #if DEBUG
        if progressResponse.updated {
            print("✅ Progress saved successfully")
        } else {
            print("⚠️ Progress not updated (conflict detected)")
        }
        #endif

        return progressResponse
    }

    /// Mark a book as completed
    /// - Parameter bookId: The book's UUID
    func markCompleted(bookId: String) async throws {
        guard let token = AuthManager.shared.token else {
            throw NSError(domain: "ProgressManager", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }

        guard let url = URL(string: "\(APIClient.baseURL)/api/progress") else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])
        }

        let requestBody = ["bookId": bookId, "status": "completed"]

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        #if DEBUG
        print("✅ Marking book as completed: \(bookId)")
        #endif

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ProgressManager", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response"
            ])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "ProgressManager", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Failed to mark as completed: HTTP \(httpResponse.statusCode)"
            ])
        }
    }

    /// Reset a book's progress (mark as not started)
    /// - Parameter bookId: The book's UUID
    func resetProgress(bookId: String) async throws {
        guard let token = AuthManager.shared.token else {
            throw NSError(domain: "ProgressManager", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }

        guard let url = URL(string: "\(APIClient.baseURL)/api/progress") else {
            throw NSError(domain: "ProgressManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])
        }

        let requestBody = ["bookId": bookId, "status": "not-started"]

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        #if DEBUG
        print("🔄 Resetting progress for book: \(bookId)")
        #endif

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ProgressManager", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response"
            ])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "ProgressManager", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Failed to reset progress: HTTP \(httpResponse.statusCode)"
            ])
        }
    }
}
