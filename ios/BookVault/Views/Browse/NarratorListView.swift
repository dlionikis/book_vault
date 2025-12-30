//
//  NarratorListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - NarratorListView

/// List view for browsing all narrators alphabetically
struct NarratorListView: View {
    @StateObject private var searchManager = SearchManager.shared
    @State private var narrators: [NarratorWithBookCount] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var hasMorePages = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if isLoading, narrators.isEmpty {
                ProgressView("Loading narrators...")
                    .accessibilityLabel("Loading narrators")
            } else if let error = errorMessage, narrators.isEmpty {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Narrators")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadNarrators()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if narrators.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Narrators Found")
                        .font(.headline)

                    Text("There are no narrators in your library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(groupedNarrators.keys.sorted(), id: \.self) { letter in
                        Section(header: Text(letter)) {
                            ForEach(groupedNarrators[letter] ?? [], id: \.id) { narrator in
                                NavigationLink(destination: NarratorDetailView(narratorId: narrator.id.uuidString)) {
                                    narratorRow(narrator)
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
                                await loadMoreNarrators()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Filter narrators")
                .refreshable {
                    await refreshNarrators()
                }
            }
        }
        .navigationTitle("Narrators")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadNarrators()
        }
    }

    // MARK: - Narrator Row

    @ViewBuilder
    private func narratorRow(_ narrator: NarratorWithBookCount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(narrator.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text("\(narrator.bookCount) \(narrator.bookCount == 1 ? "book" : "books")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(narrator.name), \(narrator.bookCount) books")
        .accessibilityHint("Tap to view books narrated by this narrator")
    }

    // MARK: - Grouped Narrators

    /// Groups narrators by first letter for section headers
    private var groupedNarrators: [String: [NarratorWithBookCount]] {
        let filtered = filteredNarrators
        return Dictionary(grouping: filtered) { narrator in
            String(narrator.name.prefix(1).uppercased())
        }
    }

    /// Filters narrators based on search text
    private var filteredNarrators: [NarratorWithBookCount] {
        if searchText.isEmpty {
            narrators
        } else {
            narrators.filter { narrator in
                narrator.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Data Loading

    /// Loads the first page of narrators
    private func loadNarrators() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await searchManager.fetchNarrators(page: currentPage, limit: 50)
            narrators = response.results
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger
                .info(
                    "Loaded \(narrators.count) narrators (page \(currentPage) of \(response.pagination.pages), total: \(response.pagination.total))"
                )
        } catch {
            DebugLogger.error("Failed to load narrators", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Loads the next page of narrators
    private func loadMoreNarrators() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await searchManager.fetchNarrators(page: currentPage, limit: 50)
            narrators.append(contentsOf: response.results)
            hasMorePages = currentPage < response.pagination.pages
            DebugLogger.info("Loaded more narrators - page \(currentPage), total loaded: \(narrators.count)")
        } catch {
            DebugLogger.error("Failed to load more narrators", error: error)
            // Don't show error for pagination failures
        }

        isLoading = false
    }

    /// Refreshes the narrator list
    private func refreshNarrators() async {
        searchManager.clearAllCaches()
        await loadNarrators()
    }
}

// MARK: - NarratorListView_Previews

struct NarratorListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NarratorListView()
        }
        .previewDisplayName("Narrator List")

        NavigationView {
            NarratorListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Narrator List (Dark)")
    }
}
