//
//  BrowseConfigurations.swift
//  BookVault
//
//  Configuration structs that capture the per-type differences for generic browse views.
//

import SwiftUI

// MARK: - BrowseListConfiguration

/// Configuration for a generic browse list view.
struct BrowseListConfiguration<Item: BrowseListItem, Response: BrowseListResponse> where Response.Item == Item {
    let navigationTitle: String
    let loadingMessage: String
    let errorTitle: String
    let searchPrompt: String
    let emptyIcon: String
    let emptyMessage: String
    let rowIcon: String
    let useCircleIcon: Bool
    let accessibilityHint: String
    let fetch: (SearchManager, Int, Int) async throws -> Response
    let destination: (String) -> AnyView
}

// MARK: - BrowseDetailConfiguration

/// Configuration for a generic browse detail view.
struct BrowseDetailConfiguration<Detail: BrowseDetailResponse> {
    let navigationTitle: String
    let loadingMessage: String
    let errorTitle: String
    let headerIcon: String
    let emptyBooksMessage: String
    let fetch: (SearchManager, String) async throws -> Detail
}

// MARK: - List Configuration Factories

extension BrowseListConfiguration where Item == AuthorWithBookCount, Response == ListAuthors200Response {
    static func authors() -> Self {
        BrowseListConfiguration(
            navigationTitle: "Authors",
            loadingMessage: "Loading authors...",
            errorTitle: "Failed to Load Authors",
            searchPrompt: "Filter authors",
            emptyIcon: "person.fill",
            emptyMessage: "There are no authors in your library",
            rowIcon: "person.fill",
            useCircleIcon: true,
            accessibilityHint: "Tap to view books by this author",
            fetch: { manager, page, limit in
                try await manager.fetchAuthors(page: page, limit: limit)
            },
            destination: { id in AnyView(AuthorDetailView(authorId: id)) }
        )
    }
}

extension BrowseListConfiguration where Item == NarratorWithBookCount, Response == ListNarrators200Response {
    static func narrators() -> Self {
        BrowseListConfiguration(
            navigationTitle: "Narrators",
            loadingMessage: "Loading narrators...",
            errorTitle: "Failed to Load Narrators",
            searchPrompt: "Filter narrators",
            emptyIcon: "mic.fill",
            emptyMessage: "There are no narrators in your library",
            rowIcon: "mic.fill",
            useCircleIcon: true,
            accessibilityHint: "Tap to view books narrated by this narrator",
            fetch: { manager, page, limit in
                try await manager.fetchNarrators(page: page, limit: limit)
            },
            destination: { id in AnyView(NarratorDetailView(narratorId: id)) }
        )
    }
}

extension BrowseListConfiguration where Item == CategoryWithBookCount, Response == ListCategories200Response {
    static func categories() -> Self {
        BrowseListConfiguration(
            navigationTitle: "Categories",
            loadingMessage: "Loading categories...",
            errorTitle: "Failed to Load Categories",
            searchPrompt: "Filter categories",
            emptyIcon: "tag.fill",
            emptyMessage: "There are no categories in your library",
            rowIcon: "tag.fill",
            useCircleIcon: false,
            accessibilityHint: "Tap to view books in this category",
            fetch: { manager, page, limit in
                try await manager.fetchCategories(page: page, limit: limit)
            },
            destination: { id in AnyView(CategoryDetailView(categoryId: id)) }
        )
    }
}

// MARK: - Detail Configuration Factories

extension BrowseDetailConfiguration where Detail == GetAuthor200Response {
    static func author() -> Self {
        BrowseDetailConfiguration(
            navigationTitle: "Author",
            loadingMessage: "Loading author details...",
            errorTitle: "Failed to Load Author",
            headerIcon: "person.circle.fill",
            emptyBooksMessage: "This author doesn't have any books in your library",
            fetch: { manager, id in
                try await manager.fetchAuthorDetail(id: id)
            }
        )
    }
}

extension BrowseDetailConfiguration where Detail == GetAuthor200Response {
    static func narrator() -> Self {
        BrowseDetailConfiguration(
            navigationTitle: "Narrator",
            loadingMessage: "Loading narrator details...",
            errorTitle: "Failed to Load Narrator",
            headerIcon: "mic.circle.fill",
            emptyBooksMessage: "This narrator doesn't have any books in your library",
            fetch: { manager, id in
                try await manager.fetchNarratorDetail(id: id)
            }
        )
    }
}

extension BrowseDetailConfiguration where Detail == GetCategory200Response {
    static func category() -> Self {
        BrowseDetailConfiguration(
            navigationTitle: "Category",
            loadingMessage: "Loading category details...",
            errorTitle: "Failed to Load Category",
            headerIcon: "tag.circle.fill",
            emptyBooksMessage: "This category doesn't have any books in your library",
            fetch: { manager, id in
                try await manager.fetchCategoryDetail(id: id)
            }
        )
    }
}
