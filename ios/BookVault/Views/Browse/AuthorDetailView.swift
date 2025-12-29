//
//  AuthorDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

/// Detail view showing an author and all their books
struct AuthorDetailView: View {
    let authorId: String

    @StateObject private var searchManager = SearchManager.shared
    @State private var authorDetail: GetAuthor200Response?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading author details...")
                    .accessibilityLabel("Loading author details")
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Author")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadAuthorDetail()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let detail = authorDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Author header
                        VStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
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

                                Text("This author doesn't have any books in your library")
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
                    await refreshAuthorDetail()
                }
            }
        }
        .navigationTitle("Author")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAuthorDetail()
        }
    }

    // MARK: - Data Loading

    /// Loads the author detail from the API
    private func loadAuthorDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await searchManager.fetchAuthorDetail(id: authorId)
            authorDetail = detail
            DebugLogger.info("Loaded author: \(detail.name) with \(detail.books.count) books")
        } catch {
            DebugLogger.error("Failed to load author detail", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refreshes the author detail
    private func refreshAuthorDetail() async {
        searchManager.clearAllCaches()
        await loadAuthorDetail()
    }
}

// MARK: - Previews

struct AuthorDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Note: Using a placeholder ID for preview
            AuthorDetailView(authorId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Author Detail")

        NavigationView {
            AuthorDetailView(authorId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Author Detail (Dark)")
    }
}
