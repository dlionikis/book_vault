//
//  BrowseView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - BrowseView

/// Main browse screen with four category tiles
struct BrowseView: View {
    @StateObject private var searchManager = SearchManager.shared

    @State private var authorsCount: Int = 0
    @State private var seriesCount: Int = 0
    @State private var narratorsCount: Int = 0
    @State private var categoriesCount: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                if isLoading {
                    ProgressView("Loading browse categories...")
                        .accessibilityLabel("Loading browse categories")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text("Failed to load browse categories")
                            .font(.headline)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            Task {
                                await loadCounts()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        BrowseCategoryRow(
                            title: "Authors",
                            icon: "person.fill",
                            count: authorsCount,
                            destination: AnyView(AuthorListView())
                        )

                        BrowseCategoryRow(
                            title: "Series",
                            icon: "books.vertical.fill",
                            count: seriesCount,
                            destination: AnyView(SeriesListView())
                        )

                        BrowseCategoryRow(
                            title: "Narrators",
                            icon: "mic.fill",
                            count: narratorsCount,
                            destination: AnyView(NarratorListView())
                        )

                        BrowseCategoryRow(
                            title: "Categories",
                            icon: "tag.fill",
                            count: categoriesCount,
                            destination: AnyView(CategoryListView())
                        )
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await loadCounts()
                    }
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadCounts()
            }
        }
    }

    /// Loads the count for each browse category
    private func loadCounts() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch first page of each category to get total counts
            async let authorsResponse = searchManager.fetchAuthors(page: 1, limit: 1)
            async let seriesResponse = searchManager.fetchSeries(page: 1, limit: 1)
            async let narratorsResponse = searchManager.fetchNarrators(page: 1, limit: 1)
            async let categoriesResponse = searchManager.fetchCategories(page: 1, limit: 1)

            let (authors, series, narrators, categories) = try await (
                authorsResponse,
                seriesResponse,
                narratorsResponse,
                categoriesResponse
            )

            authorsCount = authors.pagination.total
            seriesCount = series.pagination.total
            narratorsCount = narrators.pagination.total
            categoriesCount = categories.pagination.total

            DebugLogger
                .info(
                    "Browse counts loaded - Authors: \(authorsCount), Series: \(seriesCount), Narrators: \(narratorsCount), Categories: \(categoriesCount)"
                )
        } catch {
            DebugLogger.error("Failed to load browse counts", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - BrowseCategoryRow

/// Row for a browse category with count and navigation
private struct BrowseCategoryRow: View {
    let title: String
    let icon: String
    let count: Int
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text("\(count) \(title.lowercased())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(title), \(count) \(title.lowercased())")
        .accessibilityHint("Tap to browse \(title.lowercased())")
    }
}

// MARK: - BrowseView_Previews

// periphery:ignore - Used by Xcode Previews
struct BrowseView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Default state
            BrowseView()
                .previewDisplayName("Browse View")

            // Dark mode
            BrowseView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Browse View (Dark)")
        }
    }
}
