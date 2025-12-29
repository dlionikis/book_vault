//
//  SeriesDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

/// Detail view showing a series and all books in series order
struct SeriesDetailView: View {
    let seriesId: String

    @StateObject private var searchManager = SearchManager.shared
    @State private var seriesDetail: GetSeries200Response?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading series details...")
                    .accessibilityLabel("Loading series details")
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Series")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadSeriesDetail()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let detail = seriesDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Series header
                        VStack(spacing: 12) {
                            Image(systemName: "books.vertical.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.accentColor)
                                .accessibilityHidden(true)

                            VStack(spacing: 4) {
                                Text(detail.title)
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

                                Text("This series doesn't have any books in your library")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Books in Series Order")
                                    .font(.headline)
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(detail.books, id: \.id) { book in
                                        NavigationLink(destination: BookDetailView(book: book)) {
                                            VStack(alignment: .leading, spacing: 0) {
                                                // Show sequence number if available
                                                if let seriesInfo = book.series?.first(where: { $0.id == detail.id }),
                                                   let sequence = seriesInfo.sequence {
                                                    Text("Book \(sequence)")
                                                        .font(.caption2)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.accentColor)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.accentColor.opacity(0.1))
                                                        .cornerRadius(4)
                                                        .padding(.bottom, 8)
                                                }

                                                BookGridItem(book: book)
                                            }
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
                    await refreshSeriesDetail()
                }
            }
        }
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSeriesDetail()
        }
    }

    // MARK: - Data Loading

    /// Loads the series detail from the API
    private func loadSeriesDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await searchManager.fetchSeriesDetail(id: seriesId)
            seriesDetail = detail
            DebugLogger.info("Loaded series: \(detail.title) with \(detail.books.count) books")
        } catch {
            DebugLogger.error("Failed to load series detail", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refreshes the series detail
    private func refreshSeriesDetail() async {
        searchManager.clearAllCaches()
        await loadSeriesDetail()
    }
}

// MARK: - Previews

struct SeriesDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Note: Using a placeholder ID for preview
            SeriesDetailView(seriesId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Series Detail")

        NavigationView {
            SeriesDetailView(seriesId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Series Detail (Dark)")
    }
}
