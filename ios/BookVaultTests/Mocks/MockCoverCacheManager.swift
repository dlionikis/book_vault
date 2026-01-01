//
//  MockCoverCacheManager.swift
//  BookVaultTests
//
//  Mock implementation of CoverCaching for testing.
//

import Foundation
import UIKit
@testable import BookVault

/// Mock CoverCacheManager for testing
@MainActor
class MockCoverCacheManager: CoverCaching {
    // MARK: - Stored Data

    var cachedCovers: [UUID: UIImage] = [:]
    var coverURLs: [UUID: URL] = [:]

    // MARK: - Call Tracking

    var getCoverCalls = 0
    var hasCoverCalls = 0
    var localCoverURLCalls = 0
    var cacheCoverCalls = 0
    var deleteCoverCalls = 0
    var clearCacheCalls = 0

    // MARK: - Configuration

    var shouldThrowOnCache = false
    var cacheError: Error?

    // MARK: - CoverCaching Protocol

    func getCover(for bookId: UUID) -> UIImage? {
        getCoverCalls += 1
        return cachedCovers[bookId]
    }

    func hasCover(for bookId: UUID) -> Bool {
        hasCoverCalls += 1
        return cachedCovers[bookId] != nil
    }

    func localCoverURL(for bookId: UUID) -> URL? {
        localCoverURLCalls += 1
        return coverURLs[bookId]
    }

    func cacheCover(for bookId: UUID, from url: URL) async throws {
        cacheCoverCalls += 1
        if shouldThrowOnCache {
            throw cacheError ?? NSError(domain: "MockCoverCacheManager", code: 1, userInfo: nil)
        }
        // Simulate caching with a placeholder image
        cachedCovers[bookId] = UIImage()
        coverURLs[bookId] = url
    }

    func deleteCover(for bookId: UUID) {
        deleteCoverCalls += 1
        cachedCovers.removeValue(forKey: bookId)
        coverURLs.removeValue(forKey: bookId)
    }

    func clearCache() {
        clearCacheCalls += 1
        cachedCovers.removeAll()
        coverURLs.removeAll()
    }

    func getCacheCount() -> Int {
        return cachedCovers.count
    }

    func getCacheSize() -> Int64 {
        return Int64(cachedCovers.count * 1024) // Mock size
    }

    // MARK: - Test Helpers

    func reset() {
        cachedCovers.removeAll()
        coverURLs.removeAll()
        getCoverCalls = 0
        hasCoverCalls = 0
        localCoverURLCalls = 0
        cacheCoverCalls = 0
        deleteCoverCalls = 0
        clearCacheCalls = 0
        shouldThrowOnCache = false
        cacheError = nil
    }
}
