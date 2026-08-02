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

    /// The count the row advertises. Defaults to `bookCount`; categories override it
    /// with their subtree rollup, since a container category has no books of its own
    /// and would otherwise read "0 books".
    var displayBookCount: Int { get }

    /// Whether the row leads to further subdivisions rather than straight to books.
    var indicatesDrillDown: Bool { get }
}

extension BrowseListItem {
    var displaySubtitle: String? { nil }
    var displayBookCount: Int { bookCount }
    var indicatesDrillDown: Bool { false }
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
    /// those rows are indistinguishable. Empty in the roots listing, where every
    /// name is top-level and therefore already unique.
    var displaySubtitle: String? {
        guard let parentPath, !parentPath.isEmpty else { return nil }
        return parentPath.joined(separator: " › ")
    }

    /// Prefer the subtree rollup: 15 of 16 top-level categories have no books of
    /// their own, so `bookCount` would read "0 books" on nearly every row. Falls back
    /// to the direct count when the server omits the rollup (flat listing, or an
    /// older server).
    var displayBookCount: Int { totalBookCount ?? bookCount }

    var indicatesDrillDown: Bool { hasChildren ?? false }
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

// MARK: - Hierarchy

/// A detail response that sits in a tree and can be drilled into.
///
/// Only categories conform: Audible ships each book's genre as a full ladder, so
/// categories nest while authors, narrators and series are flat. Keeping this
/// separate from `BrowseDetailResponse` means the generic detail view renders the
/// hierarchy strip for categories and is unchanged for everything else.
protocol BrowseHierarchyDetail: BrowseDetailResponse {
    /// Root-to-immediate-parent, excluding self. Empty at a root.
    var breadcrumb: [CategoryRef] { get }
    /// Immediate children to drill into. Empty at a leaf.
    var childCategories: [CategorySummary] { get }
    /// Distinct books here or anywhere below, vs `books` which is one page of
    /// those tagged directly.
    var subtreeBookCount: Int { get }
}

extension GetCategory200Response: BrowseHierarchyDetail {
    var breadcrumb: [CategoryRef] { ancestors ?? [] }
    var childCategories: [CategorySummary] { subcategories ?? [] }
    /// Falls back to the page total when the server omits the rollup, so an older
    /// build talking to a newer server never shows a smaller number than it lists.
    var subtreeBookCount: Int { totalBookCount ?? pagination.total }
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
