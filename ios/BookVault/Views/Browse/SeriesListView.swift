//
//  SeriesListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - SeriesListView

/// List view for browsing all series alphabetically
struct SeriesListView: View {
    @StateObject private var searchManager = SearchManager.shared
    @State private var series: [SeriesWithBookCount] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var hasMorePages = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if isLoading, series.isEmpty {
                ProgressView("Loading series...")
                    .accessibilityLabel("Loading series")
            } else if let error = errorMessage, series.isEmpty {
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
                            await loadSeries()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if series.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Series Found")
                        .font(.headline)

                    Text("There are no series in your library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(groupedSeries.keys.sorted(), id: \.self) { letter in
                        Section(header: Text(letter)) {
                            ForEach(groupedSeries[letter] ?? [], id: \.id) { seriesItem in
                                NavigationLink(destination: SeriesDetailView(seriesId: seriesItem.id.uuidString)) {
                                    seriesRow(seriesItem)
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
                                await loadMoreSeries()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Filter series")
                .refreshable {
                    await refreshSeries()
                }
            }
        }
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadSeries()
        }
    }

    // MARK: - Series Row

    @ViewBuilder
    private func seriesRow(_ seriesItem: SeriesWithBookCount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(seriesItem.title)
                    .font(.body)
                    .fontWeight(.medium)

                Text("\(seriesItem.bookCount) \(seriesItem.bookCount == 1 ? "book" : "books")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(seriesItem.title), \(seriesItem.bookCount) books")
        .accessibilityHint("Tap to view books in this series")
    }

    // MARK: - Grouped Series

    /// Groups series by first letter for section headers
    private var groupedSeries: [String: [SeriesWithBookCount]] {
        let filtered = filteredSeries
        return Dictionary(grouping: filtered) { seriesItem in
            String(seriesItem.title.prefix(1).uppercased())
        }
    }

    /// Filters series based on search text
    private var filteredSeries: [SeriesWithBookCount] {
        if searchText.isEmpty {
            series
        } else {
            series.filter { seriesItem in
                seriesItem.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Data Loading

    /// Loads the first page of series
    private func loadSeries() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await searchManager.fetchSeries(page: currentPage, limit: 50)
            series = response.results
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger
                .info(
                    "Loaded \(series.count) series (page \(currentPage) of \(response.pagination.pages), total: \(response.pagination.total))"
                )
        } catch {
            DebugLogger.error("Failed to load series", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Loads the next page of series
    private func loadMoreSeries() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await searchManager.fetchSeries(page: currentPage, limit: 50)
            series.append(contentsOf: response.results)
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger.info("Loaded more series - page \(currentPage), total loaded: \(series.count)")
        } catch {
            DebugLogger.error("Failed to load more series", error: error)
            // Don't show error for pagination failures
        }

        isLoading = false
    }

    /// Refreshes the series list
    private func refreshSeries() async {
        searchManager.clearAllCaches()
        await loadSeries()
    }
}

// MARK: - SeriesListView_Previews

// periphery:ignore - Used by Xcode Previews
struct SeriesListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SeriesListView()
        }
        .previewDisplayName("Series List")

        NavigationView {
            SeriesListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Series List (Dark)")
    }
}
