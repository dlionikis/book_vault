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

    private let apiClient: any APIClientProtocol
    private var chapterCache: [String: [Chapter]] = [:] // bookId -> chapters

    // MARK: - Initialization

    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Fetch chapters for a specific book
    /// - Parameter bookId: The book ID (UUID string)
    /// - Returns: Array of chapters (empty if none available)
    func fetchChapters(bookId: String) async -> [Chapter] {
        // Check cache first - only return if we have actual chapters cached
        // Empty arrays are not cached to allow retry when chapters become available
        if let cached = chapterCache[bookId], !cached.isEmpty {
            self.chapters = cached
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Convert bookId string to UUID
            guard let uuid = UUID(uuidString: bookId) else {
                print("⚠️ ChapterManager: Invalid UUID format for bookId: \(bookId)")
                self.chapters = []
                return []
            }

            print("📖 ChapterManager: Fetching chapters for book \(bookId)...")
            let fetchedChapters = try await apiClient.fetchBookChapters(bookId: uuid)
            print("📖 ChapterManager: Received \(fetchedChapters.count) chapters")

            // Only cache if we got chapters - don't cache empty results
            // This allows retry when chapters become available on the server
            if !fetchedChapters.isEmpty {
                chapterCache[bookId] = fetchedChapters
            }
            self.chapters = fetchedChapters

            return fetchedChapters
        } catch {
            // Silent failure - chapters are optional
            print("⚠️ ChapterManager: Failed to fetch chapters for book \(bookId): \(error.localizedDescription)")
            print("⚠️ ChapterManager: Error details: \(error)")

            // Don't cache failures - allow retry next time
            self.chapters = []

            return []
        }
    }

    /// Get chapters from cache (synchronous)
    /// - Parameter bookId: The book ID
    /// - Returns: Cached chapters or empty array
    func getCachedChapters(bookId: String) -> [Chapter] {
        chapterCache[bookId] ?? []
    }

    /// Check if chapters are cached for a book
    /// - Parameter bookId: The book ID
    /// - Returns: True if chapters are in cache
    func hasCachedChapters(bookId: String) -> Bool {
        chapterCache[bookId] != nil
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
