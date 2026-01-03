//
//  SearchView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - SearchView

/// Main search screen with autocomplete suggestions and results
struct SearchView: View {
    @StateObject private var searchManager = SearchManager.shared
    @State private var searchText = ""
    @State private var suggestions: GetSearchSuggestions200Response?
    @State private var searchResults: SearchAll200Response?
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var errorMessage: String?
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search audiobooks...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFieldFocused)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit {
                                performSearch()
                            }
                            .onChange(of: searchText) { _, newValue in
                                handleSearchTextChange(newValue)
                            }
                            .accessibilityLabel("Search audiobooks")

                        if !searchText.isEmpty {
                            Button {
                                clearSearch()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    if isSearching {
                        Button("Cancel") {
                            clearSearch()
                            isSearchFieldFocused = false
                        }
                    }
                }
                .padding()

                Divider()

                // Content area
                ScrollView {
                    if isLoading, searchResults == nil {
                        // Loading state
                        ProgressView("Searching...")
                            .padding(.top, 100)
                            .accessibilityLabel("Searching for books")
                    } else if let error = errorMessage {
                        // Error state
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)

                            Text("Search Error")
                                .font(.headline)

                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button("Try Again") {
                                performSearch()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else if let results = searchResults {
                        // Search results
                        searchResultsView(results)
                    } else if !searchText.isEmpty, let suggestions {
                        // Suggestions while typing
                        suggestionsView(suggestions)
                    } else {
                        // Empty state
                        emptyStateView
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Auto-focus search field when view appears
            // Use a small delay to ensure the view is fully loaded and keyboard appears reliably
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }

    // MARK: - Suggestions View

    @ViewBuilder
    private func suggestionsView(_ suggestions: GetSearchSuggestions200Response) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Books suggestions
            if !suggestions.books.isEmpty {
                suggestionSection(
                    title: "Books",
                    icon: "book.fill",
                    items: suggestions.books,
                    itemText: { $0.title },
                    destination: { BookDetailLoader(bookId: $0.id.uuidString) }
                )
            }

            // Authors suggestions
            if !suggestions.authors.isEmpty {
                suggestionSection(
                    title: "Authors",
                    icon: "person.fill",
                    items: suggestions.authors,
                    itemText: { $0.name },
                    destination: { AuthorDetailView(authorId: $0.id.uuidString) }
                )
            }

            // Narrators suggestions
            if !suggestions.narrators.isEmpty {
                suggestionSection(
                    title: "Narrators",
                    icon: "mic.fill",
                    items: suggestions.narrators,
                    itemText: { $0.name },
                    destination: { NarratorDetailView(narratorId: $0.id.uuidString) }
                )
            }
        }
        .padding(.vertical)
    }

    /// Generic suggestion section component
    @ViewBuilder
    private func suggestionSection<Item: Identifiable>(
        title: String,
        icon: String,
        items: [Item],
        itemText: @escaping (Item) -> String,
        destination: @escaping (Item) -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)

            ForEach(items) { item in
                NavigationLink(destination: destination(item)) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        Text(itemText(item))
                            .font(.body)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title.dropLast()): \(itemText(item))")
            }
        }
    }

    // MARK: - Search Results View

    @ViewBuilder
    private func searchResultsView(_ results: SearchAll200Response) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if results.results.isEmpty {
                // No results
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Books Found")
                        .font(.headline)

                    Text("No results found for '\(searchText)'")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(results.pagination.total) results for '\(searchText)'")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(results.results, id: \.id) { book in
                            NavigationLink(destination: BookDetailView(book: book)) {
                                BookGridItem(book: book)
                            }
                            .buttonStyle(.plain)
                        }

                        // Load more indicator
                        if results.pagination.page < results.pagination.pages {
                            ProgressView()
                                .gridCellColumns(columns.count)
                                .onAppear {
                                    loadMoreResults()
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
    }

    // MARK: - Empty State View

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Search Your Library")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Find books by title, author, narrator, or series")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Text("Browse by category:")
                    .font(.headline)

                NavigationLink(destination: AuthorListView()) {
                    browseShortcut(icon: "person.fill", title: "Authors")
                }

                NavigationLink(destination: SeriesListView()) {
                    browseShortcut(icon: "books.vertical.fill", title: "Series")
                }

                NavigationLink(destination: NarratorListView()) {
                    browseShortcut(icon: "mic.fill", title: "Narrators")
                }

                NavigationLink(destination: CategoryListView()) {
                    browseShortcut(icon: "tag.fill", title: "Categories")
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private func browseShortcut(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(title)
                .font(.body)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Search Actions

    /// Handles changes to the search text (for suggestions)
    private func handleSearchTextChange(_ newValue: String) {
        isSearching = !newValue.isEmpty

        // Clear results when text changes
        searchResults = nil
        errorMessage = nil

        // Don't fetch suggestions if text is empty
        guard !newValue.isEmpty else {
            suggestions = nil
            return
        }

        // Fetch suggestions with debouncing
        Task {
            do {
                let result = try await searchManager.getSearchSuggestions(query: newValue)
                // Only update if the search text hasn't changed
                if searchText == newValue {
                    suggestions = result
                }
            } catch is CancellationError {
                // Ignore cancellation errors from debouncing
            } catch let error as APIError {
                // Silently ignore 400 errors (query too short) - this is expected during typing
                if case .serverError(400, _) = error {
                    // Clear suggestions when query is too short
                    if searchText == newValue {
                        suggestions = nil
                    }
                } else {
                    DebugLogger.error("Failed to fetch suggestions", error: error)
                }
            } catch {
                DebugLogger.error("Failed to fetch suggestions", error: error)
            }
        }
    }

    /// Performs a full search
    private func performSearch() {
        // Trim and validate search text
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespaces)
        guard trimmedQuery.count >= 2 else {
            // Don't perform search if query is too short
            return
        }

        isLoading = true
        errorMessage = nil
        suggestions = nil // Clear suggestions when performing full search
        currentPage = 1

        Task {
            do {
                let result = try await searchManager.search(query: trimmedQuery, page: currentPage)
                searchResults = result
                isSearchFieldFocused = false // Dismiss keyboard
            } catch {
                DebugLogger.error("Search failed", error: error)
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    /// Loads more search results (pagination)
    private func loadMoreResults() {
        guard let results = searchResults,
              results.pagination.page < results.pagination.pages,
              !isLoading
        else {
            return
        }

        isLoading = true
        currentPage += 1

        Task {
            do {
                let moreResults = try await searchManager.search(query: searchText, page: currentPage)

                // Append new results to existing ones
                var updatedResults = results
                updatedResults.results.append(contentsOf: moreResults.results)
                updatedResults.pagination = moreResults.pagination

                searchResults = updatedResults
            } catch {
                DebugLogger.error("Failed to load more results", error: error)
                // Don't show error for pagination failures, just stop loading
            }

            isLoading = false
        }
    }

    /// Clears the search
    private func clearSearch() {
        searchText = ""
        searchResults = nil
        suggestions = nil
        errorMessage = nil
        isSearching = false
        currentPage = 1
    }
}

// MARK: - SearchView_Previews

// periphery:ignore - Used by Xcode Previews
struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Empty state
            SearchView()
                .previewDisplayName("Search View (Empty)")

            // Dark mode
            SearchView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Search View (Dark)")
        }
    }
}
