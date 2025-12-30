//
//  MockProgressManager.swift
//  BookVaultTests
//
//  Mock ProgressManager for testing - allows configuring responses and tracking calls.
//

import Foundation
@testable import BookVault

/// Mock progress manager for testing
@MainActor
class MockProgressManager: ProgressManaging {
    // MARK: - Published Properties (for protocol conformance)

    var isLoading: Bool = false
    var error: Error?

    // MARK: - Call Tracking

    var fetchProgressCalls: [String] = []
    var saveProgressCalls: [(bookId: String, positionSeconds: Double, timestamp: Date?)] = []
    var markCompletedCalls: [String] = []
    var resetProgressCalls: [String] = []

    // MARK: - Configurable Results

    var fetchProgressResult: Result<UserProgress, Error> = .success(UserProgress(positionSeconds: 0, completed: false, lastPlayed: nil))
    var saveProgressResult: Result<SaveProgressResponse, Error> = .success(SaveProgressResponse(positionSeconds: 0, completed: false, lastPlayed: nil, updated: true))
    var markCompletedShouldFail: Bool = false
    var resetProgressShouldFail: Bool = false

    // MARK: - Cached Progress (for getCachedProgress scenarios)

    var cachedProgress: [String: UserProgress] = [:]

    // MARK: - Protocol Implementation

    func fetchProgress(for bookId: String) async throws -> UserProgress {
        fetchProgressCalls.append(bookId)
        return try fetchProgressResult.get()
    }

    func saveProgress(for bookId: String, positionSeconds: Double, timestamp: Date?) async throws -> SaveProgressResponse {
        saveProgressCalls.append((bookId, positionSeconds, timestamp))
        return try saveProgressResult.get()
    }

    func markCompleted(bookId: String) async throws {
        markCompletedCalls.append(bookId)
        if markCompletedShouldFail {
            throw NSError(domain: "MockProgressManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
    }

    func resetProgress(bookId: String) async throws {
        resetProgressCalls.append(bookId)
        if resetProgressShouldFail {
            throw NSError(domain: "MockProgressManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
    }

    // MARK: - Reset

    func reset() {
        fetchProgressCalls = []
        saveProgressCalls = []
        markCompletedCalls = []
        resetProgressCalls = []
        cachedProgress = [:]
        isLoading = false
        error = nil
        fetchProgressResult = .success(UserProgress(positionSeconds: 0, completed: false, lastPlayed: nil))
        saveProgressResult = .success(SaveProgressResponse(positionSeconds: 0, completed: false, lastPlayed: nil, updated: true))
        markCompletedShouldFail = false
        resetProgressShouldFail = false
    }
}
