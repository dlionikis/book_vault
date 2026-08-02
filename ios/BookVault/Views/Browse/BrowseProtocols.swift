//
//  BrowseProtocols.swift
//  BookVault
//
//  Protocols that normalize generated API types for use in generic browse views.
//

import Foundation

// MARK: - BrowseListItem

/// Normalizes list item types (AuthorWithBookCount, etc.) so generic views
/// can access a display name regardless of whether the model uses `.name` or `.title`.
protocol BrowseListItem: Identifiable, Hashable, Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var bookCount: Int { get }

    /// Optional disambiguating line shown under the name (e.g. a category's
    /// ancestor path). Nil for types where the name alone is unambiguous.
    var displaySubtitle: String? { get }
}

extension BrowseListItem {
    var displaySubtitle: String? { nil }
}

// MARK: - BrowseDetailResponse

/// Normalizes detail response types (GetAuthor200Response, etc.).
protocol BrowseDetailResponse: Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var books: [Book] { get }
}

// MARK: - BrowseListResponse

/// Normalizes paginated list responses, bridging the two different pagination types
/// (`Pagination` vs `ListBooks200ResponsePagination`) behind a single interface.
protocol BrowseListResponse: Sendable {
    associatedtype Item: BrowseListItem
    var results: [Item] { get }
    var paginationPages: Int { get }
    var paginationTotal: Int { get }
}

// MARK: - List Item Conformances

extension AuthorWithBookCount: BrowseListItem {
    var displayName: String { name }
}

extension NarratorWithBookCount: BrowseListItem {
    var displayName: String { name }
}

extension SeriesWithBookCount: BrowseListItem {
    var displayName: String { title }
}

extension CategoryWithBookCount: BrowseListItem {
    var displayName: String { name }

    /// Category names are unique only per-parent, so the same name can appear
    /// several times in this list under different ancestries. Without the path
    /// those rows are indistinguishable.
    var displaySubtitle: String? {
        guard let parentPath, !parentPath.isEmpty else { return nil }
        return parentPath.joined(separator: " › ")
    }
}

// MARK: - Detail Response Conformances

extension GetAuthor200Response: BrowseDetailResponse {
    var displayName: String { name }
}

// Note: Narrator detail uses GetAuthor200Response (same shape: id, name, asin, books, pagination)
extension GetSeries200Response: BrowseDetailResponse {
    var displayName: String { title }
}

extension GetCategory200Response: BrowseDetailResponse {
    var displayName: String { name }
}

// MARK: - List Response Conformances

extension ListAuthors200Response: BrowseListResponse {
    var paginationPages: Int { pagination.pages }
    var paginationTotal: Int { pagination.total }
}

extension ListNarrators200Response: BrowseListResponse {
    var paginationPages: Int { pagination.pages }
    var paginationTotal: Int { pagination.total }
}

extension ListSeries200Response: BrowseListResponse {
    var paginationPages: Int { pagination.pages }
    var paginationTotal: Int { pagination.total }
}

extension ListCategories200Response: BrowseListResponse {
    var paginationPages: Int { pagination.pages }
    var paginationTotal: Int { pagination.total }
}
