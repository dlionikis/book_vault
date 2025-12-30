//
//  StorageManaging.swift
//  BookVault
//
//  Protocol for StorageManager to enable testing with dependency injection.
//

import Foundation

/// Protocol for StorageManager to enable testing
@MainActor
protocol StorageManaging: ObservableObject {
    /// List of downloaded books
    var downloads: [DownloadedBook] { get }

    /// Total size of all downloads in bytes
    var totalSize: Int64 { get }

    /// Whether storage operations are in progress
    var isLoading: Bool { get }

    /// Current storage limit in bytes
    var storageLimit: Int64 { get }

    /// Available device storage in bytes
    var availableDeviceSpace: Int64 { get }

    /// Remaining space within storage limit
    var remainingStorageLimit: Int64 { get }

    /// Storage usage as percentage (0.0 to 1.0)
    var storageUsagePercentage: Double { get }

    /// Whether storage is near limit (>90%)
    var isNearStorageLimit: Bool { get }

    // MARK: - File Path Methods

    /// Get audio file path for a book
    func audioFilePath(for bookId: String) -> URL

    /// Get audio file path with specific extension (used during download)
    func audioFilePath(for bookId: String, extension fileExtension: String) -> URL

    /// Get cover image path for a book
    func coverImagePath(for bookId: String) -> URL

    // MARK: - Storage Operations

    /// Save downloaded audio file
    /// - Parameters:
    ///   - tempLocation: Temporary file URL from URLSession download
    ///   - bookId: Book ID to save as
    /// - Returns: Final file URL
    func saveAudioFile(from tempLocation: URL, bookId: String) throws -> URL

    /// Save cover image data
    func saveCoverImage(data: Data, bookId: String) throws

    /// Check if a book is downloaded
    func isBookDownloaded(bookId: String) -> Bool

    /// Get file size of downloaded audio
    func downloadedFileSize(for bookId: String) -> Int64?

    /// Delete a downloaded book
    func deleteDownload(bookId: String) throws

    /// Delete all downloads
    func deleteAllDownloads() throws

    // MARK: - Metadata Management

    /// Add a download to metadata
    func addToMetadata(book: Book, fileSize: Int64, fileExtension: String)

    /// Get downloaded book metadata
    func getDownloadedBook(bookId: String) -> DownloadedBook?

    // MARK: - Storage Limit Checks

    /// Check if we can download a file of given size
    func canDownload(fileSize: Int64) -> Bool

    /// Verify download integrity (file exists and size matches)
    func verifyDownload(bookId: String) -> Bool

    /// Clean up orphaned files (files without metadata entries)
    func cleanupOrphanedFiles()
}
