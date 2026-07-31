//
//  StorageManagerTests.swift
//  BookVaultTests
//
//  Unit tests for StorageManager.
//

import XCTest
@testable import BookVault

@MainActor
final class StorageManagerTests: XCTestCase {
    var sut: MockStorageManager!
    var testDirectory: URL!

    override func setUp() async throws {
        sut = MockStorageManager()
        // Create temp directory for test files
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Clean up test files
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        sut = nil
    }

    // MARK: - Storage Space Tests

    func testAvailableStorageReturnsConfiguredValue() {
        // Given: A mock with configured available space
        sut.configurableAvailableSpace = 20_000_000_000 // 20GB

        // Then: Should return the configured value
        XCTAssertEqual(sut.availableDeviceSpace, 20_000_000_000)
    }

    func testHasSpaceForDownloadReturnsTrueWhenSpaceAvailable() {
        // Given: Enough storage available
        sut.configurableStorageLimit = 5_000_000_000 // 5GB
        sut.configurableAvailableSpace = 10_000_000_000 // 10GB
        sut.totalSize = 0

        // When: Checking if can download 1GB file
        let result = sut.canDownload(fileSize: 1_000_000_000)

        // Then: Should return true
        XCTAssertTrue(result)
    }

    func testHasSpaceForDownloadReturnsFalseWhenExceedsLimit() {
        // Given: Limited storage
        sut.configurableStorageLimit = 1_000_000_000 // 1GB
        sut.totalSize = 500_000_000 // 500MB already used

        // When: Trying to download 600MB file (would exceed 1GB limit)
        let result = sut.canDownload(fileSize: 600_000_000)

        // Then: Should return false
        XCTAssertFalse(result)
    }

    func testHasSpaceForDownloadReturnsFalseWhenDeviceSpaceLow() {
        // Given: Limited device space
        sut.configurableAvailableSpace = 400_000_000 // 400MB (less than 500MB buffer)

        // When: Trying to download any file
        let result = sut.canDownload(fileSize: 100_000_000)

        // Then: Should return false (need 500MB buffer)
        XCTAssertFalse(result)
    }

    // MARK: - File Operations Tests

    func testSaveAudioFileRecordsCall() throws {
        // Given: A temporary file
        let tempURL = testDirectory.appendingPathComponent("temp.mp3")
        try "test".data(using: .utf8)!.write(to: tempURL)
        let bookId = "test-book-id"

        // When: saveAudioFile is called
        _ = try sut.saveAudioFile(from: tempURL, bookId: bookId)

        // Then: Call should be recorded
        XCTAssertEqual(sut.saveAudioFileCalls.count, 1)
        XCTAssertEqual(sut.saveAudioFileCalls.first?.bookId, bookId)
    }

    func testSaveAudioFileThrowsWhenConfiguredToFail() throws {
        // Given: Mock configured to fail
        sut.saveShouldFail = true
        let tempURL = testDirectory.appendingPathComponent("temp.mp3")

        // When/Then: Should throw
        XCTAssertThrowsError(try sut.saveAudioFile(from: tempURL, bookId: "test"))
    }

    func testDeleteDownloadRecordsCall() throws {
        // Given: A book in the downloaded list
        let book = TestFixtures.makeBook()
        sut.addToMetadata(book: book, fileSize: 100_000_000, fileExtension: "mp3")

        // When: deleteDownload is called
        try sut.deleteDownload(bookId: book.id.uuidString)

        // Then: Call should be recorded
        XCTAssertEqual(sut.deleteDownloadCalls.count, 1)
    }

    func testDeleteDownloadRemovesFromDownloads() throws {
        // Given: A book in the downloaded list
        let book = TestFixtures.makeBook()
        sut.addToMetadata(book: book, fileSize: 100_000_000, fileExtension: "mp3")
        XCTAssertTrue(sut.isBookDownloaded(bookId: book.id.uuidString))

        // When: deleteDownload is called
        try sut.deleteDownload(bookId: book.id.uuidString)

        // Then: Book should no longer be in downloads
        XCTAssertFalse(sut.isBookDownloaded(bookId: book.id.uuidString))
    }

    func testDeleteDownloadThrowsWhenConfiguredToFail() throws {
        // Given: Mock configured to fail
        sut.deleteShouldFail = true

        // When/Then: Should throw
        XCTAssertThrowsError(try sut.deleteDownload(bookId: "test"))
    }

    func testIsDownloadedReturnsTrueForSavedFile() throws {
        // Given: A book added to metadata
        let book = TestFixtures.makeBook()
        sut.addToMetadata(book: book, fileSize: 100_000_000, fileExtension: "mp3")

        // When: Checking if downloaded
        let result = sut.isBookDownloaded(bookId: book.id.uuidString)

        // Then: Should return true
        XCTAssertTrue(result)
    }

    func testIsDownloadedReturnsFalseForMissingFile() {
        // Given: An unknown book ID

        // When: Checking if downloaded
        let result = sut.isBookDownloaded(bookId: UUID().uuidString)

        // Then: Should return false
        XCTAssertFalse(result)
    }

    // MARK: - Metadata Tests

    func testAddToMetadataUpdatesDownloads() {
        // Given: A book to add
        let book = TestFixtures.makeBook()

        // When: Adding to metadata
        sut.addToMetadata(book: book, fileSize: 500_000_000, fileExtension: "m4a")

        // Then: Should be in downloads
        XCTAssertEqual(sut.downloads.count, 1)
        XCTAssertEqual(sut.downloads.first?.title, book.title)
        XCTAssertEqual(sut.downloads.first?.fileExtension, "m4a")
    }

    func testAddToMetadataUpdatesTotalSize() {
        // Given: A book to add
        let book = TestFixtures.makeBook()

        // When: Adding to metadata
        sut.addToMetadata(book: book, fileSize: 500_000_000, fileExtension: "mp3")

        // Then: Total size should be updated
        XCTAssertEqual(sut.totalSize, 500_000_000)
    }

    func testGetDownloadedBookReturnsMetadata() {
        // Given: A book added to metadata
        let book = TestFixtures.makeBook()
        sut.addToMetadata(book: book, fileSize: 100_000_000, fileExtension: "mp3")

        // When: Getting downloaded book
        let result = sut.getDownloadedBook(bookId: book.id.uuidString)

        // Then: Should return metadata
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, book.title)
    }

    func testGetDownloadedBookReturnsNilForUnknown() {
        // Given: No downloads

        // When: Getting unknown book
        let result = sut.getDownloadedBook(bookId: UUID().uuidString)

        // Then: Should return nil
        XCTAssertNil(result)
    }

    // MARK: - Storage Usage Tests

    func testStorageUsagePercentageCalculation() {
        // Given: Known storage values
        sut.configurableStorageLimit = 10_000_000_000 // 10GB
        sut.totalSize = 2_500_000_000 // 2.5GB

        // When: Calculating usage percentage
        let percentage = sut.storageUsagePercentage

        // Then: Should be 25%
        XCTAssertEqual(percentage, 0.25, accuracy: 0.001)
    }

    func testIsNearStorageLimitReturnsTrueAbove90Percent() {
        // Given: 95% usage
        sut.configurableStorageLimit = 10_000_000_000
        sut.totalSize = 9_500_000_000

        // Then: Should be near limit
        XCTAssertTrue(sut.isNearStorageLimit)
    }

    func testIsNearStorageLimitReturnsFalseBelow90Percent() {
        // Given: 50% usage
        sut.configurableStorageLimit = 10_000_000_000
        sut.totalSize = 5_000_000_000

        // Then: Should not be near limit
        XCTAssertFalse(sut.isNearStorageLimit)
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() {
        // Given: Some state
        let book = TestFixtures.makeBook()
        sut.addToMetadata(book: book, fileSize: 100_000_000, fileExtension: "mp3")
        sut.saveShouldFail = true

        // When: Reset is called
        sut.reset()

        // Then: All state should be cleared
        XCTAssertTrue(sut.downloads.isEmpty)
        XCTAssertEqual(sut.totalSize, 0)
        XCTAssertFalse(sut.saveShouldFail)
        XCTAssertTrue(sut.downloadedBooks.isEmpty)
    }

    // MARK: - Delete All Tests

    func testDeleteAllDownloadsMarksAsCalled() throws {
        // When: deleteAllDownloads is called
        try sut.deleteAllDownloads()

        // Then: Should be marked as called
        XCTAssertTrue(sut.deleteAllDownloadsCalled)
    }

    func testDeleteAllDownloadsClearsDownloads() throws {
        // Given: Some downloads
        let book = TestFixtures.makeBook()
        sut.addToMetadata(book: book, fileSize: 100_000_000, fileExtension: "mp3")

        // When: deleteAllDownloads is called
        try sut.deleteAllDownloads()

        // Then: Downloads should be empty
        XCTAssertTrue(sut.downloads.isEmpty)
        XCTAssertEqual(sut.totalSize, 0)
    }

    // MARK: - Audio File Path Tests

    func testAudioFilePathNormalizesBookId() {
        // Given: A lowercase book ID
        let bookId = "abc12345-6789-0abc-def0-123456789abc"

        // When: Getting audio file path
        let path = sut.audioFilePath(for: bookId)

        // Then: Path should use uppercase ID
        XCTAssertTrue(path.lastPathComponent.hasPrefix(bookId.uppercased()))
    }

    func testAudioFilePathWithExtension() {
        // Given: A book ID and extension
        let bookId = TestFixtures.testBookId.uuidString

        // When: Getting audio file path with m4a extension
        let path = sut.audioFilePath(for: bookId, extension: "m4a")

        // Then: Path should have correct extension
        XCTAssertTrue(path.lastPathComponent.hasSuffix(".m4a"))
    }
}
