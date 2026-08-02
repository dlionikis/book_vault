//
//  BrowseListView.swift
//  BookVault
//
//  Generic list view for browsing authors, narrators, series, and categories.
//

import SwiftUI

// MARK: - BrowseListView

/// A paginated, searchable, alphabetically-grouped list view driven by a configuration.
struct BrowseListView<Item: BrowseListItem, Response: BrowseListResponse>: View where Response.Item == Item {
    let configuration: BrowseListConfiguration<Item, Response>

    @ObservedObject private var searchManager = SearchManager.shared
    @State private var items: [Item] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var hasMorePages = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if isLoading, items.isEmpty {
                ProgressView(configuration.loadingMessage)
                    .accessibilityLabel(configuration.loadingMessage)
            } else if let error = errorMessage, items.isEmpty {
                errorStateView(error)
            } else if items.isEmpty {
                emptyStateView
            } else {
                listView
            }
        }
        .navigationTitle(configuration.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadItems()
        }
    }

    // MARK: - Error State

    private func errorStateView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text(configuration.errorTitle)
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task {
                    await loadItems()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: configuration.emptyIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No \(configuration.navigationTitle) Found")
                .font(.headline)

            Text(configuration.emptyMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - List

    private var listView: some View {
        List {
            ForEach(groupedItems.keys.sorted(), id: \.self) { letter in
                Section(header: Text(letter)) {
                    ForEach(groupedItems[letter] ?? [], id: \.id) { item in
                        NavigationLink(destination: configuration.destination(item.id.uuidString)) {
                            itemRow(item)
                        }
                    }
                }
            }

            if hasMorePages {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .onAppear {
                    Task {
                        await loadMoreItems()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: configuration.searchPrompt)
        .refreshable {
            await refreshItems()
        }
    }

    // MARK: - Item Row

    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        HStack(spacing: 12) {
            iconView
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                if let subtitle = item.displaySubtitle {
                    Text("in \(subtitle)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Text("\(item.bookCount) \(item.bookCount == 1 ? "book" : "books")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityHint(configuration.accessibilityHint)
    }

    /// Includes the disambiguating path so VoiceOver users can tell repeated
    /// names apart, exactly as sighted users do from the subtitle.
    private func accessibilityLabel(for item: Item) -> String {
        let books = "\(item.bookCount) books"
        if let subtitle = item.displaySubtitle {
            return "\(item.displayName), in \(subtitle), \(books)"
        }
        return "\(item.displayName), \(books)"
    }

    @ViewBuilder
    private var iconView: some View {
        if configuration.useCircleIcon {
            Image(systemName: configuration.rowIcon)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
        } else {
            Image(systemName: configuration.rowIcon)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Grouping & Filtering

    private var groupedItems: [String: [Item]] {
        let filtered = filteredItems
        return Dictionary(grouping: filtered) { item in
            String(item.displayName.prefix(1).uppercased())
        }
    }

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            items
        } else {
            // Match the ancestor path too, so filtering "fantasy" also surfaces
            // nested rows like "Epic" under "SF&F › Fantasy".
            items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || ($0.displaySubtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    // MARK: - Data Loading

    private func loadItems() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await configuration.fetch(searchManager, currentPage, 50)
            items = response.results
            hasMorePages = currentPage < response.paginationPages
            DebugLogger.info(
                "Loaded \(items.count) \(configuration.navigationTitle.lowercased()) (page \(currentPage) of \(response.paginationPages), total: \(response.paginationTotal))"
            )
        } catch {
            DebugLogger.error("Failed to load \(configuration.navigationTitle.lowercased())", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadMoreItems() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await configuration.fetch(searchManager, currentPage, 50)
            items.append(contentsOf: response.results)
            hasMorePages = currentPage < response.paginationPages
            DebugLogger.info("Loaded more \(configuration.navigationTitle.lowercased()) - page \(currentPage), total loaded: \(items.count)")
        } catch {
            DebugLogger.error("Failed to load more \(configuration.navigationTitle.lowercased())", error: error)
        }

        isLoading = false
    }

    private func refreshItems() async {
        searchManager.clearAllCaches()
        await loadItems()
    }
}
