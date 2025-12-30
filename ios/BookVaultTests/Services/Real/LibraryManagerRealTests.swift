//
//  LibraryManagerRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 3: Real Services Testing - LibraryManager
//
//  Tests the real LibraryManager implementation with mocked dependencies.
//

import XCTest
@testable import BookVault

final class LibraryManagerRealTests: XCTestCase {
    // MARK: - Properties

    private var libraryManager: LibraryManager!
    private var mockAPIClient: MockAPIClient!
    private var mockLibraryCacheManager: MockLibraryCacheManager!
    private var mockNetworkMonitor: MockNetworkMonitor!
    private var mockStorageManager: MockStorageManager!

    // MARK: - Test Data

    private var testBooks: [LibraryBook]!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockLibraryCacheManager = MockLibraryCacheManager()
        mockNetworkMonitor = MockNetworkMonitor()
        mockStorageManager = MockStorageManager()

        libraryManager = LibraryManager(
            apiClient: mockAPIClient,
            libraryCacheManager: mockLibraryCacheManager,
            networkMonitor: mockNetworkMonitor,
            storageManager: mockStorageManager
        )

        // Create test books
        testBooks = [
            createTestBook(title: "Book 1", authorName: "Author 1"),
            createTestBook(title: "Book 2", authorName: "Author 2"),
            createTestBook(title: "Book 3", authorName: "Author 3")
        ]
    }

    @MainActor
    override func tearDown() {
        libraryManager = nil
        mockAPIClient = nil
        mockLibraryCacheManager = nil
        mockNetworkMonitor = nil
        mockStorageManager = nil
        testBooks = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createTestBook(title: String, authorName: String) -> LibraryBook {
        LibraryBook(
            id: UUID(),
            asin: "ASIN\(UUID().uuidString.prefix(8))",
            title: title,
            description: "Test description",
            runtimeMinutes: 360,
            releaseDate: Date(),
            publisher: "Test Publisher",
            coverUrl: "https://example.com/cover.jpg",
            audioUrl: "https://example.com/audio.mp3",
            authors: [Author(id: UUID(), name: authorName)],
            addedAt: Date()
        )
    }

    // MARK: - Fetch Library Books Tests (Online)

    @MainActor
    func testFetchLibraryBooks_WhenOnline_FetchesFromAPI() async throws {
        // Given: Online with API response
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))

        // When: Fetching library
        let result = try await libraryManager.fetchLibraryBooks()

        // Then: Returns API books
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(mockAPIClient.fetchLibraryCalls, 1)
    }

    @MainActor
    func testFetchLibraryBooks_WhenOnline_SavesToDiskCache() async throws {
        // Given: Online with API response
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))

        // When: Fetching library
        _ = try await libraryManager.fetchLibraryBooks()

        // Then: Saved to disk cache
        XCTAssertEqual(mockLibraryCacheManager.saveLibraryCalls.count, 1)
        XCTAssertEqual(mockLibraryCacheManager.saveLibraryCalls.first?.count, 3)
    }

    @MainActor
    func testFetchLibraryBooks_WhenOnline_SetsNotShowingCachedData() async throws {
        // Given: Online with API response
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))

        // When: Fetching library
        _ = try await libraryManager.fetchLibraryBooks()

        // Then: Not showing cached data
        XCTAssertFalse(libraryManager.isShowingCachedData)
    }

    @MainActor
    func testFetchLibraryBooks_WhenOnline_UsesMemoryCacheOnSecondCall() async throws {
        // Given: Online with API response
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))

        // When: Fetching library twice
        _ = try await libraryManager.fetchLibraryBooks()
        _ = try await libraryManager.fetchLibraryBooks()

        // Then: Only one API call (second uses memory cache)
        XCTAssertEqual(mockAPIClient.fetchLibraryCalls, 1)
    }

    @MainActor
    func testFetchLibraryBooks_ForceRefresh_BypassesMemoryCache() async throws {
        // Given: Online with library already cached
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))
        _ = try await libraryManager.fetchLibraryBooks()

        // When: Force refreshing
        _ = try await libraryManager.fetchLibraryBooks(forceRefresh: true)

        // Then: Two API calls (force refresh bypasses cache)
        XCTAssertEqual(mockAPIClient.fetchLibraryCalls, 2)
    }

    // MARK: - Fetch Library Books Tests (Offline)

    @MainActor
    func testFetchLibraryBooks_WhenOffline_WithDiskCache_ReturnsCachedData() async throws {
        // Given: Offline with disk cache
        mockNetworkMonitor.isConnected = false
        mockLibraryCacheManager.preloadCache(books: testBooks)

        // When: Fetching library
        let result = try await libraryManager.fetchLibraryBooks()

        // Then: Returns cached books
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(libraryManager.isShowingCachedData)
        XCTAssertEqual(mockAPIClient.fetchLibraryCalls, 0) // No API call
    }

    @MainActor
    func testFetchLibraryBooks_WhenOffline_WithNoDiskCache_Throws() async {
        // Given: Offline with no disk cache
        mockNetworkMonitor.isConnected = false
        mockLibraryCacheManager.loadShouldFail = true

        // When/Then: Throws error
        do {
            _ = try await libraryManager.fetchLibraryBooks()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is LibraryError)
            if let libraryError = error as? LibraryError {
                XCTAssertEqual(libraryError, .offlineNoCache)
            }
        }
    }

    // MARK: - Add to Library Tests

    @MainActor
    func testAddToLibrary_Success_CallsAPI() async throws {
        // Given: Valid book ID
        let bookId = UUID()
        mockAPIClient.addToLibraryResult = .success(AddToLibrary201Response(
            message: "Book added to library"
        ))

        // When: Adding to library
        try await libraryManager.addToLibrary(bookId: bookId.uuidString)

        // Then: API called
        XCTAssertEqual(mockAPIClient.addToLibraryCalls.count, 1)
        XCTAssertEqual(mockAPIClient.addToLibraryCalls.first, bookId)
    }

    @MainActor
    func testAddToLibrary_Success_IncrementsLibraryVersion() async throws {
        // Given: Initial library version
        let initialVersion = libraryManager.libraryVersion
        let bookId = UUID()
        mockAPIClient.addToLibraryResult = .success(AddToLibrary201Response(
            message: "Book added to library"
        ))

        // When: Adding to library
        try await libraryManager.addToLibrary(bookId: bookId.uuidString)

        // Then: Version incremented
        XCTAssertEqual(libraryManager.libraryVersion, initialVersion + 1)
    }

    @MainActor
    func testAddToLibrary_InvalidBookId_Throws() async {
        // Given: Invalid book ID

        // When/Then: Throws error
        do {
            try await libraryManager.addToLibrary(bookId: "invalid")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid book ID"))
        }
    }

    @MainActor
    func testAddToLibrary_APIError_Throws() async {
        // Given: API will fail
        let bookId = UUID()
        mockAPIClient.addToLibraryResult = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

        // When/Then: Throws error
        do {
            try await libraryManager.addToLibrary(bookId: bookId.uuidString)
            XCTFail("Expected error")
        } catch {
            // Error is thrown
        }
    }

    // MARK: - Remove from Library Tests

    @MainActor
    func testRemoveFromLibrary_Success_CallsAPI() async throws {
        // Given: Valid book ID
        let bookId = UUID()
        mockAPIClient.removeFromLibraryResult = .success(())

        // When: Removing from library
        try await libraryManager.removeFromLibrary(bookId: bookId.uuidString)

        // Then: API called
        XCTAssertEqual(mockAPIClient.removeFromLibraryCalls.count, 1)
        XCTAssertEqual(mockAPIClient.removeFromLibraryCalls.first, bookId)
    }

    @MainActor
    func testRemoveFromLibrary_Success_IncrementsLibraryVersion() async throws {
        // Given: Initial library version
        let initialVersion = libraryManager.libraryVersion
        let bookId = UUID()
        mockAPIClient.removeFromLibraryResult = .success(())

        // When: Removing from library
        try await libraryManager.removeFromLibrary(bookId: bookId.uuidString)

        // Then: Version incremented
        XCTAssertEqual(libraryManager.libraryVersion, initialVersion + 1)
    }

    @MainActor
    func testRemoveFromLibrary_WithDownload_DeletesLocalFile() async throws {
        // Given: Book is downloaded
        let bookId = UUID()
        mockStorageManager.downloadedBooks.insert(bookId.uuidString.uppercased())
        mockAPIClient.removeFromLibraryResult = .success(())

        // When: Removing from library
        try await libraryManager.removeFromLibrary(bookId: bookId.uuidString)

        // Then: Local download deleted
        XCTAssertEqual(mockStorageManager.deleteDownloadCalls.count, 1)
    }

    @MainActor
    func testRemoveFromLibrary_WithoutDownload_DoesNotDeleteFile() async throws {
        // Given: Book is not downloaded
        let bookId = UUID()
        mockAPIClient.removeFromLibraryResult = .success(())

        // When: Removing from library
        try await libraryManager.removeFromLibrary(bookId: bookId.uuidString)

        // Then: No delete call
        XCTAssertEqual(mockStorageManager.deleteDownloadCalls.count, 0)
    }

    @MainActor
    func testRemoveFromLibrary_DeleteFails_DoesNotThrow() async throws {
        // Given: Book is downloaded but delete will fail
        let bookId = UUID()
        mockStorageManager.downloadedBooks.insert(bookId.uuidString.uppercased())
        mockStorageManager.deleteShouldFail = true
        mockAPIClient.removeFromLibraryResult = .success(())

        // When: Removing from library
        try await libraryManager.removeFromLibrary(bookId: bookId.uuidString)

        // Then: Does not throw (delete failure is logged but not thrown)
        XCTAssertEqual(mockStorageManager.deleteDownloadCalls.count, 1)
    }

    @MainActor
    func testRemoveFromLibrary_InvalidBookId_Throws() async {
        // Given: Invalid book ID

        // When/Then: Throws error
        do {
            try await libraryManager.removeFromLibrary(bookId: "invalid")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid book ID"))
        }
    }

    // MARK: - Is In Library Tests

    @MainActor
    func testIsInLibrary_WithCachedData_ReturnsFromCache() async throws {
        // Given: Library is cached
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))
        _ = try await libraryManager.fetchLibraryBooks()

        let bookId = testBooks[0].id.uuidString

        // When: Checking if in library
        let result = try await libraryManager.isInLibrary(bookId: bookId)

        // Then: Returns true from cache (no additional API call)
        XCTAssertTrue(result)
        XCTAssertEqual(mockAPIClient.fetchLibraryCalls, 1) // Only the initial fetch
    }

    @MainActor
    func testIsInLibrary_BookNotInLibrary_ReturnsFalse() async throws {
        // Given: Library is cached without the book
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))
        _ = try await libraryManager.fetchLibraryBooks()

        let nonExistentBookId = UUID().uuidString

        // When: Checking if in library
        let result = try await libraryManager.isInLibrary(bookId: nonExistentBookId)

        // Then: Returns false
        XCTAssertFalse(result)
    }

    // MARK: - Refresh Cache Tests

    @MainActor
    func testRefreshCache_ForcesAPIFetch() async throws {
        // Given: Library is cached
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))
        _ = try await libraryManager.fetchLibraryBooks()

        // When: Refreshing cache
        try await libraryManager.refreshCache()

        // Then: Two API calls (initial + refresh)
        XCTAssertEqual(mockAPIClient.fetchLibraryCalls, 2)
    }

    // MARK: - Loading State Tests

    @MainActor
    func testFetchLibraryBooks_SetsLoadingState() async throws {
        // Given: Online with API response
        mockNetworkMonitor.isConnected = true
        mockAPIClient.fetchLibraryResult = .success(GetLibrary200Response(books: testBooks, total: 3))

        // When: Fetching library
        _ = try await libraryManager.fetchLibraryBooks()

        // Then: Loading state is cleared after completion
        XCTAssertFalse(libraryManager.isLoading)
    }

    @MainActor
    func testAddToLibrary_SetsLoadingState() async throws {
        // Given: Valid operation
        let bookId = UUID()
        mockAPIClient.addToLibraryResult = .success(AddToLibrary201Response(message: "Added"))

        // When: Adding to library
        try await libraryManager.addToLibrary(bookId: bookId.uuidString)

        // Then: Loading state is cleared
        XCTAssertFalse(libraryManager.isLoading)
    }

    @MainActor
    func testRemoveFromLibrary_SetsLoadingState() async throws {
        // Given: Valid operation
        let bookId = UUID()
        mockAPIClient.removeFromLibraryResult = .success(())

        // When: Removing from library
        try await libraryManager.removeFromLibrary(bookId: bookId.uuidString)

        // Then: Loading state is cleared
        XCTAssertFalse(libraryManager.isLoading)
    }
}
