//
//  StorageManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 7: Offline Downloads
//

import Foundation

/// Metadata for a single downloaded book
struct DownloadedBook: Codable, Identifiable {
    let id: String  // bookId
    let title: String
    let author: String
    let downloadedAt: Date
    let fileSize: Int64
    let audioPath: String
    let coverPath: String?
    let fileExtension: String  // e.g., "mp3" or "m4a"

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    // Custom decoder to handle existing metadata without fileExtension
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        audioPath = try container.decode(String.self, forKey: .audioPath)
        coverPath = try container.decodeIfPresent(String.self, forKey: .coverPath)
        // Default to mp3 for backwards compatibility with existing downloads
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension) ?? "mp3"
    }

    init(id: String, title: String, author: String, downloadedAt: Date, fileSize: Int64, audioPath: String, coverPath: String?, fileExtension: String) {
        self.id = id
        self.title = title
        self.author = author
        self.downloadedAt = downloadedAt
        self.fileSize = fileSize
        self.audioPath = audioPath
        self.coverPath = coverPath
        self.fileExtension = fileExtension
    }
}

/// Root metadata structure stored on disk
struct DownloadMetadata: Codable {
    var version: Int = 1
    var downloads: [DownloadedBook]
    var totalSize: Int64

    init() {
        self.downloads = []
        self.totalSize = 0
    }
}

/// Manages local storage for downloaded audiobooks
/// Handles file operations, metadata index, and storage limits
@MainActor
class StorageManager: ObservableObject {
    static let shared = StorageManager()

    // MARK: - Published Properties

    @Published var downloads: [DownloadedBook] = []
    @Published var totalSize: Int64 = 0
    @Published var isLoading = false

    // MARK: - Constants

    /// Default storage limit (5 GB)
    static let defaultStorageLimit: Int64 = 5_000_000_000

    /// Directory names
    private let downloadsDirectoryName = "downloads"
    private let audiobooksDirectoryName = "audiobooks"
    private let metadataFileName = "metadata.json"

    // MARK: - Computed Properties

    /// Root downloads directory
    private var downloadsDirectory: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(downloadsDirectoryName)
    }

    /// Audiobooks subdirectory
    private var audiobooksDirectory: URL {
        downloadsDirectory.appendingPathComponent(audiobooksDirectoryName)
    }

    /// Metadata file path
    private var metadataPath: URL {
        downloadsDirectory.appendingPathComponent(metadataFileName)
    }

    /// Current storage limit from UserDefaults
    var storageLimit: Int64 {
        let limit = UserDefaults.standard.integer(forKey: "downloadStorageLimit")
        return limit > 0 ? Int64(limit) : StorageManager.defaultStorageLimit
    }

    /// Available device storage
    var availableDeviceSpace: Int64 {
        do {
            let resourceValues = try URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            DebugLogger.error("Failed to get available space", error: error)
            return 0
        }
    }

    /// Remaining space within storage limit
    var remainingStorageLimit: Int64 {
        max(0, storageLimit - totalSize)
    }

    // MARK: - Initialization

    private init() {
        setupDirectories()
        loadMetadata()
    }

    // MARK: - Directory Setup

    private func setupDirectories() {
        let fileManager = FileManager.default

        do {
            // Create downloads directory if needed
            if !fileManager.fileExists(atPath: downloadsDirectory.path) {
                try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
                DebugLogger.storage("Created downloads directory")
            }

            // Create audiobooks subdirectory if needed
            if !fileManager.fileExists(atPath: audiobooksDirectory.path) {
                try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
                DebugLogger.storage("Created audiobooks directory")
            }
        } catch {
            DebugLogger.error("Failed to create directories", error: error)
        }
    }

    // MARK: - File Paths

    /// Normalize book ID to uppercase for consistent file naming
    /// iOS UUID.uuidString returns uppercase, so we normalize all IDs to match
    private func normalizeBookId(_ bookId: String) -> String {
        bookId.uppercased()
    }

    /// Get audio file path for a book
    /// Uses file extension from metadata if available, otherwise defaults to mp3
    func audioFilePath(for bookId: String) -> URL {
        let normalizedId = normalizeBookId(bookId)
        // Check if we have metadata with file extension
        if let downloadedBook = downloads.first(where: { $0.id == normalizedId }) {
            return audiobooksDirectory.appendingPathComponent("\(normalizedId).\(downloadedBook.fileExtension)")
        }
        // Fallback: try to find any file with this book ID
        let fileManager = FileManager.default
        for ext in ["mp3", "m4a", "m4b", "aac"] {
            let path = audiobooksDirectory.appendingPathComponent("\(normalizedId).\(ext)")
            if fileManager.fileExists(atPath: path.path) {
                return path
            }
        }
        // Default to mp3 if no file found
        return audiobooksDirectory.appendingPathComponent("\(normalizedId).mp3")
    }

    /// Get audio file path with specific extension (used during download)
    func audioFilePath(for bookId: String, extension fileExtension: String) -> URL {
        audiobooksDirectory.appendingPathComponent("\(normalizeBookId(bookId)).\(fileExtension)")
    }

    /// Get cover image path for a book
    func coverImagePath(for bookId: String) -> URL {
        audiobooksDirectory.appendingPathComponent("\(normalizeBookId(bookId)).jpg")
    }

    // MARK: - Storage Operations

    /// Save downloaded audio file
    /// - Parameters:
    ///   - tempLocation: Temporary file URL from URLSession download
    ///   - bookId: Book ID to save as
    /// - Returns: Final file URL
    func saveAudioFile(from tempLocation: URL, bookId: String) throws -> URL {
        let fileManager = FileManager.default
        let destinationPath = audioFilePath(for: bookId)

        // Ensure directory exists (defensive - may be called before init completes on main actor)
        if !fileManager.fileExists(atPath: audiobooksDirectory.path) {
            try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
            DebugLogger.storage("Created audiobooks directory (late initialization)")
        }

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationPath.path) {
            try fileManager.removeItem(at: destinationPath)
        }

        // Move temp file to permanent location
        try fileManager.moveItem(at: tempLocation, to: destinationPath)

        DebugLogger.storage("Saved audio file: \(destinationPath.lastPathComponent)")
        return destinationPath
    }

    /// Save cover image data
    func saveCoverImage(data: Data, bookId: String) throws {
        let path = coverImagePath(for: bookId)
        try data.write(to: path)
        DebugLogger.storage("Saved cover image: \(path.lastPathComponent)")
    }

    /// Check if a book is downloaded
    /// Uses metadata array (which triggers SwiftUI updates) with file system verification
    func isBookDownloaded(bookId: String) -> Bool {
        let normalizedId = normalizeBookId(bookId)

        // Check metadata first (this is what triggers SwiftUI updates)
        let inMetadata = downloads.contains { $0.id == normalizedId }

        // Verify file actually exists on disk
        let audioPath = audioFilePath(for: bookId)
        let existsOnDisk = FileManager.default.fileExists(atPath: audioPath.path)

        // Both must be true for a valid download
        let isDownloaded = inMetadata && existsOnDisk

        DebugLogger.storage("isBookDownloaded check: \(normalizedId) -> \(isDownloaded) (metadata: \(inMetadata), disk: \(existsOnDisk))")
        return isDownloaded
    }

    /// Get file size of downloaded audio
    func downloadedFileSize(for bookId: String) -> Int64? {
        return downloadedFileSize(for: bookId, extension: nil)
    }

    /// Get file size of downloaded audio with explicit extension
    func downloadedFileSize(for bookId: String, extension fileExtension: String?) -> Int64? {
        let audioPath: URL
        if let ext = fileExtension {
            audioPath = audioFilePath(for: bookId, extension: ext)
        } else {
            audioPath = audioFilePath(for: bookId)
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioPath.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    /// Delete a downloaded book
    func deleteDownload(bookId: String) throws {
        let fileManager = FileManager.default

        // Delete audio file
        let audioPath = audioFilePath(for: bookId)
        if fileManager.fileExists(atPath: audioPath.path) {
            try fileManager.removeItem(at: audioPath)
            DebugLogger.storage("Deleted audio file: \(audioPath.lastPathComponent)")
        }

        // Delete cover image
        let coverPath = coverImagePath(for: bookId)
        if fileManager.fileExists(atPath: coverPath.path) {
            try fileManager.removeItem(at: coverPath)
            DebugLogger.storage("Deleted cover image: \(coverPath.lastPathComponent)")
        }

        // Update metadata
        removeFromMetadata(bookId: bookId)
    }

    /// Delete all downloads
    func deleteAllDownloads() throws {
        let fileManager = FileManager.default

        // Remove entire audiobooks directory
        if fileManager.fileExists(atPath: audiobooksDirectory.path) {
            try fileManager.removeItem(at: audiobooksDirectory)
            // Recreate empty directory
            try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
        }

        // Clear metadata
        downloads = []
        totalSize = 0
        saveMetadata()

        DebugLogger.storage("Deleted all downloads")
    }

    // MARK: - Metadata Management

    /// Load metadata from disk
    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataPath.path) else {
            DebugLogger.storage("No metadata file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: metadataPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(DownloadMetadata.self, from: data)

            downloads = metadata.downloads
            totalSize = metadata.totalSize

            DebugLogger.storage("Loaded metadata: \(downloads.count) downloads, \(StorageManager.formatFileSize(totalSize))")
        } catch {
            DebugLogger.error("Failed to load metadata", error: error)
        }
    }

    /// Save metadata to disk
    private func saveMetadata() {
        var metadata = DownloadMetadata()
        metadata.downloads = downloads
        metadata.totalSize = totalSize

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try data.write(to: metadataPath)

            DebugLogger.storage("Saved metadata: \(downloads.count) downloads")
        } catch {
            DebugLogger.error("Failed to save metadata", error: error)
        }
    }

    /// Add a download to metadata
    func addToMetadata(book: Book, fileSize: Int64, fileExtension: String = "mp3") {
        let normalizedId = normalizeBookId(book.id.uuidString)
        let downloadedBook = DownloadedBook(
            id: normalizedId,
            title: book.title,
            author: book.authors.first?.name ?? "Unknown Author",
            downloadedAt: Date(),
            fileSize: fileSize,
            audioPath: "audiobooks/\(normalizedId).\(fileExtension)",
            coverPath: "audiobooks/\(normalizedId).jpg",
            fileExtension: fileExtension
        )

        // Remove existing entry if present (re-download)
        downloads.removeAll { $0.id == normalizedId }

        downloads.append(downloadedBook)
        totalSize = downloads.reduce(0) { $0 + $1.fileSize }

        saveMetadata()
        DebugLogger.storage("Added to metadata: \(book.title) (\(StorageManager.formatFileSize(fileSize)), \(fileExtension))")
    }

    /// Remove a download from metadata
    private func removeFromMetadata(bookId: String) {
        let normalizedId = normalizeBookId(bookId)
        downloads.removeAll { $0.id == normalizedId }
        totalSize = downloads.reduce(0) { $0 + $1.fileSize }
        saveMetadata()
    }

    /// Get downloaded book metadata
    func getDownloadedBook(bookId: String) -> DownloadedBook? {
        let normalizedId = normalizeBookId(bookId)
        return downloads.first { $0.id == normalizedId }
    }

    // MARK: - Storage Limit Checks

    /// Check if we can download a file of given size
    func canDownload(fileSize: Int64) -> Bool {
        // Check against storage limit
        if totalSize + fileSize > storageLimit {
            return false
        }

        // Check against available device space (with 500MB buffer)
        let minBuffer: Int64 = 500_000_000
        if fileSize > availableDeviceSpace - minBuffer {
            return false
        }

        return true
    }

    /// Check storage usage percentage
    var storageUsagePercentage: Double {
        guard storageLimit > 0 else { return 0 }
        return Double(totalSize) / Double(storageLimit)
    }

    /// Check if storage is near limit (>90%)
    var isNearStorageLimit: Bool {
        storageUsagePercentage > 0.9
    }

    // MARK: - Utility

    /// Format file size for display
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Verify download integrity (file exists and size matches)
    func verifyDownload(bookId: String) -> Bool {
        guard let downloadedBook = getDownloadedBook(bookId: bookId) else {
            return false
        }

        guard let actualSize = downloadedFileSize(for: bookId) else {
            return false
        }

        // Allow 1% variance for file system differences
        let tolerance: Int64 = max(1024, downloadedBook.fileSize / 100)
        return abs(actualSize - downloadedBook.fileSize) <= tolerance
    }

    /// Clean up orphaned files (files without metadata entries)
    func cleanupOrphanedFiles() {
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: audiobooksDirectory, includingPropertiesForKeys: nil)

            for file in files {
                let filename = file.deletingPathExtension().lastPathComponent

                // Check if this file has a metadata entry
                if !downloads.contains(where: { $0.id == filename }) {
                    try fileManager.removeItem(at: file)
                    DebugLogger.storage("Cleaned up orphaned file: \(file.lastPathComponent)")
                }
            }
        } catch {
            DebugLogger.error("Failed to cleanup orphaned files", error: error)
        }
    }
}

// MARK: - DebugLogger Extension for Storage

extension DebugLogger {
    static func storage(_ message: String) {
        log(message, category: .database)  // Use database category for storage operations
    }
}
