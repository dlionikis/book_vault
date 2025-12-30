//
//  MockLibraryCacheManager.swift
//  BookVaultTests
//
//  Mock LibraryCacheManager for testing - simulates library cache operations.
//  Phase 5: Offline Mode Tests
//

import Foundation
@testable import BookVault

/// Mock library cache manager for testing
@MainActor
class MockLibraryCacheManager: LibraryCaching {

    // MARK: - In-Memory Storage

    var cachedBooks: [LibraryBook]?
    var cacheTimestamp: Date?
    var simulatedUserId: String?

    // MARK: - Call Tracking

    var saveLibraryCalls: [[LibraryBook]] = []
    var loadLibraryCalls: Int = 0
    var isCacheValidCalls: Int = 0
    var getLastSyncDateCalls: Int = 0
    var clearCacheCalled: Bool = false

    // MARK: - Behavior Configuration

    var shouldCacheBeValid: Bool = true
    var loadShouldFail: Bool = false

    // MARK: - Protocol Implementation

    func saveLibrary(books: [LibraryBook]) {
        saveLibraryCalls.append(books)
        cachedBooks = books
        cacheTimestamp = Date()
    }

    func loadLibrary() -> [LibraryBook]? {
        loadLibraryCalls += 1

        if loadShouldFail {
            return nil
        }

        return cachedBooks
    }

    func isCacheValid() -> Bool {
        isCacheValidCalls += 1

        if !shouldCacheBeValid {
            return false
        }

        return cachedBooks != nil
    }

    func getLastSyncDate() -> Date? {
        getLastSyncDateCalls += 1
        return cacheTimestamp
    }

    func clearCache() {
        clearCacheCalled = true
        cachedBooks = nil
        cacheTimestamp = nil
    }

    // MARK: - Test Helpers

    /// Pre-populate cache with library books
    func preloadCache(books: [LibraryBook], syncDate: Date = Date()) {
        cachedBooks = books
        cacheTimestamp = syncDate
    }

    /// Simulate stale cache by setting old timestamp
    func simulateStaleCache(books: [LibraryBook], age: TimeInterval = 3600) {
        cachedBooks = books
        cacheTimestamp = Date().addingTimeInterval(-age)
    }

    // MARK: - Reset

    func reset() {
        cachedBooks = nil
        cacheTimestamp = nil
        simulatedUserId = nil
        saveLibraryCalls = []
        loadLibraryCalls = 0
        isCacheValidCalls = 0
        getLastSyncDateCalls = 0
        clearCacheCalled = false
        shouldCacheBeValid = true
        loadShouldFail = false
    }
}
