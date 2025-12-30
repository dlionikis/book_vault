//
//  MockLibraryManager.swift
//  BookVaultTests
//
//  Mock LibraryManager for testing - simulates library operations.
//  Phase 3: DI-Enabled Services
//

import Foundation
@testable import BookVault

/// Mock library manager for testing
@MainActor
class MockLibraryManager: LibraryManaging {

    // MARK: - Published-like Properties (for protocol conformance)

    var isLoading: Bool = false
    var error: Error?
    var libraryVersion: Int = 0
    var isShowingCachedData: Bool = false

    // MARK: - In-Memory Storage

    var libraryBooks: [LibraryBook] = []

    // MARK: - Call Tracking

    var fetchLibraryBooksCalls: [Bool] = []  // forceRefresh values
    var addToLibraryCalls: [String] = []
    var removeFromLibraryCalls: [String] = []
    var isInLibraryCalls: [String] = []
    var refreshCacheCalls: Int = 0

    // MARK: - Behavior Configuration

    var fetchShouldFail: Bool = false
    var fetchError: Error = NSError(domain: "MockLibraryManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
    var addShouldFail: Bool = false
    var removeShouldFail: Bool = false

    // MARK: - Protocol Implementation

    func fetchLibraryBooks(forceRefresh: Bool) async throws -> [LibraryBook] {
        fetchLibraryBooksCalls.append(forceRefresh)

        if fetchShouldFail {
            throw fetchError
        }

        return libraryBooks
    }

    func addToLibrary(bookId: String) async throws {
        addToLibraryCalls.append(bookId)

        if addShouldFail {
            throw NSError(domain: "MockLibraryManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Failed to add to library"
            ])
        }

        libraryVersion += 1
    }

    func removeFromLibrary(bookId: String) async throws {
        removeFromLibraryCalls.append(bookId)

        if removeShouldFail {
            throw NSError(domain: "MockLibraryManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Failed to remove from library"
            ])
        }

        libraryVersion += 1
    }

    func isInLibrary(bookId: String) async throws -> Bool {
        isInLibraryCalls.append(bookId)
        return libraryBooks.contains { $0.id.uuidString == bookId }
    }

    func refreshCache() async throws {
        refreshCacheCalls += 1

        if fetchShouldFail {
            throw fetchError
        }
    }

    // MARK: - Test Helpers

    /// Set up library with test library books
    func setLibrary(_ books: [LibraryBook]) {
        libraryBooks = books
    }

    // MARK: - Reset

    func reset() {
        isLoading = false
        error = nil
        libraryVersion = 0
        isShowingCachedData = false
        libraryBooks = []
        fetchLibraryBooksCalls = []
        addToLibraryCalls = []
        removeFromLibraryCalls = []
        isInLibraryCalls = []
        refreshCacheCalls = 0
        fetchShouldFail = false
        addShouldFail = false
        removeShouldFail = false
    }
}
