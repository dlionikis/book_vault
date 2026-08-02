//
//  SearchManager.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import Foundation
import UIKit

// MARK: - CacheEntry

/// Cache entry for storing cached search/browse results
private struct CacheEntry<T> {
    let data: T
    let timestamp: Date
    let ttl: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}

// MARK: - SearchManager

/// Manages search and browse functionality with caching and debouncing
@MainActor
class SearchManager: ObservableObject {
    static let shared = SearchManager()

    private let apiClient = APIClient.shared

    // MARK: - Cache Storage

    /// Cache for search results (key: "query_page", TTL: 5 minutes)
    private var searchCache: [String: CacheEntry<SearchAll200Response>] = [:]

    /// Cache for search suggestions (key: query, TTL: 5 minutes)
    private var suggestionsCache: [String: CacheEntry<GetSearchSuggestions200Response>] = [:]

    /// Cache for browse lists (key: "type_page", TTL: 10 minutes)
    private var browseListCache: [String: Any] = [:]

    /// Cache for detail pages (key: "type_id", TTL: 10 minutes)
    private var detailCache: [String: Any] = [:]

    // MARK: - Cache TTL Constants

    private let searchCacheTTL: TimeInterval = 300 // 5 minutes
    private let browseCacheTTL: TimeInterval = 600 // 10 minutes

    // MARK: - Debouncing

    /// Debounce task for search suggestions
    private var suggestionDebounceTask: Task<Void, Never>?
    private let suggestionDebounceDelay: TimeInterval = 0.3 // 300ms

    private init() {
        // Listen for memory warnings to clear cache
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleMemoryWarning() {
        DebugLogger.info("Memory warning received - clearing search cache")
        clearAllCaches()
    }

    // MARK: - Cache Management

    /// Clears all caches (call on logout or memory warning)
    func clearAllCaches() {
        searchCache.removeAll()
        suggestionsCache.removeAll()
        browseListCache.removeAll()
        detailCache.removeAll()
        DebugLogger.info("All search/browse caches cleared")
    }

    /// Clears only search-related caches
    func clearSearchCache() {
        searchCache.removeAll()
        suggestionsCache.removeAll()
        DebugLogger.info("Search caches cleared")
    }

    // MARK: - JSON Decoding

    /// Creates a configured JSONDecoder with custom date handling
    private func createDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with time first (e.g., "2025-07-22T00:00:00Z")
            let iso8601Formatter = ISO8601DateFormatter()
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try date-only format (e.g., "2025-07-22")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }
        return decoder
    }

    // MARK: - Search

    /// Performs a full-text search with pagination
    /// - Parameters:
    ///   - query: Search query string
    ///   - page: Page number (default: 1)
    ///   - limit: Results per page (default: 20)
    /// - Returns: Search results with pagination info
    func search(query: String, page: Int = 1, limit: Int = 20) async throws -> SearchAll200Response {
        // Check cache first (include limit in key to avoid returning wrong page size)
        let cacheKey = "\(query)_\(page)_\(limit)"
        if let cached = searchCache[cacheKey], !cached.isExpired {
            DebugLogger.network("Returning cached search results for: \(query) (page \(page), limit \(limit))")
            return cached.data
        }

        // Build URL with query parameters
        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url(relativeTo: apiClient.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization header
        if let token = apiClient.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        DebugLogger.network("Searching for: \(query) (page \(page), limit \(limit))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, nil)
        }

        // DEBUG: Log raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            DebugLogger.verbose("Raw search JSON response:\n\(jsonString)")
        }

        let decoder = createDecoder()
        let result = try decoder.decode(SearchAll200Response.self, from: data)

        // Cache the result
        searchCache[cacheKey] = CacheEntry(data: result, timestamp: Date(), ttl: searchCacheTTL)

        return result
    }

    /// Gets search suggestions (autocomplete) with debouncing
    /// - Parameter query: Search query string (minimum 1 character)
    /// - Returns: Top 5 book suggestions and top 5 author suggestions
    func getSearchSuggestions(query: String) async throws -> GetSearchSuggestions200Response {
        // Cancel any pending debounce task
        suggestionDebounceTask?.cancel()

        // Wait for debounce delay
        try await Task.sleep(nanoseconds: UInt64(suggestionDebounceDelay * 1_000_000_000))

        // Check if task was cancelled during sleep
        try Task.checkCancellation()

        // Check cache first
        if let cached = suggestionsCache[query], !cached.isExpired {
            DebugLogger.network("Returning cached suggestions for: \(query)")
            return cached.data
        }

        // Build URL with query parameters
        var components = URLComponents()
        components.path = "/api/search/suggestions"
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components.url(relativeTo: apiClient.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization header
        if let token = apiClient.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        DebugLogger.network("Getting suggestions for: \(query)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // DEBUG: Log error response
            if let errorString = String(data: data, encoding: .utf8) {
                DebugLogger.error("Suggestions API error (\(httpResponse.statusCode)): \(errorString)")
            }
            throw APIError.serverError(httpResponse.statusCode, nil)
        }

        // DEBUG: Log raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            DebugLogger.verbose("Raw suggestions JSON response:\n\(jsonString)")
        }

        let decoder = createDecoder()
        let result = try decoder.decode(GetSearchSuggestions200Response.self, from: data)

        // Cache the result
        suggestionsCache[query] = CacheEntry(data: result, timestamp: Date(), ttl: searchCacheTTL)

        return result
    }

    // MARK: - Browse Lists

    /// Fetches list of authors with book counts
    /// - Parameters:
    ///   - page: Page number (default: 1)
    ///   - limit: Results per page (default: 20)
    /// - Returns: List of authors with pagination info
    func fetchAuthors(page: Int = 1, limit: Int = 20) async throws -> ListAuthors200Response {
        try await fetchBrowseList(
            path: "/api/browse/authors",
            page: page,
            limit: limit,
            cachePrefix: "authors"
        )
    }

    /// Fetches list of series with book counts
    ///
    /// Currently unused by the iOS UI: `SeriesListView` was retired in favor of
    /// the Catalog's Books/Series toggle (requirements Q6), which uses
    /// `fetchCatalogSeriesView` instead. Kept as the wrapper for the still-live,
    /// still-spec'd `/api/browse/series` endpoint (web's Browse Series page uses it),
    /// and for parity with the sibling browse-list methods.
    ///
    /// - Parameters:
    ///   - page: Page number (default: 1)
    ///   - limit: Results per page (default: 20)
    /// - Returns: List of series with pagination info
    func fetchSeries(page: Int = 1, limit: Int = 20) async throws -> ListSeries200Response {
        try await fetchBrowseList(
            path: "/api/browse/series",
            page: page,
            limit: limit,
            cachePrefix: "series"
        )
    }

    /// Fetches list of narrators with book counts
    /// - Parameters:
    ///   - page: Page number (default: 1)
    ///   - limit: Results per page (default: 20)
    /// - Returns: List of narrators with pagination info
    func fetchNarrators(page: Int = 1, limit: Int = 20) async throws -> ListNarrators200Response {
        try await fetchBrowseList(
            path: "/api/browse/narrators",
            page: page,
            limit: limit,
            cachePrefix: "narrators"
        )
    }

    /// Fetches list of categories with book counts
    ///
    /// Categories are a hierarchy (Audible ships genres as full ladders), so a flat
    /// list repeats the same name under different ancestries. `roots` asks for the
    /// top level only, with counts rolled up over each subtree, which is what the
    /// browse list shows — drill down via `GetCategory200Response.subcategories`.
    ///
    /// - Parameters:
    ///   - page: Page number (default: 1)
    ///   - limit: Results per page (default: 20)
    ///   - roots: Top-level categories only (default: true)
    /// - Returns: List of categories with pagination info
    func fetchCategories(
        page: Int = 1,
        limit: Int = 20,
        roots: Bool = true
    ) async throws -> ListCategories200Response {
        try await fetchBrowseList(
            path: "/api/browse/categories",
            page: page,
            limit: limit,
            // Distinct cache key: the two modes return different result sets for the
            // same page/limit, so they must not share an entry.
            cachePrefix: roots ? "categories_roots" : "categories",
            extraQueryItems: roots ? [URLQueryItem(name: "roots", value: "true")] : []
        )
    }

    /// Generic method to fetch browse lists with caching
    private func fetchBrowseList<T: Decodable>(
        path: String,
        page: Int,
        limit: Int,
        cachePrefix: String,
        extraQueryItems: [URLQueryItem] = []
    ) async throws -> T {
        // Check cache first (include limit in key to avoid returning wrong page size)
        let cacheKey = "\(cachePrefix)_\(page)_\(limit)"
        if let cached = browseListCache[cacheKey] as? CacheEntry<T>, !cached.isExpired {
            DebugLogger.network("Returning cached \(cachePrefix) list (page \(page), limit \(limit))")
            return cached.data
        }

        // Build URL with query parameters
        var components = URLComponents()
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ] + extraQueryItems

        guard let url = components.url(relativeTo: apiClient.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization header
        if let token = apiClient.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        DebugLogger.network("Fetching \(cachePrefix) list (page \(page), limit \(limit))")
        DebugLogger.verbose("Request URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, nil)
        }

        // DEBUG: Log raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            DebugLogger.verbose("Raw JSON response for \(cachePrefix) list (page \(page)):\n\(jsonString)")
        }

        let decoder = createDecoder()
        let result = try decoder.decode(T.self, from: data)

        // Cache the result
        browseListCache[cacheKey] = CacheEntry(data: result, timestamp: Date(), ttl: browseCacheTTL)

        return result
    }

    // MARK: - Detail Pages

    /// Fetches author details with all their books
    /// - Parameter id: Author ID (UUID)
    /// - Returns: Author details with list of books
    func fetchAuthorDetail(id: String) async throws -> GetAuthor200Response {
        try await fetchDetail(
            path: "/api/authors/\(id)",
            cachePrefix: "author"
        )
    }

    /// Fetches series details with all books in order
    /// - Parameter id: Series ID (UUID)
    /// - Returns: Series details with list of books (ordered by sequence)
    func fetchSeriesDetail(id: String) async throws -> GetSeries200Response {
        try await fetchDetail(
            path: "/api/series/\(id)",
            cachePrefix: "series"
        )
    }

    /// Fetches narrator details with all their books
    /// - Parameter id: Narrator ID (UUID)
    /// - Returns: Narrator details with list of books
    func fetchNarratorDetail(id: String) async throws -> GetAuthor200Response {
        try await fetchDetail(
            path: "/api/narrators/\(id)",
            cachePrefix: "narrator"
        )
    }

    /// Fetches category details with all books in category
    /// - Parameter id: Category ID (UUID)
    /// - Returns: Category details with list of books
    func fetchCategoryDetail(id: String) async throws -> GetCategory200Response {
        try await fetchDetail(
            path: "/api/categories/\(id)",
            cachePrefix: "category"
        )
    }

    /// Generic method to fetch detail pages with caching
    private func fetchDetail<T: Decodable>(
        path: String,
        cachePrefix: String
    ) async throws -> T {
        // Check cache first
        let cacheKey = "\(cachePrefix)_\(path)"
        if let cached = detailCache[cacheKey] as? CacheEntry<T>, !cached.isExpired {
            DebugLogger.network("Returning cached \(cachePrefix) detail")
            return cached.data
        }

        guard let url = URL(string: path, relativeTo: apiClient.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization header
        if let token = apiClient.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        DebugLogger.network("Fetching \(cachePrefix) detail: \(path)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, nil)
        }

        // DEBUG: Log raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            DebugLogger.verbose("Raw JSON response for \(path):\n\(jsonString)")
        } else {
            DebugLogger.warning("Could not convert response data to string for \(path)")
        }

        let decoder = createDecoder()
        let result = try decoder.decode(T.self, from: data)

        // Cache the result
        detailCache[cacheKey] = CacheEntry(data: result, timestamp: Date(), ttl: browseCacheTTL)

        return result
    }
}
