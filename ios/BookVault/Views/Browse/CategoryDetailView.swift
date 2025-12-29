//
//  CategoryDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

/// Detail view showing a category and all books in that category
struct CategoryDetailView: View {
    let categoryId: String

    @StateObject private var searchManager = SearchManager.shared
    @State private var categoryDetail: GetCategory200Response?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading category details...")
                    .accessibilityLabel("Loading category details")
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Category")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadCategoryDetail()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let detail = categoryDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Category header
                        VStack(spacing: 12) {
                            Image(systemName: "tag.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.accentColor)
                                .accessibilityHidden(true)

                            VStack(spacing: 4) {
                                Text(detail.name)
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
                            VStack(spacing: 16) {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text("No books found")
                                    .font(.headline)

                                Text("This category doesn't have any books in your library")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
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
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await refreshCategoryDetail()
                }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCategoryDetail()
        }
    }

    // MARK: - Data Loading

    /// Loads the category detail from the API
    private func loadCategoryDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await searchManager.fetchCategoryDetail(id: categoryId)
            categoryDetail = detail
            DebugLogger.info("Loaded category: \(detail.name) with \(detail.books.count) books")
        } catch {
            DebugLogger.error("Failed to load category detail", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refreshes the category detail
    private func refreshCategoryDetail() async {
        searchManager.clearAllCaches()
        await loadCategoryDetail()
    }
}

// MARK: - Previews

struct CategoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Note: Using a placeholder ID for preview
            CategoryDetailView(categoryId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Category Detail")

        NavigationView {
            CategoryDetailView(categoryId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Category Detail (Dark)")
    }
}
