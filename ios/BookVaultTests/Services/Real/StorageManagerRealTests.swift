//
//  StorageManagerRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 2: Real Services Testing - StorageManager
//

import XCTest
@testable import BookVault

final class StorageManagerRealTests: XCTestCase {
    // MARK: - Properties

    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var storageManager: StorageManager!

    // MARK: - Test Helpers

    private func createTestBook(
        id: UUID = UUID(),
        title: String = "Test Book",
        authorName: String = "Test Author"
    ) -> Book {
        let author = Author(id: UUID(), name: authorName)
        return Book(id: id, asin: "TEST123", title: title, archiveStatus: .available, authors: [author])
    }

    private func createTempFile(withData data: Data, named filename: String) -> URL {
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try? data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Setup & Teardown

    // `@MainActor` because the type under test has a main-actor isolated
    // init. Legal on the async form of setUp, unlike the synchronous one.
    @MainActor
    override func setUp() async throws {
        // Create a unique temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageManagerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create isolated UserDefaults
        suiteName = "StorageManagerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        // Create storage manager with test directory
        storageManager = StorageManager(baseDirectory: tempDirectory, userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)

        // Clean up UserDefaults
        testDefaults?.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        storageManager = nil
        tempDirectory = nil
    }

    // MARK: - Initialization Tests

    @MainActor
    func testInitialization_CreatesDirectoryStructure() {
        // Given: A fresh storage manager
        // Then: Downloads directory should exist
        let downloadsDir = tempDirectory.appendingPathComponent("downloads")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadsDir.path))

        // And: Audiobooks subdirectory should exist
        let audiobooksDir = downloadsDir.appendingPathComponent("audiobooks")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audiobooksDir.path))
    }

    @MainActor
    func testInitialization_WithEmptyDirectory_HasNoDownloads() {
        // Given: A fresh storage manager
        // Then: Downloads list should be empty
        XCTAssertTrue(storageManager.downloads.isEmpty)
        XCTAssertEqual(storageManager.totalSize, 0)
    }

    // MARK: - File Path Tests

    @MainActor
    func testAudioFilePath_ReturnsCorrectPath() {
        // Given: A book ID
        let bookId = "ABC123"

        // When: Getting audio file path
        let path = storageManager.audioFilePath(for: bookId)

        // Then: Path is in audiobooks directory with normalized ID
        XCTAssertTrue(path.path.contains("audiobooks"))
        XCTAssertTrue(path.lastPathComponent.hasPrefix("ABC123"))
    }

    @MainActor
    func testAudioFilePath_NormalizesToUppercase() {
        // Given: A lowercase book ID
        let bookId = "abc123"

        // When: Getting audio file path
        let path = storageManager.audioFilePath(for: bookId)

        // Then: Filename uses uppercase
        XCTAssertTrue(path.lastPathComponent.hasPrefix("ABC123"))
    }

    @MainActor
    func testAudioFilePath_WithExtension_UsesProvidedExtension() {
        // Given: A book ID and extension
        let bookId = "ABC123"
        let ext = "m4a"

        // When: Getting audio file path with extension
        let path = storageManager.audioFilePath(for: bookId, extension: ext)

        // Then: Path uses provided extension
        XCTAssertEqual(path.pathExtension, "m4a")
        XCTAssertEqual(path.lastPathComponent, "ABC123.m4a")
    }

    @MainActor
    func testCoverImagePath_ReturnsJpgPath() {
        // Given: A book ID
        let bookId = "ABC123"

        // When: Getting cover image path
        let path = storageManager.coverImagePath(for: bookId)

        // Then: Path is jpg in audiobooks directory
        XCTAssertEqual(path.pathExtension, "jpg")
        XCTAssertTrue(path.path.contains("audiobooks"))
    }

    // MARK: - Save Audio File Tests

    @MainActor
    func testSaveAudioFile_MovesFileToDestination() throws {
        // Given: A temp audio file
        let audioData = Data("fake audio content".utf8)
        let tempFile = createTempFile(withData: audioData, named: "temp_audio.mp3")
        let bookId = "BOOK123"

        // When: Saving audio file
        let savedPath = try storageManager.saveAudioFile(from: tempFile, bookId: bookId)

        // Then: File exists at new location
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath.path))

        // And: Content is preserved
        let savedData = try Data(contentsOf: savedPath)
        XCTAssertEqual(savedData, audioData)

        // And: Original file is removed (moved, not copied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
    }

    @MainActor
    func testSaveAudioFile_OverwritesExistingFile() throws {
        // Given: An existing audio file
        let bookId = "BOOK123"
        let oldData = Data("old content".utf8)
        let oldFile = createTempFile(withData: oldData, named: "temp1.mp3")
        _ = try storageManager.saveAudioFile(from: oldFile, bookId: bookId)

        // When: Saving a new file with same book ID
        let newData = Data("new content".utf8)
        let newFile = createTempFile(withData: newData, named: "temp2.mp3")
        let savedPath = try storageManager.saveAudioFile(from: newFile, bookId: bookId)

        // Then: New content is saved
        let savedData = try Data(contentsOf: savedPath)
        XCTAssertEqual(savedData, newData)
    }

    // MARK: - Save Cover Image Tests

    @MainActor
    func testSaveCoverImage_WritesDataToFile() throws {
        // Given: Cover image data
        let imageData = Data("fake image data".utf8)
        let bookId = "BOOK123"

        // When: Saving cover image
        try storageManager.saveCoverImage(data: imageData, bookId: bookId)

        // Then: File exists at expected path
        let coverPath = storageManager.coverImagePath(for: bookId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverPath.path))

        // And: Content is correct
        let savedData = try Data(contentsOf: coverPath)
        XCTAssertEqual(savedData, imageData)
    }

    // MARK: - Metadata Tests

    @MainActor
    func testAddToMetadata_AddsBookToDownloads() {
        // Given: A book
        let book = createTestBook()
        let fileSize: Int64 = 1024 * 1024 // 1 MB

        // When: Adding to metadata
        storageManager.addToMetadata(book: book, fileSize: fileSize)

        // Then: Book appears in downloads
        XCTAssertEqual(storageManager.downloads.count, 1)
        XCTAssertEqual(storageManager.downloads.first?.title, book.title)
        XCTAssertEqual(storageManager.downloads.first?.fileSize, fileSize)
    }

    @MainActor
    func testAddToMetadata_UpdatesTotalSize() {
        // Given: A book
        let book = createTestBook()
        let fileSize: Int64 = 5_000_000

        // When: Adding to metadata
        storageManager.addToMetadata(book: book, fileSize: fileSize)

        // Then: Total size is updated
        XCTAssertEqual(storageManager.totalSize, fileSize)
    }

    @MainActor
    func testAddToMetadata_MultipleBooks_AccumulatesTotalSize() {
        // Given: Two books
        let book1 = createTestBook(title: "Book 1")
        let book2 = createTestBook(title: "Book 2")

        // When: Adding both books
        storageManager.addToMetadata(book: book1, fileSize: 1_000_000)
        storageManager.addToMetadata(book: book2, fileSize: 2_000_000)

        // Then: Total size is sum
        XCTAssertEqual(storageManager.downloads.count, 2)
        XCTAssertEqual(storageManager.totalSize, 3_000_000)
    }

    @MainActor
    func testAddToMetadata_RedownloadingSameBook_ReplacesEntry() {
        // Given: A book added to metadata
        let bookId = UUID()
        let book = createTestBook(id: bookId, title: "Original Title")
        storageManager.addToMetadata(book: book, fileSize: 1_000_000)

        // When: Adding same book again with different size
        let updatedBook = createTestBook(id: bookId, title: "Updated Title")
        storageManager.addToMetadata(book: updatedBook, fileSize: 2_000_000)

        // Then: Only one entry exists
        XCTAssertEqual(storageManager.downloads.count, 1)
        XCTAssertEqual(storageManager.totalSize, 2_000_000)
    }

    @MainActor
    func testAddToMetadata_WithFileExtension_StoresExtension() {
        // Given: A book with m4a extension
        let book = createTestBook()

        // When: Adding with specific extension
        storageManager.addToMetadata(book: book, fileSize: 1_000_000, fileExtension: "m4a")

        // Then: Extension is stored
        let downloadedBook = storageManager.downloads.first
        XCTAssertEqual(downloadedBook?.fileExtension, "m4a")
    }

    @MainActor
    func testGetDownloadedBook_ReturnsCorrectBook() {
        // Given: A book in metadata
        let bookId = UUID()
        let book = createTestBook(id: bookId, title: "Findable Book")
        storageManager.addToMetadata(book: book, fileSize: 1_000_000)

        // When: Getting by ID
        let found = storageManager.getDownloadedBook(bookId: bookId.uuidString)

        // Then: Correct book is returned
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Findable Book")
    }

    @MainActor
    func testGetDownloadedBook_WithMissingBook_ReturnsNil() {
        // Given: Empty storage
        // When: Getting non-existent book
        let found = storageManager.getDownloadedBook(bookId: UUID().uuidString)

        // Then: Returns nil
        XCTAssertNil(found)
    }

    // MARK: - Download Status Tests

    @MainActor
    func testIsBookDownloaded_WithoutMetadataOrFile_ReturnsFalse() {
        // Given: A book ID with no download
        let bookId = UUID().uuidString

        // When/Then: Book is not downloaded
        XCTAssertFalse(storageManager.isBookDownloaded(bookId: bookId))
    }

    @MainActor
    func testIsBookDownloaded_WithMetadataButNoFile_ReturnsFalse() {
        // Given: A book in metadata but no file
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 1_000_000)

        // When/Then: Book is not downloaded (file doesn't exist)
        XCTAssertFalse(storageManager.isBookDownloaded(bookId: book.id.uuidString))
    }

    @MainActor
    func testIsBookDownloaded_WithMetadataAndFile_ReturnsTrue() throws {
        // Given: A book with metadata and file
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 100)

        // Create the actual file
        let audioData = Data("audio".utf8)
        let tempFile = createTempFile(withData: audioData, named: "temp.mp3")
        _ = try storageManager.saveAudioFile(from: tempFile, bookId: book.id.uuidString)

        // When/Then: Book is downloaded
        XCTAssertTrue(storageManager.isBookDownloaded(bookId: book.id.uuidString))
    }

    // MARK: - Delete Tests

    @MainActor
    func testDeleteDownload_RemovesFilesAndMetadata() throws {
        // Given: A complete download
        let book = createTestBook()
        let audioData = Data("audio content".utf8)
        let imageData = Data("image content".utf8)

        let tempFile = createTempFile(withData: audioData, named: "temp.mp3")
        let audioPath = try storageManager.saveAudioFile(from: tempFile, bookId: book.id.uuidString)
        try storageManager.saveCoverImage(data: imageData, bookId: book.id.uuidString)
        storageManager.addToMetadata(book: book, fileSize: Int64(audioData.count))

        let coverPath = storageManager.coverImagePath(for: book.id.uuidString)

        // When: Deleting download
        try storageManager.deleteDownload(bookId: book.id.uuidString)

        // Then: Files are removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverPath.path))

        // And: Metadata is updated
        XCTAssertTrue(storageManager.downloads.isEmpty)
        XCTAssertEqual(storageManager.totalSize, 0)
    }

    @MainActor
    func testDeleteAllDownloads_ClearsEverything() throws {
        // Given: Multiple downloads
        for i in 1 ... 3 {
            let book = createTestBook(title: "Book \(i)")
            let audioData = Data("audio \(i)".utf8)
            let tempFile = createTempFile(withData: audioData, named: "temp\(i).mp3")
            _ = try storageManager.saveAudioFile(from: tempFile, bookId: book.id.uuidString)
            storageManager.addToMetadata(book: book, fileSize: Int64(audioData.count))
        }

        XCTAssertEqual(storageManager.downloads.count, 3)

        // When: Deleting all
        try storageManager.deleteAllDownloads()

        // Then: Everything is cleared
        XCTAssertTrue(storageManager.downloads.isEmpty)
        XCTAssertEqual(storageManager.totalSize, 0)
    }

    // MARK: - Storage Limit Tests

    @MainActor
    func testStorageLimit_DefaultsTo5GB() {
        // Given: No storage limit set in UserDefaults
        // Then: Default is 5 GB
        XCTAssertEqual(storageManager.storageLimit, 5_000_000_000)
    }

    @MainActor
    func testStorageLimit_ReadsFromUserDefaults() {
        // Given: Custom storage limit set
        testDefaults.set(10_000_000_000, forKey: "downloadStorageLimit")

        // Create new manager to pick up the setting
        let manager = StorageManager(baseDirectory: tempDirectory, userDefaults: testDefaults)

        // Then: Custom limit is used
        XCTAssertEqual(manager.storageLimit, 10_000_000_000)
    }

    @MainActor
    func testCanDownload_WithinLimit_ReturnsTrue() {
        // Given: Empty storage with default 5GB limit
        // When/Then: Can download 1GB file
        XCTAssertTrue(storageManager.canDownload(fileSize: 1_000_000_000))
    }

    @MainActor
    func testCanDownload_ExceedingLimit_ReturnsFalse() {
        // Given: Storage with 4GB used
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 4_000_000_000)

        // When/Then: Cannot download 2GB file (would exceed 5GB limit)
        XCTAssertFalse(storageManager.canDownload(fileSize: 2_000_000_000))
    }

    @MainActor
    func testStorageUsagePercentage_CalculatesCorrectly() {
        // Given: 2.5GB used of 5GB limit
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 2_500_000_000)

        // Then: Usage is 50%
        XCTAssertEqual(storageManager.storageUsagePercentage, 0.5, accuracy: 0.01)
    }

    @MainActor
    func testIsNearStorageLimit_Below90Percent_ReturnsFalse() {
        // Given: 80% usage
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 4_000_000_000) // 80% of 5GB

        // Then: Not near limit
        XCTAssertFalse(storageManager.isNearStorageLimit)
    }

    @MainActor
    func testIsNearStorageLimit_Above90Percent_ReturnsTrue() {
        // Given: 95% usage
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 4_750_000_000) // 95% of 5GB

        // Then: Near limit
        XCTAssertTrue(storageManager.isNearStorageLimit)
    }

    @MainActor
    func testRemainingStorageLimit_CalculatesCorrectly() {
        // Given: 3GB used
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 3_000_000_000)

        // Then: 2GB remaining
        XCTAssertEqual(storageManager.remainingStorageLimit, 2_000_000_000)
    }

    // MARK: - Metadata Persistence Tests

    @MainActor
    func testMetadata_PersistsAcrossInstances() {
        // Given: A book added to metadata
        let book = createTestBook(title: "Persistent Book")
        storageManager.addToMetadata(book: book, fileSize: 1_000_000)

        // When: Creating a new storage manager with same directory
        let newManager = StorageManager(baseDirectory: tempDirectory, userDefaults: testDefaults)

        // Then: Metadata is loaded
        XCTAssertEqual(newManager.downloads.count, 1)
        XCTAssertEqual(newManager.downloads.first?.title, "Persistent Book")
        XCTAssertEqual(newManager.totalSize, 1_000_000)
    }

    // MARK: - File Size Tests

    @MainActor
    func testDownloadedFileSize_ReturnsCorrectSize() throws {
        // Given: A saved audio file
        let book = createTestBook()
        let audioData = Data(repeating: 0, count: 1024) // 1KB
        let tempFile = createTempFile(withData: audioData, named: "temp.mp3")
        _ = try storageManager.saveAudioFile(from: tempFile, bookId: book.id.uuidString)
        storageManager.addToMetadata(book: book, fileSize: 1024)

        // When: Getting file size
        let size = storageManager.downloadedFileSize(for: book.id.uuidString)

        // Then: Size is correct
        XCTAssertEqual(size, 1024)
    }

    @MainActor
    func testDownloadedFileSize_ForNonExistentFile_ReturnsNil() {
        // Given: No file exists
        // When/Then: Size is nil
        XCTAssertNil(storageManager.downloadedFileSize(for: UUID().uuidString))
    }

    // MARK: - Verify Download Tests

    @MainActor
    func testVerifyDownload_WithValidDownload_ReturnsTrue() throws {
        // Given: A complete download with matching size
        let book = createTestBook()
        let audioData = Data(repeating: 0, count: 10000)
        let tempFile = createTempFile(withData: audioData, named: "temp.mp3")
        _ = try storageManager.saveAudioFile(from: tempFile, bookId: book.id.uuidString)
        storageManager.addToMetadata(book: book, fileSize: Int64(audioData.count))

        // When/Then: Download is verified
        XCTAssertTrue(storageManager.verifyDownload(bookId: book.id.uuidString))
    }

    @MainActor
    func testVerifyDownload_WithMissingMetadata_ReturnsFalse() {
        // Given: No metadata for book
        // When/Then: Verification fails
        XCTAssertFalse(storageManager.verifyDownload(bookId: UUID().uuidString))
    }

    @MainActor
    func testVerifyDownload_WithMissingFile_ReturnsFalse() {
        // Given: Metadata but no file
        let book = createTestBook()
        storageManager.addToMetadata(book: book, fileSize: 1000)

        // When/Then: Verification fails
        XCTAssertFalse(storageManager.verifyDownload(bookId: book.id.uuidString))
    }

    // MARK: - Cleanup Orphaned Files Tests

    @MainActor
    func testCleanupOrphanedFiles_RemovesFilesWithoutMetadata() throws {
        // Given: A file in audiobooks directory without metadata
        let audiobooksDir = tempDirectory
            .appendingPathComponent("downloads")
            .appendingPathComponent("audiobooks")
        let orphanedFile = audiobooksDir.appendingPathComponent("ORPHAN123.mp3")
        try Data("orphan".utf8).write(to: orphanedFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanedFile.path))

        // When: Cleaning up
        storageManager.cleanupOrphanedFiles()

        // Then: Orphaned file is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedFile.path))
    }

    @MainActor
    func testCleanupOrphanedFiles_KeepsFilesWithMetadata() throws {
        // Given: A file with matching metadata
        let book = createTestBook()
        let audioData = Data("audio".utf8)
        let tempFile = createTempFile(withData: audioData, named: "temp.mp3")
        let savedPath = try storageManager.saveAudioFile(from: tempFile, bookId: book.id.uuidString)
        storageManager.addToMetadata(book: book, fileSize: Int64(audioData.count))

        // When: Cleaning up
        storageManager.cleanupOrphanedFiles()

        // Then: File still exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath.path))
    }

    // MARK: - Format File Size Tests

    @MainActor
    func testFormatFileSize_FormatsBytes() {
        XCTAssertEqual(StorageManager.formatFileSize(500), "500 bytes")
    }

    @MainActor
    func testFormatFileSize_FormatsKB() {
        let formatted = StorageManager.formatFileSize(1024)
        XCTAssertTrue(formatted.contains("KB") || formatted.contains("kB"))
    }

    @MainActor
    func testFormatFileSize_FormatsMB() {
        let formatted = StorageManager.formatFileSize(1_048_576)
        XCTAssertTrue(formatted.contains("MB"))
    }

    @MainActor
    func testFormatFileSize_FormatsGB() {
        let formatted = StorageManager.formatFileSize(1_073_741_824)
        XCTAssertTrue(formatted.contains("GB"))
    }
}
