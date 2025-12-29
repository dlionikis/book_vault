//
//  CategoryListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

/// List view for browsing all categories alphabetically
struct CategoryListView: View {
    @StateObject private var searchManager = SearchManager.shared
    @State private var categories: [CategoryWithBookCount] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var hasMorePages = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if isLoading && categories.isEmpty {
                ProgressView("Loading categories...")
                    .accessibilityLabel("Loading categories")
            } else if let error = errorMessage, categories.isEmpty {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Categories")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadCategories()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if categories.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Categories Found")
                        .font(.headline)

                    Text("There are no categories in your library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(groupedCategories.keys.sorted(), id: \.self) { letter in
                        Section(header: Text(letter)) {
                            ForEach(groupedCategories[letter] ?? [], id: \.id) { category in
                                NavigationLink(destination: CategoryDetailView(categoryId: category.id.uuidString)) {
                                    categoryRow(category)
                                }
                            }
                        }
                    }

                    // Load more indicator
                    if hasMorePages {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .onAppear {
                            Task {
                                await loadMoreCategories()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Filter categories")
                .refreshable {
                    await refreshCategories()
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadCategories()
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(_ category: CategoryWithBookCount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text("\(category.bookCount) \(category.bookCount == 1 ? "book" : "books")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(category.name), \(category.bookCount) books")
        .accessibilityHint("Tap to view books in this category")
    }

    // MARK: - Grouped Categories

    /// Groups categories by first letter for section headers
    private var groupedCategories: [String: [CategoryWithBookCount]] {
        let filtered = filteredCategories
        return Dictionary(grouping: filtered) { category in
            String(category.name.prefix(1).uppercased())
        }
    }

    /// Filters categories based on search text
    private var filteredCategories: [CategoryWithBookCount] {
        if searchText.isEmpty {
            return categories
        } else {
            return categories.filter { category in
                category.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Data Loading

    /// Loads the first page of categories
    private func loadCategories() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await searchManager.fetchCategories(page: currentPage, limit: 50)
            categories = response.results
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger.info("Loaded \(categories.count) categories (page \(currentPage) of \(response.pagination.pages), total: \(response.pagination.total))")
        } catch {
            DebugLogger.error("Failed to load categories", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Loads the next page of categories
    private func loadMoreCategories() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await searchManager.fetchCategories(page: currentPage, limit: 50)
            categories.append(contentsOf: response.results)
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger.info("Loaded more categories - page \(currentPage), total loaded: \(categories.count)")
        } catch {
            DebugLogger.error("Failed to load more categories", error: error)
            // Don't show error for pagination failures
        }

        isLoading = false
    }

    /// Refreshes the category list
    private func refreshCategories() async {
        searchManager.clearAllCaches()
        await loadCategories()
    }
}

// MARK: - Previews

struct CategoryListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CategoryListView()
        }
        .previewDisplayName("Category List")

        NavigationView {
            CategoryListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Category List (Dark)")
    }
}
