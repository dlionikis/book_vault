//
//  LibraryCacheManagerRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 2: Real Services Testing - LibraryCacheManager
//

import XCTest
@testable import BookVault

final class LibraryCacheManagerRealTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!
    private var cacheManager: LibraryCacheManager!
    private var testUserId: String!

    // MARK: - Test Helpers

    private func createTestBook(id: UUID = UUID(), title: String = "Test Book", authorName: String = "Test Author") -> Book {
        let author = Author(id: UUID(), name: authorName)
        return Book(id: id, asin: "ASIN123", title: title, authors: [author])
    }

    private func createTestBooks(count: Int) -> [Book] {
        return (1...count).map { i in
            createTestBook(id: UUID(), title: "Book \(i)", authorName: "Author \(i)")
        }
    }

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        // Create a unique temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryCacheManagerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create a test user ID
        testUserId = UUID().uuidString

        // Create cache manager with test directory and user ID provider
        cacheManager = LibraryCacheManager(
            cacheDirectory: tempDirectory,
            userIdProvider: { [weak self] in self?.testUserId }
        )
    }

    @MainActor
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        cacheManager = nil
        tempDirectory = nil
        testUserId = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    @MainActor
    func testInitialization_CreatesCacheDirectory() {
        // Then: Cache directory should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    @MainActor
    func testInitialization_WithEmptyDirectory_HasNoCache() {
        // Given: Fresh cache manager
        // Then: No valid cache
        XCTAssertFalse(cacheManager.isCacheValid())
        XCTAssertNil(cacheManager.loadLibrary())
    }

    // MARK: - Save Library Tests

    @MainActor
    func testSaveLibrary_CreatesValidCache() {
        // Given: A list of books
        let books = createTestBooks(count: 5)

        // When: Saving library
        cacheManager.saveLibrary(books: books)

        // Then: Cache is valid
        XCTAssertTrue(cacheManager.isCacheValid())
    }

    @MainActor
    func testSaveLibrary_CreatesJsonFile() {
        // Given: A list of books
        let books = createTestBooks(count: 3)

        // When: Saving library
        cacheManager.saveLibrary(books: books)

        // Then: Cache file exists
        let cacheFile = tempDirectory.appendingPathComponent("library.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    @MainActor
    func testSaveLibrary_WithNoUser_DoesNotSave() {
        // Given: No user logged in
        testUserId = nil

        // When: Attempting to save
        let books = createTestBooks(count: 3)
        cacheManager.saveLibrary(books: books)

        // Then: No cache created
        XCTAssertFalse(cacheManager.isCacheValid())
    }

    @MainActor
    func testSaveLibrary_OverwritesPreviousCache() {
        // Given: Existing cache with 5 books
        let oldBooks = createTestBooks(count: 5)
        cacheManager.saveLibrary(books: oldBooks)

        // When: Saving new library with 3 books
        let newBooks = createTestBooks(count: 3)
        cacheManager.saveLibrary(books: newBooks)

        // Then: New cache replaces old
        let loaded = cacheManager.loadLibrary()
        XCTAssertEqual(loaded?.count, 3)
    }

    @MainActor
    func testSaveLibrary_WithEmptyArray_SavesEmptyCache() {
        // When: Saving empty library
        cacheManager.saveLibrary(books: [])

        // Then: Cache is valid but empty
        XCTAssertTrue(cacheManager.isCacheValid())
        let loaded = cacheManager.loadLibrary()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 0)
    }

    // MARK: - Load Library Tests

    @MainActor
    func testLoadLibrary_ReturnsCorrectBooks() {
        // Given: Saved library
        let books = createTestBooks(count: 5)
        cacheManager.saveLibrary(books: books)

        // When: Loading library
        let loaded = cacheManager.loadLibrary()

        // Then: Same books are returned
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 5)

        // Verify book details
        for (index, book) in (loaded ?? []).enumerated() {
            XCTAssertEqual(book.title, "Book \(index + 1)")
        }
    }

    @MainActor
    func testLoadLibrary_WithNoCache_ReturnsNil() {
        // Given: No cache exists
        // When/Then: Returns nil
        XCTAssertNil(cacheManager.loadLibrary())
    }

    @MainActor
    func testLoadLibrary_WithNoUser_ReturnsNil() {
        // Given: Valid cache
        let books = createTestBooks(count: 3)
        cacheManager.saveLibrary(books: books)

        // When: User logs out
        testUserId = nil

        // Then: Cannot load
        XCTAssertNil(cacheManager.loadLibrary())
    }

    @MainActor
    func testLoadLibrary_WithDifferentUser_ReturnsNil() {
        // Given: Cache saved with one user
        let books = createTestBooks(count: 3)
        cacheManager.saveLibrary(books: books)

        // When: Different user logs in
        testUserId = UUID().uuidString

        // Then: Cache is not accessible
        XCTAssertNil(cacheManager.loadLibrary())
    }

    @MainActor
    func testLoadLibrary_PreservesBookDetails() {
        // Given: A book with all details
        let book = Book(
            id: UUID(),
            asin: "B0123456789",
            title: "The Great Book",
            description: "A wonderful story",
            runtimeMinutes: 600,
            releaseDate: Date(timeIntervalSince1970: 1700000000),
            publisher: "Great Publisher",
            coverUrl: "https://example.com/cover.jpg",
            audioUrl: "https://example.com/audio.mp3",
            authors: [Author(id: UUID(), name: "Famous Author", asin: "A123")],
            narrators: [Narrator(id: UUID(), name: "Voice Actor", asin: "N456")],
            series: [SeriesInfo(id: UUID(), title: "Epic Series", sequence: "1")],
            categories: [Category(id: UUID(), name: "Fiction")]
        )

        // When: Saving and loading
        cacheManager.saveLibrary(books: [book])
        let loaded = cacheManager.loadLibrary()

        // Then: All details are preserved
        let loadedBook = loaded?.first
        XCTAssertNotNil(loadedBook)
        XCTAssertEqual(loadedBook?.title, "The Great Book")
        XCTAssertEqual(loadedBook?.description, "A wonderful story")
        XCTAssertEqual(loadedBook?.runtimeMinutes, 600)
        XCTAssertEqual(loadedBook?.publisher, "Great Publisher")
        XCTAssertEqual(loadedBook?.authors.first?.name, "Famous Author")
        XCTAssertEqual(loadedBook?.narrators?.first?.name, "Voice Actor")
        XCTAssertEqual(loadedBook?.series?.first?.title, "Epic Series")
        XCTAssertEqual(loadedBook?.categories?.first?.name, "Fiction")
    }

    // MARK: - Is Cache Valid Tests

    @MainActor
    func testIsCacheValid_WithNoFile_ReturnsFalse() {
        XCTAssertFalse(cacheManager.isCacheValid())
    }

    @MainActor
    func testIsCacheValid_WithValidCache_ReturnsTrue() {
        let books = createTestBooks(count: 1)
        cacheManager.saveLibrary(books: books)
        XCTAssertTrue(cacheManager.isCacheValid())
    }

    @MainActor
    func testIsCacheValid_WithNoUser_ReturnsFalse() {
        let books = createTestBooks(count: 1)
        cacheManager.saveLibrary(books: books)

        testUserId = nil
        XCTAssertFalse(cacheManager.isCacheValid())
    }

    @MainActor
    func testIsCacheValid_WithDifferentUser_ReturnsFalse() {
        let books = createTestBooks(count: 1)
        cacheManager.saveLibrary(books: books)

        testUserId = UUID().uuidString
        XCTAssertFalse(cacheManager.isCacheValid())
    }

    @MainActor
    func testIsCacheValid_WithCorruptedFile_ReturnsFalse() {
        // Given: A corrupted cache file
        let cacheFile = tempDirectory.appendingPathComponent("library.json")
        try? Data("not valid json".utf8).write(to: cacheFile)

        // Then: Cache is not valid
        XCTAssertFalse(cacheManager.isCacheValid())
    }

    // MARK: - Last Sync Date Tests

    @MainActor
    func testGetLastSyncDate_WithNoCache_ReturnsNil() {
        XCTAssertNil(cacheManager.getLastSyncDate())
    }

    @MainActor
    func testGetLastSyncDate_AfterSave_ReturnsRecentDate() {
        // Given: Just saved library
        let now = Date()
        let books = createTestBooks(count: 1)
        cacheManager.saveLibrary(books: books)

        // When: Getting last sync date
        let syncDate = cacheManager.getLastSyncDate()

        // Then: Date is within 2 seconds of now (accounting for JSON date encoding precision)
        XCTAssertNotNil(syncDate)
        let timeDifference = abs(syncDate!.timeIntervalSince(now))
        XCTAssertLessThan(timeDifference, 2.0, "Sync date should be within 2 seconds of now")
    }

    @MainActor
    func testGetLastSyncDate_WithNoUser_ReturnsNil() {
        let books = createTestBooks(count: 1)
        cacheManager.saveLibrary(books: books)

        testUserId = nil
        XCTAssertNil(cacheManager.getLastSyncDate())
    }

    @MainActor
    func testGetLastSyncDate_WithDifferentUser_ReturnsNil() {
        let books = createTestBooks(count: 1)
        cacheManager.saveLibrary(books: books)

        testUserId = UUID().uuidString
        XCTAssertNil(cacheManager.getLastSyncDate())
    }

    // MARK: - Clear Cache Tests

    @MainActor
    func testClearCache_RemovesCacheFile() {
        // Given: Valid cache
        let books = createTestBooks(count: 3)
        cacheManager.saveLibrary(books: books)
        let cacheFile = tempDirectory.appendingPathComponent("library.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        // When: Clearing cache
        cacheManager.clearCache()

        // Then: File is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    @MainActor
    func testClearCache_InvalidatesCache() {
        // Given: Valid cache
        let books = createTestBooks(count: 3)
        cacheManager.saveLibrary(books: books)
        XCTAssertTrue(cacheManager.isCacheValid())

        // When: Clearing cache
        cacheManager.clearCache()

        // Then: Cache is no longer valid
        XCTAssertFalse(cacheManager.isCacheValid())
        XCTAssertNil(cacheManager.loadLibrary())
    }

    @MainActor
    func testClearCache_WithNoExistingCache_DoesNotThrow() {
        // Given: No cache exists
        // When/Then: Clearing doesn't throw
        cacheManager.clearCache()
        XCTAssertFalse(cacheManager.isCacheValid())
    }

    // MARK: - Persistence Tests

    @MainActor
    func testLibrary_PersistsAcrossInstances() {
        // Given: Library saved
        let books = createTestBooks(count: 5)
        cacheManager.saveLibrary(books: books)

        // When: Creating new cache manager with same directory and user
        let newManager = LibraryCacheManager(
            cacheDirectory: tempDirectory,
            userIdProvider: { [weak self] in self?.testUserId }
        )

        // Then: Library is loaded
        let loaded = newManager.loadLibrary()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 5)
    }

    @MainActor
    func testLibrary_WithDifferentUserOnReload_NotAccessible() {
        // Given: Library saved with one user
        let books = createTestBooks(count: 5)
        cacheManager.saveLibrary(books: books)

        // When: Creating new cache manager with different user
        let differentUserId = UUID().uuidString
        let newManager = LibraryCacheManager(
            cacheDirectory: tempDirectory,
            userIdProvider: { differentUserId }
        )

        // Then: Library is not accessible
        XCTAssertNil(newManager.loadLibrary())
    }

    // MARK: - Large Dataset Tests

    @MainActor
    func testSaveAndLoadLibrary_WithManyBooks_Works() {
        // Given: Large library
        let books = createTestBooks(count: 100)

        // When: Saving and loading
        cacheManager.saveLibrary(books: books)
        let loaded = cacheManager.loadLibrary()

        // Then: All books are preserved
        XCTAssertEqual(loaded?.count, 100)
    }

    // MARK: - Edge Cases

    @MainActor
    func testSaveLibrary_WithBooksHavingSpecialCharacters_Works() {
        // Given: Book with special characters in title
        let book = createTestBook(title: "Book with \"quotes\" & <special> chars")
        cacheManager.saveLibrary(books: [book])

        // When: Loading
        let loaded = cacheManager.loadLibrary()

        // Then: Special characters are preserved
        XCTAssertEqual(loaded?.first?.title, "Book with \"quotes\" & <special> chars")
    }

    @MainActor
    func testSaveLibrary_WithUnicodeContent_Works() {
        // Given: Book with unicode characters
        let book = createTestBook(title: "日本語のタイトル 🎧📚")
        cacheManager.saveLibrary(books: [book])

        // When: Loading
        let loaded = cacheManager.loadLibrary()

        // Then: Unicode is preserved
        XCTAssertEqual(loaded?.first?.title, "日本語のタイトル 🎧📚")
    }

    @MainActor
    func testLoadLibrary_WithPartiallyCorruptedJson_ReturnsNil() {
        // Given: Partially valid JSON that doesn't match expected structure
        let cacheFile = tempDirectory.appendingPathComponent("library.json")
        let invalidJson = """
        {"version": 1, "books": "not an array", "lastSyncDate": "2024-01-01T00:00:00Z", "userId": "\(testUserId!)"}
        """
        try? Data(invalidJson.utf8).write(to: cacheFile)

        // When/Then: Loading returns nil (decoding fails)
        XCTAssertNil(cacheManager.loadLibrary())
    }
}
