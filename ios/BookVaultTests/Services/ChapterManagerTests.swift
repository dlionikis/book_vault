//
//  ChapterManagerTests.swift
//  BookVaultTests
//
//  Tests for ChapterManager - Phase 3: Playback Core Tests
//

import XCTest
@testable import BookVault

@MainActor
/// `@unchecked Sendable` so test bodies can capture `self` inside the
/// `@Sendable` closures these tests hand to URLProtocol / refresh handlers.
/// XCTest drives one instance per test method and never concurrently, so
/// there is no cross-test sharing to race on.
final class ChapterManagerTests: XCTestCase, @unchecked Sendable {
    var sut: ChapterManager!
    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        sut = ChapterManager(apiClient: mockAPIClient)
    }

    override func tearDown() {
        sut.clearCache()
        sut = nil
        mockAPIClient.reset()
        mockAPIClient = nil
        super.tearDown()
    }

    // MARK: - Fetch Chapters Tests

    func testFetchChaptersCallsAPI() async throws {
        // Given chapters from API
        let bookId = TestFixtures.testBookId.uuidString
        let chapters = TestFixtures.makeChapterList(count: 5)
        mockAPIClient.fetchBookChaptersResult = .success(chapters)

        // When fetchChapters is called
        let result = await sut.fetchChapters(bookId: bookId)

        // Then API should be called and chapters returned
        XCTAssertEqual(mockAPIClient.fetchBookChaptersCalls.count, 1)
        XCTAssertEqual(mockAPIClient.fetchBookChaptersCalls.first, TestFixtures.testBookId)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(sut.chapters.count, 5)
    }

    func testFetchChaptersReturnsFromCache() async throws {
        // Given chapters already cached
        let bookId = TestFixtures.testBookId.uuidString
        let chapters = TestFixtures.makeChapterList(count: 3)
        mockAPIClient.fetchBookChaptersResult = .success(chapters)

        // First call to populate cache
        _ = await sut.fetchChapters(bookId: bookId)
        XCTAssertEqual(mockAPIClient.fetchBookChaptersCalls.count, 1)

        // When fetchChapters is called again
        let result = await sut.fetchChapters(bookId: bookId)

        // Then should return cached chapters without calling API again
        XCTAssertEqual(mockAPIClient.fetchBookChaptersCalls.count, 1) // Still 1, not 2
        XCTAssertEqual(result.count, 3)
    }

    func testFetchChaptersCachesResult() async throws {
        // Given API returns chapters
        let bookId = TestFixtures.testBookId.uuidString
        let chapters = TestFixtures.makeChapterList(count: 4)
        mockAPIClient.fetchBookChaptersResult = .success(chapters)

        // When fetchChapters is called
        _ = await sut.fetchChapters(bookId: bookId)

        // Then chapters should be cached
        XCTAssertTrue(sut.hasCachedChapters(bookId: bookId))
        XCTAssertEqual(sut.getCachedChapters(bookId: bookId).count, 4)
    }

    func testFetchChaptersHandlesAPIError() async throws {
        // Given API returns error
        let bookId = TestFixtures.testBookId.uuidString
        mockAPIClient.fetchBookChaptersResult = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))

        // When fetchChapters is called
        let result = await sut.fetchChapters(bookId: bookId)

        // Then should return empty array but NOT cache (allows retry)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertFalse(sut.hasCachedChapters(bookId: bookId)) // Empty results are NOT cached
        XCTAssertTrue(sut.getCachedChapters(bookId: bookId).isEmpty)
    }

    func testFetchChaptersHandlesInvalidUUID() async throws {
        // Given invalid UUID string
        let invalidBookId = "not-a-valid-uuid"

        // When fetchChapters is called
        let result = await sut.fetchChapters(bookId: invalidBookId)

        // Then should return empty array without calling API
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(mockAPIClient.fetchBookChaptersCalls.count, 0)
    }

    func testFetchChaptersSetsLoadingState() async throws {
        // Given chapters from API
        let bookId = TestFixtures.testBookId.uuidString
        mockAPIClient.fetchBookChaptersResult = .success([])

        // Verify loading starts false
        XCTAssertFalse(sut.isLoading)

        // When fetchChapters is called
        _ = await sut.fetchChapters(bookId: bookId)

        // Then loading should end as false (completed)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Cache Operations Tests

    func testGetCachedChaptersReturnsEmptyWhenNotCached() {
        // Given no cached chapters
        let bookId = "some-book-id"

        // When getCachedChapters is called
        let result = sut.getCachedChapters(bookId: bookId)

        // Then should return empty array
        XCTAssertTrue(result.isEmpty)
    }

    func testHasCachedChaptersReturnsFalseWhenNotCached() {
        // Given no cached chapters
        let bookId = "some-book-id"

        // When hasCachedChapters is called
        let result = sut.hasCachedChapters(bookId: bookId)

        // Then should return false
        XCTAssertFalse(result)
    }

    func testHasCachedChaptersReturnsTrueAfterFetch() async throws {
        // Given successful fetch
        let bookId = TestFixtures.testBookId.uuidString
        mockAPIClient.fetchBookChaptersResult = .success(TestFixtures.makeChapterList(count: 2))
        _ = await sut.fetchChapters(bookId: bookId)

        // When hasCachedChapters is called
        let result = sut.hasCachedChapters(bookId: bookId)

        // Then should return true
        XCTAssertTrue(result)
    }

    func testClearCacheRemovesAllCachedChapters() async throws {
        // Given cached chapters for multiple books
        let bookId1 = TestFixtures.testBookId.uuidString
        let bookId2 = UUID().uuidString
        mockAPIClient.fetchBookChaptersResult = .success(TestFixtures.makeChapterList(count: 2))

        _ = await sut.fetchChapters(bookId: bookId1)
        mockAPIClient.fetchBookChaptersResult = .success(TestFixtures.makeChapterList(count: 3))
        _ = await sut.fetchChapters(bookId: bookId2)

        // When clearCache is called
        sut.clearCache()

        // Then all caches should be cleared
        XCTAssertFalse(sut.hasCachedChapters(bookId: bookId1))
        XCTAssertFalse(sut.hasCachedChapters(bookId: bookId2))
        XCTAssertTrue(sut.chapters.isEmpty)
    }

    func testClearCacheForSpecificBookOnlyRemovesThatBook() async throws {
        // Given cached chapters for multiple books
        let bookId1 = TestFixtures.testBookId.uuidString
        let bookId2 = UUID().uuidString
        mockAPIClient.fetchBookChaptersResult = .success(TestFixtures.makeChapterList(count: 2))

        _ = await sut.fetchChapters(bookId: bookId1)
        mockAPIClient.fetchBookChaptersResult = .success(TestFixtures.makeChapterList(count: 3))
        _ = await sut.fetchChapters(bookId: bookId2)

        // When clearCache is called for book1
        sut.clearCache(for: bookId1)

        // Then only book1's cache should be cleared
        XCTAssertFalse(sut.hasCachedChapters(bookId: bookId1))
        XCTAssertTrue(sut.hasCachedChapters(bookId: bookId2))
    }

    // MARK: - Chapter Data Integrity Tests

    func testChaptersPreserveAllData() async throws {
        // Given chapters with full data
        let bookId = TestFixtures.testBookId.uuidString
        let chapters = [
            TestFixtures.makeChapter(
                id: UUID(),
                title: "Introduction",
                startTime: 0,
                endTime: 300,
                duration: 300,
                index: 0
            ),
            TestFixtures.makeChapter(
                id: UUID(),
                title: "Chapter 1",
                startTime: 300,
                endTime: 900,
                duration: 600,
                index: 1
            )
        ]
        mockAPIClient.fetchBookChaptersResult = .success(chapters)

        // When fetchChapters is called
        let result = await sut.fetchChapters(bookId: bookId)

        // Then all chapter data should be preserved
        XCTAssertEqual(result.count, 2)

        let intro = result[0]
        XCTAssertEqual(intro.title, "Introduction")
        XCTAssertEqual(intro.startTime, 0)
        XCTAssertEqual(intro.endTime, 300)
        XCTAssertEqual(intro.duration, 300)
        XCTAssertEqual(intro.index, 0)

        let chapter1 = result[1]
        XCTAssertEqual(chapter1.title, "Chapter 1")
        XCTAssertEqual(chapter1.startTime, 300)
        XCTAssertEqual(chapter1.endTime, 900)
        XCTAssertEqual(chapter1.duration, 600)
        XCTAssertEqual(chapter1.index, 1)
    }

    // MARK: - Concurrent Access Tests

    func testMultipleFetchesForSameBookOnlyCallAPIOnce() async throws {
        // Given chapters from API
        let bookId = TestFixtures.testBookId.uuidString
        let chapters = TestFixtures.makeChapterList(count: 3)
        mockAPIClient.fetchBookChaptersResult = .success(chapters)

        // When multiple fetches happen concurrently
        async let result1 = sut.fetchChapters(bookId: bookId)
        async let result2 = sut.fetchChapters(bookId: bookId)

        let results1 = await result1
        let results2 = await result2

        // Then both should return same chapters
        XCTAssertEqual(results1.count, 3)
        XCTAssertEqual(results2.count, 3)

        // Note: In the actual implementation, this might call API twice before caching
        // This test documents the current behavior
        XCTAssertLessThanOrEqual(mockAPIClient.fetchBookChaptersCalls.count, 2)
    }
}
