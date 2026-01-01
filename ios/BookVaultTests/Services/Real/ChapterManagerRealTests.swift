//
//  ChapterManagerRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 3: Real Services Testing - ChapterManager
//
//  Tests the real ChapterManager implementation with mocked API client.
//

import XCTest
@testable import BookVault

final class ChapterManagerRealTests: XCTestCase {
    // MARK: - Properties

    private var chapterManager: ChapterManager!
    private var mockAPIClient: MockAPIClient!

    // MARK: - Test Data

    private var testBookId: UUID!
    private var testChapters: [Chapter]!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        chapterManager = ChapterManager(apiClient: mockAPIClient)

        testBookId = UUID()
        testChapters = [
            Chapter(
                id: UUID(),
                title: "Chapter 1: Introduction",
                startTime: 0.0,
                endTime: 600.0,
                duration: 600.0,
                index: 0
            ),
            Chapter(
                id: UUID(),
                title: "Chapter 2: The Journey Begins",
                startTime: 600.0,
                endTime: 1200.0,
                duration: 600.0,
                index: 1
            ),
            Chapter(
                id: UUID(),
                title: "Chapter 3: Challenges",
                startTime: 1200.0,
                endTime: 1800.0,
                duration: 600.0,
                index: 2
            )
        ]
    }

    @MainActor
    override func tearDown() {
        chapterManager = nil
        mockAPIClient = nil
        testBookId = nil
        testChapters = nil
        super.tearDown()
    }

    // MARK: - Fetch Chapters Tests

    @MainActor
    func testFetchChapters_Success_ReturnsChapters() async {
        // Given: API returns chapters
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)

        // When: Fetching chapters
        let result = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Returns chapters
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].title, "Chapter 1: Introduction")
        XCTAssertEqual(result[1].title, "Chapter 2: The Journey Begins")
        XCTAssertEqual(result[2].title, "Chapter 3: Challenges")
    }

    @MainActor
    func testFetchChapters_Success_UpdatesPublishedProperty() async {
        // Given: API returns chapters
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)

        // When: Fetching chapters
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Published chapters are updated
        XCTAssertEqual(chapterManager.chapters.count, 3)
    }

    @MainActor
    func testFetchChapters_Success_CachesChapters() async {
        // Given: API returns chapters
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)

        // When: Fetching chapters
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Chapters are cached
        XCTAssertTrue(chapterManager.hasCachedChapters(bookId: testBookId.uuidString))
    }

    @MainActor
    func testFetchChapters_CacheHit_ReturnsFromCache() async {
        // Given: Chapters already cached
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)
        let initialCallCount = mockAPIClient.fetchBookChaptersCalls.count

        // When: Fetching same chapters again
        let result = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Returns from cache without API call
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(mockAPIClient.fetchBookChaptersCalls.count, initialCallCount)
    }

    @MainActor
    func testFetchChapters_InvalidBookId_ReturnsEmptyArray() async {
        // Given: Invalid book ID
        let invalidBookId = "not-a-uuid"

        // When: Fetching chapters
        let result = await chapterManager.fetchChapters(bookId: invalidBookId)

        // Then: Returns empty array
        XCTAssertTrue(result.isEmpty)
        // And: Does NOT cache empty result (allows retry)
        XCTAssertFalse(chapterManager.hasCachedChapters(bookId: invalidBookId))
    }

    @MainActor
    func testFetchChapters_APIError_ReturnsEmptyArray() async {
        // Given: API returns error
        mockAPIClient.fetchBookChaptersResult = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

        // When: Fetching chapters
        let result = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Returns empty array (graceful failure)
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testFetchChapters_APIError_DoesNotCacheEmptyResult() async {
        // Given: API returns error
        mockAPIClient.fetchBookChaptersResult = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

        // When: Fetching chapters
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Does NOT cache empty result (allows retry when network recovers)
        XCTAssertFalse(chapterManager.hasCachedChapters(bookId: testBookId.uuidString))
    }

    @MainActor
    func testFetchChapters_SetsLoadingState() async {
        // Given: API returns chapters
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)

        // When: Fetching chapters
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Loading state is cleared after completion
        XCTAssertFalse(chapterManager.isLoading)
    }

    // MARK: - Get Cached Chapters Tests

    @MainActor
    func testGetCachedChapters_WithCachedData_ReturnsChapters() async {
        // Given: Chapters are cached
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // When: Getting cached chapters synchronously
        let result = chapterManager.getCachedChapters(bookId: testBookId.uuidString)

        // Then: Returns cached chapters
        XCTAssertEqual(result.count, 3)
    }

    @MainActor
    func testGetCachedChapters_WithNoCache_ReturnsEmptyArray() {
        // Given: No cached chapters
        let bookId = UUID().uuidString

        // When: Getting cached chapters
        let result = chapterManager.getCachedChapters(bookId: bookId)

        // Then: Returns empty array
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Has Cached Chapters Tests

    @MainActor
    func testHasCachedChapters_WithCachedData_ReturnsTrue() async {
        // Given: Chapters are cached
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // When: Checking cache
        let result = chapterManager.hasCachedChapters(bookId: testBookId.uuidString)

        // Then: Returns true
        XCTAssertTrue(result)
    }

    @MainActor
    func testHasCachedChapters_WithNoCache_ReturnsFalse() {
        // Given: No cached chapters
        let bookId = UUID().uuidString

        // When: Checking cache
        let result = chapterManager.hasCachedChapters(bookId: bookId)

        // Then: Returns false
        XCTAssertFalse(result)
    }

    // MARK: - Clear Cache Tests

    @MainActor
    func testClearCache_RemovesAllCachedChapters() async {
        // Given: Multiple books cached
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        let bookId2 = UUID().uuidString
        _ = await chapterManager.fetchChapters(bookId: bookId2)

        // When: Clearing cache
        chapterManager.clearCache()

        // Then: All cache is cleared
        XCTAssertFalse(chapterManager.hasCachedChapters(bookId: testBookId.uuidString))
        XCTAssertFalse(chapterManager.hasCachedChapters(bookId: bookId2))
        XCTAssertTrue(chapterManager.chapters.isEmpty)
    }

    @MainActor
    func testClearCacheForBook_RemovesOnlyThatBook() async {
        // Given: Multiple books cached
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        let bookId2 = UUID()
        let chapters2 = [
            Chapter(id: UUID(), title: "Other Chapter", startTime: 0, endTime: 300, duration: 300, index: 0)
        ]
        mockAPIClient.fetchBookChaptersResult = .success(chapters2)
        _ = await chapterManager.fetchChapters(bookId: bookId2.uuidString)

        // When: Clearing cache for one book
        chapterManager.clearCache(for: testBookId.uuidString)

        // Then: Only that book is cleared
        XCTAssertFalse(chapterManager.hasCachedChapters(bookId: testBookId.uuidString))
        XCTAssertTrue(chapterManager.hasCachedChapters(bookId: bookId2.uuidString))
    }

    // MARK: - Chapter Structure Tests

    @MainActor
    func testFetchChapters_ChapterTimesAreCorrect() async {
        // Given: API returns chapters with specific times
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)

        // When: Fetching chapters
        let result = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Times are correct
        XCTAssertEqual(result[0].startTime, 0.0)
        XCTAssertEqual(result[0].endTime, 600.0)
        XCTAssertEqual(result[1].startTime, 600.0)
        XCTAssertEqual(result[1].endTime, 1200.0)
    }

    @MainActor
    func testFetchChapters_ChapterIndicesArePreserved() async {
        // Given: API returns chapters with indices
        mockAPIClient.fetchBookChaptersResult = .success(testChapters)

        // When: Fetching chapters
        let result = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Indices are preserved
        XCTAssertEqual(result[0].index, 0)
        XCTAssertEqual(result[1].index, 1)
        XCTAssertEqual(result[2].index, 2)
    }

    // MARK: - Empty Chapters Tests

    @MainActor
    func testFetchChapters_NoChapters_ReturnsEmptyArray() async {
        // Given: API returns empty chapters
        mockAPIClient.fetchBookChaptersResult = .success([])

        // When: Fetching chapters
        let result = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Returns empty array
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testFetchChapters_NoChapters_DoesNotCacheEmptyResult() async {
        // Given: API returns empty chapters
        mockAPIClient.fetchBookChaptersResult = .success([])

        // When: Fetching chapters
        _ = await chapterManager.fetchChapters(bookId: testBookId.uuidString)

        // Then: Empty result is NOT cached (allows retry when chapters become available)
        XCTAssertFalse(chapterManager.hasCachedChapters(bookId: testBookId.uuidString))
        XCTAssertTrue(chapterManager.getCachedChapters(bookId: testBookId.uuidString).isEmpty)
    }
}
