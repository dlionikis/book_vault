//
//  MockStorageManager.swift
//  BookVaultTests
//
//  Mock StorageManager for testing - simulates storage operations.
//

import Foundation
@testable import BookVault

/// Mock storage manager for testing
@MainActor
class MockStorageManager: ObservableObject, StorageManaging {
    // MARK: - Published Properties

    @Published var downloads: [DownloadedBook] = []
    @Published var totalSize: Int64 = 0
    @Published var isLoading: Bool = false

    // MARK: - Configurable Properties

    var configurableStorageLimit: Int64 = 5_000_000_000 // 5 GB default
    var configurableAvailableSpace: Int64 = 10_000_000_000 // 10 GB default

    var storageLimit: Int64 { configurableStorageLimit }
    var availableDeviceSpace: Int64 { configurableAvailableSpace }

    var remainingStorageLimit: Int64 {
        max(0, storageLimit - totalSize)
    }

    var storageUsagePercentage: Double {
        guard storageLimit > 0 else { return 0 }
        return Double(totalSize) / Double(storageLimit)
    }

    var isNearStorageLimit: Bool {
        storageUsagePercentage > 0.9
    }

    // MARK: - Call Tracking

    var saveAudioFileCalls: [(tempLocation: URL, bookId: String)] = []
    var saveCoverImageCalls: [(dataSize: Int, bookId: String)] = []
    var deleteDownloadCalls: [String] = []
    var deleteAllDownloadsCalled: Bool = false
    var cleanupOrphanedFilesCalled: Bool = false

    // MARK: - Error Simulation

    var saveShouldFail: Bool = false
    var deleteShouldFail: Bool = false

    // MARK: - In-Memory Storage

    var downloadedBooks = Set<String>()
    var savedFiles = [String: Data]()
    var metadata = [String: DownloadedBook]()

    // MARK: - Protocol Implementation

    func audioFilePath(for bookId: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId.uppercased()).mp3")
    }

    func audioFilePath(for bookId: String, extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId.uppercased()).\(fileExtension)")
    }

    func coverImagePath(for bookId: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId.uppercased()).jpg")
    }

    func saveAudioFile(from tempLocation: URL, bookId: String) throws -> URL {
        saveAudioFileCalls.append((tempLocation, bookId))
        if saveShouldFail {
            throw NSError(domain: "MockStorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage full"])
        }
        let normalizedId = bookId.uppercased()
        downloadedBooks.insert(normalizedId)
        return audioFilePath(for: bookId)
    }

    func saveCoverImage(data: Data, bookId: String) throws {
        saveCoverImageCalls.append((data.count, bookId))
        if saveShouldFail {
            throw NSError(domain: "MockStorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage full"])
        }
    }

    func isBookDownloaded(bookId: String) -> Bool {
        downloadedBooks.contains(bookId.uppercased())
    }

    func downloadedFileSize(for bookId: String) -> Int64? {
        if let downloadedBook = metadata[bookId.uppercased()] {
            return downloadedBook.fileSize
        }
        return nil
    }

    func downloadedFileSize(for bookId: String, extension _: String?) -> Int64? {
        if let downloadedBook = metadata[bookId.uppercased()] {
            return downloadedBook.fileSize
        }
        return nil
    }

    func deleteDownload(bookId: String) throws {
        deleteDownloadCalls.append(bookId)
        if deleteShouldFail {
            throw NSError(
                domain: "MockStorageManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Delete failed"]
            )
        }
        let normalizedId = bookId.uppercased()
        downloadedBooks.remove(normalizedId)
        metadata.removeValue(forKey: normalizedId)
        downloads.removeAll { $0.id == normalizedId }
        totalSize = downloads.reduce(0) { $0 + $1.fileSize }
    }

    func deleteAllDownloads() throws {
        deleteAllDownloadsCalled = true
        if deleteShouldFail {
            throw NSError(
                domain: "MockStorageManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Delete failed"]
            )
        }
        downloadedBooks = Set<String>()
        metadata = [String: DownloadedBook]()
        downloads = []
        totalSize = 0
    }

    func addToMetadata(book: Book, fileSize: Int64, fileExtension: String = "mp3") {
        let normalizedId = book.id.uuidString.uppercased()
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
        metadata[normalizedId] = downloadedBook
        downloads.removeAll { $0.id == normalizedId }
        downloads.append(downloadedBook)
        downloadedBooks.insert(normalizedId)
        totalSize = downloads.reduce(0) { $0 + $1.fileSize }
    }

    func getDownloadedBook(bookId: String) -> DownloadedBook? {
        metadata[bookId.uppercased()]
    }

    func canDownload(fileSize: Int64) -> Bool {
        // Check against storage limit
        if totalSize + fileSize > storageLimit {
            return false
        }
        // Check against available device space (with buffer)
        let minBuffer: Int64 = 500_000_000
        if fileSize > availableDeviceSpace - minBuffer {
            return false
        }
        return true
    }

    func verifyDownload(bookId: String) -> Bool {
        // In mock, just check if it's in our downloaded set
        downloadedBooks.contains(bookId.uppercased())
    }

    func cleanupOrphanedFiles() {
        cleanupOrphanedFilesCalled = true
    }

    // MARK: - Reset

    func reset() {
        downloads = []
        totalSize = 0
        isLoading = false
        downloadedBooks = Set<String>()
        savedFiles = [String: Data]()
        metadata = [String: DownloadedBook]()
        saveAudioFileCalls = []
        saveCoverImageCalls = []
        deleteDownloadCalls = []
        deleteAllDownloadsCalled = false
        cleanupOrphanedFilesCalled = false
        saveShouldFail = false
        deleteShouldFail = false
        configurableStorageLimit = 5_000_000_000
        configurableAvailableSpace = 10_000_000_000
    }
}
