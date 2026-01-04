//
//  SeriesDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - SeriesDetailView

/// Detail view showing a series and all books in series order
struct SeriesDetailView: View {
    let seriesId: String

    @StateObject private var searchManager = SearchManager.shared
    @StateObject private var libraryManager = LibraryManager.shared
    @State private var seriesDetail: GetSeries200Response?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAddingToLibrary = false
    @State private var showingSuccessMessage = false
    @State private var booksInLibrary: Set<String> = []
    @State private var isCheckingLibrary = false

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
                            VStack(alignment: .leading, spacing: 16) {
                                // Add/Remove Series to/from Library button
                                if isCheckingLibrary {
                                    HStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                        Text("Checking library status...")
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                } else if booksInLibrary.isEmpty {
                                    // Add to library button
                                    Button {
                                        Task {
                                            await addSeriesToLibrary()
                                        }
                                    } label: {
                                        HStack {
                                            if isAddingToLibrary {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle())
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: showingSuccessMessage ? "checkmark.circle.fill" :
                                                    "plus.circle.fill")
                                            }
                                            Text(showingSuccessMessage ? "Added to Library" :
                                                "Add Entire Series to Library")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(showingSuccessMessage ? Color.green : Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                    }
                                    .disabled(isAddingToLibrary || showingSuccessMessage)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)
                                } else {
                                    // Remove from library button
                                    Button {
                                        Task {
                                            await removeSeriesFromLibrary()
                                        }
                                    } label: {
                                        HStack {
                                            if isAddingToLibrary {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle())
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: showingSuccessMessage ? "checkmark.circle.fill" :
                                                    "trash.circle.fill")
                                            }
                                            Text(showingSuccessMessage ? "Removed from Library" :
                                                "Remove Series from Library")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(showingSuccessMessage ? Color.green : Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                    }
                                    .disabled(isAddingToLibrary || showingSuccessMessage)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)
                                }

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

    // MARK: - Library Actions

    /// Checks which books from the series are already in the library
    private func checkLibraryStatus() async {
        guard let detail = seriesDetail else { return }

        isCheckingLibrary = true
        defer { isCheckingLibrary = false }

        var inLibrary = Set<String>()

        for book in detail.books {
            do {
                let status = try await libraryManager.isInLibrary(bookId: book.id.uuidString)
                if status {
                    inLibrary.insert(book.id.uuidString)
                }
            } catch {
                DebugLogger.error("Failed to check library status for book \(book.id)", error: error)
            }
        }

        await MainActor.run {
            booksInLibrary = inLibrary
        }

        DebugLogger.info("Series '\(detail.title)': \(inLibrary.count)/\(detail.books.count) books in library")
    }

    /// Adds all books in the series to the user's library
    private func addSeriesToLibrary() async {
        guard let detail = seriesDetail else { return }

        isAddingToLibrary = true
        defer { isAddingToLibrary = false }

        do {
            // Add each book in the series to the library
            for book in detail.books {
                _ = try await libraryManager.addToLibrary(bookId: book.id.uuidString)
            }

            // Update library status
            await checkLibraryStatus()

            // Show success message
            await MainActor.run {
                showingSuccessMessage = true
            }

            // Reset success message after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showingSuccessMessage = false
            }

            DebugLogger.info("Successfully added \(detail.books.count) books from series '\(detail.title)' to library")
        } catch {
            DebugLogger.error("Failed to add series to library", error: error)
            errorMessage = "Failed to add series to library: \(error.localizedDescription)"
        }
    }

    /// Removes all books in the series from the user's library
    private func removeSeriesFromLibrary() async {
        guard let detail = seriesDetail else { return }

        isAddingToLibrary = true
        defer { isAddingToLibrary = false }

        do {
            // Remove each book in the series from the library
            for book in detail.books {
                try await libraryManager.removeFromLibrary(bookId: book.id.uuidString)
            }

            // Update library status
            await checkLibraryStatus()

            // Show success message
            await MainActor.run {
                showingSuccessMessage = true
            }

            // Reset success message after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showingSuccessMessage = false
            }

            DebugLogger
                .info("Successfully removed \(detail.books.count) books from series '\(detail.title)' from library")
        } catch {
            DebugLogger.error("Failed to remove series from library", error: error)
            errorMessage = "Failed to remove series from library: \(error.localizedDescription)"
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

            // Check library status after loading series
            await checkLibraryStatus()
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

// MARK: - SeriesDetailView_Previews

// periphery:ignore - Used by Xcode Previews
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
