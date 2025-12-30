//
//  MockDownloadManager.swift
//  BookVaultTests
//
//  Mock DownloadManager for testing - simulates download operations.
//  Phase 4: Download Tests
//

import Foundation
import Combine
@testable import BookVault

/// Mock download manager for testing
@MainActor
class MockDownloadManager: ObservableObject, DownloadManaging {
    // MARK: - Published Properties

    @Published var activeDownloads: [String: ActiveDownload] = [:]
    @Published var error: DownloadError?

    // MARK: - Call Tracking

    var startDownloadCalls: [BookVault.Book] = []
    var cancelDownloadCalls: [String] = []
    var pauseDownloadCalls: [String] = []
    var resumeDownloadCalls: [BookVault.Book] = []
    var deleteDownloadCalls: [String] = []
    var downloadStateCalls: [String] = []

    // MARK: - Configurable Behavior

    var startShouldFail: Bool = false
    var startErrorToThrow: DownloadError = .networkError("Test error")
    var resumeShouldFail: Bool = false
    var resumeErrorToThrow: DownloadError = .networkError("Test error")
    var deleteShouldFail: Bool = false

    // MARK: - In-Memory State

    var completedDownloads: Set<String> = []

    // MARK: - Protocol Implementation

    func downloadState(for bookId: String) -> DownloadState {
        downloadStateCalls.append(bookId)

        // Check if actively downloading
        if let active = activeDownloads[bookId] {
            return active.state
        }

        // Check if completed
        if completedDownloads.contains(bookId) {
            return .completed
        }

        return .notDownloaded
    }

    func isDownloading(bookId: String) -> Bool {
        guard let active = activeDownloads[bookId] else { return false }
        switch active.state {
        case .waiting, .downloading:
            return true
        default:
            return false
        }
    }

    func startDownload(book: BookVault.Book) async throws {
        startDownloadCalls.append(book)

        if startShouldFail {
            error = startErrorToThrow
            throw startErrorToThrow
        }

        let bookId = book.id.uuidString

        // Create initial download state
        let download = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 0,
            totalBytes: Int64((book.runtimeMinutes ?? 60) * 1_000_000), // ~1MB per minute
            state: .downloading(progress: 0),
            task: nil
        )
        activeDownloads[bookId] = download
    }

    func cancelDownload(bookId: String) {
        cancelDownloadCalls.append(bookId)
        activeDownloads.removeValue(forKey: bookId)
    }

    func pauseDownload(bookId: String) {
        pauseDownloadCalls.append(bookId)

        if let download = activeDownloads[bookId] {
            activeDownloads[bookId]?.state = .paused(progress: download.progress)
        }
    }

    func resumeDownload(book: BookVault.Book) async throws {
        resumeDownloadCalls.append(book)

        if resumeShouldFail {
            error = resumeErrorToThrow
            throw resumeErrorToThrow
        }

        let bookId = book.id.uuidString

        if let download = activeDownloads[bookId] {
            activeDownloads[bookId]?.state = .downloading(progress: download.progress)
        } else {
            // If not in active downloads, start fresh
            try await startDownload(book: book)
        }
    }

    func deleteDownload(bookId: String) throws {
        deleteDownloadCalls.append(bookId)

        if deleteShouldFail {
            throw NSError(domain: "MockDownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
        }

        activeDownloads.removeValue(forKey: bookId)
        completedDownloads.remove(bookId)
    }

    // MARK: - Simulation Helpers

    /// Simulate progress update for a download
    func simulateProgress(bookId: String, progress: Double) {
        guard var download = activeDownloads[bookId] else { return }

        download.bytesDownloaded = Int64(Double(download.totalBytes) * progress)
        download.state = .downloading(progress: progress)
        activeDownloads[bookId] = download
    }

    /// Simulate download completion
    func simulateCompletion(bookId: String) {
        guard var download = activeDownloads[bookId] else { return }

        download.bytesDownloaded = download.totalBytes
        download.state = .completed
        activeDownloads[bookId] = download
        completedDownloads.insert(bookId)

        // Remove from active downloads after short delay (simulating real behavior)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.activeDownloads.removeValue(forKey: bookId)
        }
    }

    /// Simulate download failure
    func simulateFailure(bookId: String, errorMessage: String) {
        guard activeDownloads[bookId] != nil else { return }

        activeDownloads[bookId]?.state = .failed(error: errorMessage)
    }

    /// Mark a book as already completed (for testing completed state queries)
    func markAsCompleted(bookId: String) {
        completedDownloads.insert(bookId)
        activeDownloads.removeValue(forKey: bookId)
    }

    // MARK: - Reset

    func reset() {
        activeDownloads = [:]
        error = nil
        completedDownloads = []

        startDownloadCalls = []
        cancelDownloadCalls = []
        pauseDownloadCalls = []
        resumeDownloadCalls = []
        deleteDownloadCalls = []
        downloadStateCalls = []

        startShouldFail = false
        resumeShouldFail = false
        deleteShouldFail = false
    }
}
