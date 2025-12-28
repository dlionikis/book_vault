//
//  ChapterManager.swift
//  BookVault
//
//  Created by Claude on 2025-12-28.
//  Phase 5: Chapter Navigation
//

import Foundation

/// Manages fetching and caching of audiobook chapters
@MainActor
class ChapterManager: ObservableObject {
    // MARK: - Published Properties

    @Published var chapters: [Chapter] = []
    @Published var isLoading: Bool = false

    // MARK: - Private Properties

    private let apiClient: APIClient
    private var chapterCache: [String: [Chapter]] = [:] // bookId -> chapters

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Fetch chapters for a specific book
    /// - Parameter bookId: The book ID (UUID string)
    /// - Returns: Array of chapters (empty if none available)
    func fetchChapters(bookId: String) async -> [Chapter] {
        // Check cache first
        if let cached = chapterCache[bookId] {
            self.chapters = cached
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Convert bookId string to UUID
            guard let uuid = UUID(uuidString: bookId) else {
                print("⚠️ ChapterManager: Invalid UUID format for bookId: \(bookId)")
                chapterCache[bookId] = []
                self.chapters = []
                return []
            }

            print("📖 ChapterManager: Fetching chapters for book \(bookId)...")
            let fetchedChapters = try await apiClient.fetchBookChapters(bookId: uuid)
            print("📖 ChapterManager: Received \(fetchedChapters.count) chapters")

            // Cache the chapters
            chapterCache[bookId] = fetchedChapters
            self.chapters = fetchedChapters

            return fetchedChapters
        } catch {
            // Silent failure - chapters are optional
            print("⚠️ ChapterManager: Failed to fetch chapters for book \(bookId): \(error.localizedDescription)")
            print("⚠️ ChapterManager: Error details: \(error)")

            // Cache empty array to avoid repeated failed requests
            chapterCache[bookId] = []
            self.chapters = []

            return []
        }
    }

    /// Get chapters from cache (synchronous)
    /// - Parameter bookId: The book ID
    /// - Returns: Cached chapters or empty array
    func getCachedChapters(bookId: String) -> [Chapter] {
        return chapterCache[bookId] ?? []
    }

    /// Check if chapters are cached for a book
    /// - Parameter bookId: The book ID
    /// - Returns: True if chapters are in cache
    func hasCachedChapters(bookId: String) -> Bool {
        return chapterCache[bookId] != nil
    }

    /// Clear all cached chapters
    func clearCache() {
        chapterCache.removeAll()
        chapters = []
    }

    /// Clear cache for a specific book
    /// - Parameter bookId: The book ID to clear
    func clearCache(for bookId: String) {
        chapterCache.removeValue(forKey: bookId)
        if chapters.first?.id.uuidString == bookId {
            chapters = []
        }
    }
}
