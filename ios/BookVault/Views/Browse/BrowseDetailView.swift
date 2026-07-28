//
//  BrowseDetailView.swift
//  BookVault
//
//  Generic detail view for showing an author, narrator, or category and their books.
//

import SwiftUI

// MARK: - BrowseDetailView

/// A detail view that shows a header (icon + name + book count) and a book grid,
/// driven by a configuration.
struct BrowseDetailView<Detail: BrowseDetailResponse>: View {
    let itemId: String
    let configuration: BrowseDetailConfiguration<Detail>

    @ObservedObject private var searchManager = SearchManager.shared
    @State private var detail: Detail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView(configuration.loadingMessage)
                    .accessibilityLabel(configuration.loadingMessage)
            } else if let error = errorMessage {
                errorStateView(error)
            } else if let detail {
                contentView(detail)
            }
        }
        .navigationTitle(configuration.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
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
                    await loadDetail()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Content

    private func contentView(_ detail: Detail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: configuration.headerIcon)
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)

                    VStack(spacing: 4) {
                        Text(detail.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("\(detail.books.count) \(detail.books.count == 1 ? "book" : "books")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Divider()

                // Books section
                if detail.books.isEmpty {
                    emptyBooksView
                } else {
                    booksGridView(detail)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await refreshDetail()
        }
    }

    // MARK: - Empty Books

    private var emptyBooksView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No books found")
                .font(.headline)

            Text(configuration.emptyBooksMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Books Grid

    private func booksGridView(_ detail: Detail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Books")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(detail.books, id: \.id) { book in
                    NavigationLink(destination: BookDetailView(book: book)) {
                        BookGridItem(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Data Loading

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await configuration.fetch(searchManager, itemId)
            detail = fetched
            DebugLogger.info("Loaded \(configuration.navigationTitle.lowercased()): \(fetched.displayName) with \(fetched.books.count) books")
        } catch {
            DebugLogger.error("Failed to load \(configuration.navigationTitle.lowercased()) detail", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func refreshDetail() async {
        searchManager.clearAllCaches()
        await loadDetail()
    }
}
