//
//  NarratorDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

/// Detail view showing a narrator and all their books
struct NarratorDetailView: View {
    let narratorId: String

    @StateObject private var searchManager = SearchManager.shared
    @State private var narratorDetail: GetNarrator200Response?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading narrator details...")
                    .accessibilityLabel("Loading narrator details")
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Narrator")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadNarratorDetail()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let detail = narratorDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Narrator header
                        VStack(spacing: 12) {
                            Image(systemName: "mic.circle.fill")
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

                                Text("This narrator doesn't have any books in your library")
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
                    await refreshNarratorDetail()
                }
            }
        }
        .navigationTitle("Narrator")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadNarratorDetail()
        }
    }

    // MARK: - Data Loading

    /// Loads the narrator detail from the API
    private func loadNarratorDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await searchManager.fetchNarratorDetail(id: narratorId)
            narratorDetail = detail
            DebugLogger.info("Loaded narrator: \(detail.name) with \(detail.books.count) books")
        } catch {
            DebugLogger.error("Failed to load narrator detail", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refreshes the narrator detail
    private func refreshNarratorDetail() async {
        searchManager.clearAllCaches()
        await loadNarratorDetail()
    }
}

// MARK: - Previews

struct NarratorDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Note: Using a placeholder ID for preview
            NarratorDetailView(narratorId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Narrator Detail")

        NavigationView {
            NarratorDetailView(narratorId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Narrator Detail (Dark)")
    }
}
