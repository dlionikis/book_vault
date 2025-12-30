//
//  DownloadManaging.swift
//  BookVault
//
//  Protocol for DownloadManager to enable testing.
//  Phase 4: Download Tests
//

import Foundation

/// Protocol for DownloadManager to enable testing with mocks
@MainActor
protocol DownloadManaging: ObservableObject {
    // MARK: - Published Properties (read-only in protocol)

    /// Active downloads indexed by book ID
    var activeDownloads: [String: ActiveDownload] { get }

    /// Current error if any
    var error: DownloadError? { get }

    // MARK: - State Queries

    /// Get download state for a book
    func downloadState(for bookId: String) -> DownloadState

    /// Check if a book is currently downloading
    func isDownloading(bookId: String) -> Bool

    // MARK: - Download Operations

    /// Start downloading a book
    func startDownload(book: Book) async throws

    /// Cancel a download
    func cancelDownload(bookId: String)

    /// Pause a download
    func pauseDownload(bookId: String)

    /// Resume a paused download
    func resumeDownload(book: Book) async throws

    /// Delete a downloaded book
    func deleteDownload(bookId: String) throws
}
