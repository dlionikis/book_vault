//
//  LibraryCacheManagerTests.swift
//  BookVaultTests
//
//  Tests for LibraryCacheManager functionality.
//  Phase 5: Offline Mode Tests
//

import XCTest
@testable import BookVault

@MainActor
final class LibraryCacheManagerTests: XCTestCase {

    var sut: MockLibraryCacheManager!

    override func setUp() {
        super.setUp()
        sut = MockLibraryCacheManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Save Library Tests

    func testSaveLibraryStoresBooks() {
        // Given list of books
        let books = [
            TestFixtures.makeLibraryBook(id: UUID(), title: "Book 1"),
            TestFixtures.makeLibraryBook(id: UUID(), title: "Book 2"),
            TestFixtures.makeLibraryBook(id: UUID(), title: "Book 3")
        ]

        // When saveLibrary is called
        sut.saveLibrary(books: books)

        // Then books should be retrievable
        let cached = sut.loadLibrary()
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.count, 3)
    }

    func testSaveLibraryUpdatesCacheTimestamp() {
        // Given list of books
        let books = [TestFixtures.makeLibraryBook()]
        let beforeSave = Date()

        // When saveLibrary is called
        sut.saveLibrary(books: books)

        // Then cache timestamp should be updated
        let timestamp = sut.getLastSyncDate()
        XCTAssertNotNil(timestamp)
        XCTAssertGreaterThanOrEqual(timestamp!, beforeSave)
    }

    func testSaveLibraryTracksCalls() {
        // Given two sets of books
        let books1 = [TestFixtures.makeLibraryBook(id: UUID(), title: "Book 1")]
        let books2 = [TestFixtures.makeLibraryBook(id: UUID(), title: "Book 2")]

        // When saveLibrary is called twice
        sut.saveLibrary(books: books1)
        sut.saveLibrary(books: books2)

        // Then calls should be tracked
        XCTAssertEqual(sut.saveLibraryCalls.count, 2)
        XCTAssertEqual(sut.saveLibraryCalls[0].count, 1)
        XCTAssertEqual(sut.saveLibraryCalls[1].count, 1)
    }

    func testSaveLibraryOverwritesPreviousCache() {
        // Given existing cached books
        let oldBooks = [
            TestFixtures.makeLibraryBook(id: UUID(), title: "Old Book 1"),
            TestFixtures.makeLibraryBook(id: UUID(), title: "Old Book 2")
        ]
        sut.saveLibrary(books: oldBooks)

        // When saving new books
        let newBooks = [TestFixtures.makeLibraryBook(id: UUID(), title: "New Book")]
        sut.saveLibrary(books: newBooks)

        // Then cache should contain only new books
        let cached = sut.loadLibrary()
        XCTAssertEqual(cached?.count, 1)
        XCTAssertEqual(cached?.first?.title, "New Book")
    }

    // MARK: - Load Library Tests

    func testLoadLibraryReturnsNilWhenEmpty() {
        // Given empty cache
        // When loadLibrary is called
        let result = sut.loadLibrary()

        // Then should return nil
        XCTAssertNil(result)
    }

    func testLoadLibraryReturnsCachedBooks() {
        // Given cached books
        let books = [
            TestFixtures.makeLibraryBook(id: UUID(), title: "Cached Book 1"),
            TestFixtures.makeLibraryBook(id: UUID(), title: "Cached Book 2")
        ]
        sut.preloadCache(books: books)

        // When loadLibrary is called
        let result = sut.loadLibrary()

        // Then should return cached books
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 2)
    }

    func testLoadLibraryReturnsNilWhenLoadFails() {
        // Given cache that should fail to load
        sut.preloadCache(books: [TestFixtures.makeLibraryBook()])
        sut.loadShouldFail = true

        // When loadLibrary is called
        let result = sut.loadLibrary()

        // Then should return nil
        XCTAssertNil(result)
    }

    func testLoadLibraryTracksCalls() {
        // When loadLibrary is called multiple times
        _ = sut.loadLibrary()
        _ = sut.loadLibrary()
        _ = sut.loadLibrary()

        // Then calls should be tracked
        XCTAssertEqual(sut.loadLibraryCalls, 3)
    }

    // MARK: - Cache Validity Tests

    func testIsCacheValidReturnsTrueWhenFresh() {
        // Given recently cached data
        sut.preloadCache(books: [TestFixtures.makeLibraryBook()])

        // When isCacheValid is checked
        let isValid = sut.isCacheValid()

        // Then should return true
        XCTAssertTrue(isValid)
    }

    func testIsCacheValidReturnsFalseWhenEmpty() {
        // Given empty cache
        // When isCacheValid is checked
        let isValid = sut.isCacheValid()

        // Then should return false
        XCTAssertFalse(isValid)
    }

    func testIsCacheValidReturnsFalseWhenConfigured() {
        // Given cache configured to be invalid
        sut.preloadCache(books: [TestFixtures.makeLibraryBook()])
        sut.shouldCacheBeValid = false

        // When isCacheValid is checked
        let isValid = sut.isCacheValid()

        // Then should return false
        XCTAssertFalse(isValid)
    }

    func testIsCacheValidTracksCalls() {
        // When isCacheValid is called multiple times
        _ = sut.isCacheValid()
        _ = sut.isCacheValid()

        // Then calls should be tracked
        XCTAssertEqual(sut.isCacheValidCalls, 2)
    }

    // MARK: - Get Last Sync Date Tests

    func testGetLastSyncDateReturnsNilWhenEmpty() {
        // Given empty cache
        // When getLastSyncDate is called
        let date = sut.getLastSyncDate()

        // Then should return nil
        XCTAssertNil(date)
    }

    func testGetLastSyncDateReturnsCacheTimestamp() {
        // Given cache with known timestamp
        let syncDate = Date().addingTimeInterval(-3600) // 1 hour ago
        sut.preloadCache(books: [TestFixtures.makeLibraryBook()], syncDate: syncDate)

        // When getLastSyncDate is called
        let date = sut.getLastSyncDate()

        // Then should return the timestamp
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, syncDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testGetLastSyncDateTracksCalls() {
        // When getLastSyncDate is called multiple times
        _ = sut.getLastSyncDate()
        _ = sut.getLastSyncDate()
        _ = sut.getLastSyncDate()

        // Then calls should be tracked
        XCTAssertEqual(sut.getLastSyncDateCalls, 3)
    }

    // MARK: - Clear Cache Tests

    func testClearCacheRemovesAllData() {
        // Given cached library
        sut.preloadCache(books: [TestFixtures.makeLibraryBook(), TestFixtures.makeLibraryBook()])

        // When clearCache is called
        sut.clearCache()

        // Then cache should be empty
        XCTAssertNil(sut.loadLibrary())
        XCTAssertNil(sut.getLastSyncDate())
        XCTAssertTrue(sut.clearCacheCalled)
    }

    // MARK: - Test Helper Tests

    func testPreloadCacheSetsData() {
        // Given books and date
        let books = [TestFixtures.makeLibraryBook(title: "Preloaded Book")]
        let syncDate = Date().addingTimeInterval(-7200)

        // When preloadCache is called
        sut.preloadCache(books: books, syncDate: syncDate)

        // Then cache should contain the data
        XCTAssertEqual(sut.cachedBooks?.count, 1)
        XCTAssertEqual(sut.cachedBooks?.first?.title, "Preloaded Book")
        XCTAssertNotNil(sut.cacheTimestamp)
        XCTAssertEqual(sut.cacheTimestamp!.timeIntervalSince1970, syncDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testSimulateStaleCacheSetsOldTimestamp() {
        // Given books and age
        let books = [TestFixtures.makeLibraryBook()]
        let age: TimeInterval = 7200 // 2 hours

        // When simulateStaleCache is called
        sut.simulateStaleCache(books: books, age: age)

        // Then timestamp should be old
        let expectedDate = Date().addingTimeInterval(-age)
        XCTAssertNotNil(sut.cacheTimestamp)
        XCTAssertEqual(sut.cacheTimestamp?.timeIntervalSince1970 ?? 0, expectedDate.timeIntervalSince1970, accuracy: 5.0)
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() {
        // Given state
        sut.preloadCache(books: [TestFixtures.makeLibraryBook()])
        sut.saveLibrary(books: [TestFixtures.makeLibraryBook()])
        _ = sut.loadLibrary()
        _ = sut.isCacheValid()
        _ = sut.getLastSyncDate()
        sut.clearCache()
        sut.shouldCacheBeValid = false
        sut.loadShouldFail = true

        // When resetting
        sut.reset()

        // Then all state should be cleared
        XCTAssertNil(sut.cachedBooks)
        XCTAssertNil(sut.cacheTimestamp)
        XCTAssertTrue(sut.saveLibraryCalls.isEmpty)
        XCTAssertEqual(sut.loadLibraryCalls, 0)
        XCTAssertEqual(sut.isCacheValidCalls, 0)
        XCTAssertEqual(sut.getLastSyncDateCalls, 0)
        XCTAssertFalse(sut.clearCacheCalled)
        XCTAssertTrue(sut.shouldCacheBeValid)
        XCTAssertFalse(sut.loadShouldFail)
    }
}
