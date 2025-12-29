//
//  AuthorListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

/// List view for browsing all authors alphabetically
struct AuthorListView: View {
    @StateObject private var searchManager = SearchManager.shared
    @State private var authors: [AuthorWithBookCount] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var hasMorePages = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if isLoading && authors.isEmpty {
                ProgressView("Loading authors...")
                    .accessibilityLabel("Loading authors")
            } else if let error = errorMessage, authors.isEmpty {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Authors")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadAuthors()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if authors.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Authors Found")
                        .font(.headline)

                    Text("There are no authors in your library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(groupedAuthors.keys.sorted(), id: \.self) { letter in
                        Section(header: Text(letter)) {
                            ForEach(groupedAuthors[letter] ?? [], id: \.id) { author in
                                NavigationLink(destination: AuthorDetailView(authorId: author.id.uuidString)) {
                                    authorRow(author)
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
                                await loadMoreAuthors()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Filter authors")
                .refreshable {
                    await refreshAuthors()
                }
            }
        }
        .navigationTitle("Authors")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadAuthors()
        }
    }

    // MARK: - Author Row

    @ViewBuilder
    private func authorRow(_ author: AuthorWithBookCount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(author.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text("\(author.bookCount) \(author.bookCount == 1 ? "book" : "books")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(author.name), \(author.bookCount) books")
        .accessibilityHint("Tap to view books by this author")
    }

    // MARK: - Grouped Authors

    /// Groups authors by first letter for section headers
    private var groupedAuthors: [String: [AuthorWithBookCount]] {
        let filtered = filteredAuthors
        return Dictionary(grouping: filtered) { author in
            String(author.name.prefix(1).uppercased())
        }
    }

    /// Filters authors based on search text
    private var filteredAuthors: [AuthorWithBookCount] {
        if searchText.isEmpty {
            return authors
        } else {
            return authors.filter { author in
                author.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Data Loading

    /// Loads the first page of authors
    private func loadAuthors() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await searchManager.fetchAuthors(page: currentPage, limit: 50)
            authors = response.results
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger.info("Loaded \(authors.count) authors (page \(currentPage) of \(response.pagination.pages), total: \(response.pagination.total))")
        } catch {
            DebugLogger.error("Failed to load authors", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Loads the next page of authors
    private func loadMoreAuthors() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await searchManager.fetchAuthors(page: currentPage, limit: 50)
            authors.append(contentsOf: response.results)
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger.info("Loaded more authors - page \(currentPage), total loaded: \(authors.count)")
        } catch {
            DebugLogger.error("Failed to load more authors", error: error)
            // Don't show error for pagination failures
        }

        isLoading = false
    }

    /// Refreshes the author list
    private func refreshAuthors() async {
        searchManager.clearAllCaches()
        await loadAuthors()
    }
}

// MARK: - Previews

struct AuthorListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AuthorListView()
        }
        .previewDisplayName("Author List")

        NavigationView {
            AuthorListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Author List (Dark)")
    }
}
