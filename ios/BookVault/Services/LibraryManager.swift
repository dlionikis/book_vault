//
//  LibraryManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 2: Library UX Alignment
//

import Combine
import Foundation

// MARK: - LibraryError

/// Error types for library operations
enum LibraryError: LocalizedError {
    case offlineNoCache

    var errorDescription: String? {
        switch self {
        case .offlineNoCache:
            "You're offline and no cached library is available. Connect to the internet to load your library."
        }
    }
}

// MARK: - LibraryManager

/// Manages user library operations with caching strategy
/// This is a lightweight wrapper around APIClient for library-related operations
@MainActor
class LibraryManager: ObservableObject, LibraryManaging {
    static let shared = LibraryManager()

    @Published var isLoading = false
    @Published var error: Error?

    /// Increments whenever the library is modified (add/remove book)
    /// Observers can watch this to know when to refresh their views
    @Published var libraryVersion: Int = 0

    /// Indicates if current data is from cache (offline mode)
    @Published var isShowingCachedData = false

    // MARK: - Dependencies

    private let apiClient: any APIClientProtocol
    private let libraryCacheManager: any LibraryCaching
    private let coverCacheManager: any CoverCaching
    private let networkMonitor: any NetworkMonitoring
    private let storageManager: any StorageManaging

    // MARK: - Caching

    /// In-memory cache of library books
    private var cachedBooks: [LibraryBook]?

    /// Timestamp of last cache update
    private var lastCacheUpdate: Date?

    /// Cache validity duration (5 minutes)
    private let cacheValidityDuration: TimeInterval = 300

    /// Production singleton initializer
    private convenience init() {
        self.init(
            apiClient: APIClient.shared,
            libraryCacheManager: LibraryCacheManager.shared,
            coverCacheManager: CoverCacheManager.shared,
            networkMonitor: NetworkMonitor.shared,
            storageManager: StorageManager.shared
        )
    }

    /// Testable initializer with dependency injection
    /// - Parameters:
    ///   - apiClient: API client for server communication
    ///   - libraryCacheManager: Library cache for offline access
    ///   - coverCacheManager: Cover image cache
    ///   - networkMonitor: Network connectivity monitor
    ///   - storageManager: Storage manager for download deletion
    init(
        apiClient: any APIClientProtocol,
        libraryCacheManager: any LibraryCaching,
        coverCacheManager: any CoverCaching,
        networkMonitor: any NetworkMonitoring,
        storageManager: any StorageManaging
    ) {
        self.apiClient = apiClient
        self.libraryCacheManager = libraryCacheManager
        self.coverCacheManager = coverCacheManager
        self.networkMonitor = networkMonitor
        self.storageManager = storageManager
    }

    // MARK: - Public API

    /// Fetch user's library books
    /// Uses cached data if available and fresh, otherwise fetches from API
    /// When offline, returns disk-cached data if available
    /// - Parameter forceRefresh: If true, bypasses cache and fetches from API
    /// - Returns: Array of library books (includes addedAt timestamp)
    @MainActor
    func fetchLibraryBooks(forceRefresh: Bool = false) async throws -> [LibraryBook] {
        // Check network status first
        if !networkMonitor.isConnected {
            // Offline: try to load from disk cache
            if let diskCached = libraryCacheManager.loadLibrary() {
                DebugLogger.database("Using disk-cached library (offline): \(diskCached.count) books")
                isShowingCachedData = true
                cachedBooks = diskCached
                return diskCached
            }
            // No disk cache available while offline
            throw LibraryError.offlineNoCache
        }

        // Online: Check if in-memory cache is valid and not forcing refresh
        if !forceRefresh, let cached = cachedBooks, isCacheValid() {
            DebugLogger.database("Using in-memory cached library books (\(cached.count) books)")
            isShowingCachedData = false
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        DebugLogger.database("Fetching library books from API")

        let response = try await apiClient.fetchLibrary()

        // Update in-memory cache
        cachedBooks = response.books
        lastCacheUpdate = Date()
        isShowingCachedData = false

        // Save to disk cache for offline access
        libraryCacheManager.saveLibrary(books: response.books)

        // Cache cover images in background (don't block return)
        Task.detached(priority: .background) { [coverCacheManager] in
            await self.cacheCoversForBooks(response.books, using: coverCacheManager)
        }

        DebugLogger.success("Fetched \(response.books.count) library books (total: \(response.total))")

        return response.books
    }

    /// Cache cover images for library books in background
    /// - Parameters:
    ///   - books: Array of library books to cache covers for
    ///   - cache: Cover cache manager to use
    private func cacheCoversForBooks(_ books: [LibraryBook], using cache: any CoverCaching) async {
        var cachedCount = 0

        for book in books {
            guard let urlString = book.coverUrl,
                  let url = URL(string: urlString)
            else { continue }

            // Skip if already cached
            if await cache.hasCover(for: book.id) {
                continue
            }

            do {
                try await cache.cacheCover(for: book.id, from: url)
                cachedCount += 1
            } catch {
                // Log but don't fail - cover caching is best-effort
                DebugLogger.warning("Failed to cache cover for \(book.title): \(error.localizedDescription)")
            }
        }

        if cachedCount > 0 {
            DebugLogger.success("Cached \(cachedCount) new cover images")
        }
    }

    /// Add book to user's library
    /// Invalidates cache to ensure fresh data on next fetch
    /// - Parameter bookId: The book's ID string
    @MainActor
    func addToLibrary(bookId: String) async throws {
        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "LibraryManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        isLoading = true
        defer { isLoading = false }

        DebugLogger.database("Adding book to library: \(bookId)")

        let response = try await apiClient.addToLibrary(bookId: uuid)

        DebugLogger.success("Book added to library: \(response.message)")

        // Invalidate cache
        invalidateCache()
    }

    /// Remove book from user's library
    /// Also deletes any local download of the book
    /// Invalidates cache to ensure fresh data on next fetch
    /// - Parameter bookId: The book's ID string
    @MainActor
    func removeFromLibrary(bookId: String) async throws {
        guard let uuid = UUID(uuidString: bookId) else {
            throw NSError(domain: "LibraryManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid book ID format"
            ])
        }

        isLoading = true
        defer { isLoading = false }

        DebugLogger.database("Removing book from library: \(bookId)")

        try await apiClient.removeFromLibrary(bookId: uuid)

        DebugLogger.success("Book removed from library")

        // Delete local download if exists
        if storageManager.isBookDownloaded(bookId: bookId) {
            do {
                try storageManager.deleteDownload(bookId: bookId)
                DebugLogger.success("Deleted local download for removed book")
            } catch {
                DebugLogger.error("Failed to delete local download", error: error)
                // Don't throw - book was removed from library successfully
            }
        }

        // Invalidate cache
        invalidateCache()
    }

    /// Check if a book is in the user's library
    /// Uses cached data if available to minimize API calls
    /// - Parameter bookId: The book's ID string
    /// - Returns: True if book is in library, false otherwise
    @MainActor
    func isInLibrary(bookId: String) async throws -> Bool {
        // Try to use cached data first
        if let cached = cachedBooks, isCacheValid() {
            let isInCache = cached.contains { $0.id.uuidString == bookId }
            DebugLogger.database("Checked library status from cache: \(isInCache)")
            return isInCache
        }

        // If no valid cache, fetch library to update cache
        let books = try await fetchLibraryBooks()
        let isInLibrary = books.contains { $0.id.uuidString == bookId }

        DebugLogger.database("Checked library status from API: \(isInLibrary)")
        return isInLibrary
    }

    /// Add all books in a series to user's library
    /// Note: This requires a series endpoint that may not be implemented yet
    /// - Parameter seriesId: The series ID string
    @MainActor
    func addSeriesToLibrary(seriesId: String) async throws {
        guard let uuid = UUID(uuidString: seriesId) else {
            throw NSError(domain: "LibraryManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid series ID format"
            ])
        }

        isLoading = true
        defer { isLoading = false }

        DebugLogger.database("Adding series to library: \(seriesId)")

        // Create request to add series
        // Note: This assumes the API endpoint exists at /api/library/series
        // If not implemented yet, this will need to be updated
        let request = try createSeriesRequest(seriesId: uuid)

        do {
            let response: AddSeriesToLibrary200Response = try await executeRequest(request)
            DebugLogger
                .success("Series added to library: \(response.message) (\(response.added)/\(response.total) books)")

            // Invalidate cache
            invalidateCache()
        } catch {
            DebugLogger.error("Failed to add series to library", error: error)
            throw error
        }
    }

    // MARK: - Cache Management

    /// Check if cached data is still valid
    private func isCacheValid() -> Bool {
        guard let lastUpdate = lastCacheUpdate else {
            return false
        }

        let elapsed = Date().timeIntervalSince(lastUpdate)
        return elapsed < cacheValidityDuration
    }

    /// Invalidate the cache (called after add/remove operations)
    /// Also increments libraryVersion to notify observers
    @MainActor
    private func invalidateCache() {
        cachedBooks = nil
        lastCacheUpdate = nil
        libraryVersion += 1
        DebugLogger.database("Library cache invalidated (version: \(libraryVersion))")
    }

    /// Force refresh the cache (useful for pull-to-refresh)
    @MainActor
    func refreshCache() async throws {
        DebugLogger.database("Force refreshing library cache")
        _ = try await fetchLibraryBooks(forceRefresh: true)
    }

    // MARK: - Private Helpers

    /// Create a request to add series to library
    /// Note: This is a temporary implementation until the API endpoint is confirmed
    private func createSeriesRequest(seriesId: UUID) throws -> URLRequest {
        guard let url = URL(string: "/api/library/series", relativeTo: apiClient.baseURL) else {
            throw NSError(domain: "LibraryManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization header
        if let token = apiClient.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Create request body
        let body = ["seriesId": seriesId.uuidString]
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }

    /// Execute a URLRequest and decode the response
    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let session = URLSession.shared
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "LibraryManager", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response"
            ])
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "LibraryManager", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"
            ])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }
}
