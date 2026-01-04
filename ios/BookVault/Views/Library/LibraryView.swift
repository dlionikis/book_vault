//
//  LibraryView.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 4: Library UX Alignment
//

import Combine
import SwiftUI

// MARK: - LibraryView

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var authManager = AuthManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var libraryManager = LibraryManager.shared
    @Binding var selectedTab: Tab

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.isLoading, viewModel.books.isEmpty {
                    // Initial loading state
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading your library...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let error = viewModel.errorMessage {
                    // Error state - check if it's offline-no-cache
                    if viewModel.isOfflineNoCache {
                        // Special offline state with no cache
                        VStack(spacing: 20) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)

                            Text("No Cached Library")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(
                                "Connect to the internet to load your library for the first time. Once loaded, it will be available offline."
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                            if networkMonitor.isConnected {
                                Button("Load Library") {
                                    Task {
                                        await viewModel.loadLibrary()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("Waiting for connection...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                    } else {
                        // Generic error state
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            Text("Error Loading Library")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try Again") {
                                Task {
                                    await viewModel.loadLibrary()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                } else if viewModel.books.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("Your library is empty")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Browse the catalog to add books")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button {
                            // Navigate to Catalog tab
                            selectedTab = .catalog
                        } label: {
                            Text("Browse Catalog")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        // Library books grid
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("My Library")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Spacer()

                                // Show cached indicator when showing offline data
                                if libraryManager.isShowingCachedData {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise.icloud")
                                            .font(.caption)
                                        Text("Cached")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(viewModel.books, id: \.id) { libraryBook in
                                    NavigationLink(destination: BookDetailView(book: libraryBook.asBook)) {
                                        BookGridItem(book: libraryBook.asBook)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Load more indicator (only if pagination is enabled)
                                if viewModel.shouldPaginate, viewModel.hasMorePages {
                                    ProgressView()
                                        .gridCellColumns(columns.count)
                                        .onAppear {
                                            Task {
                                                await viewModel.loadMoreBooks()
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Library")
            .refreshable {
                // Only allow refresh when online
                if networkMonitor.isConnected {
                    await viewModel.refreshLibrary()
                }
            }
            .toolbar {
                // Show offline indicator in toolbar when offline
                if !networkMonitor.isConnected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi.slash")
                                .font(.caption)
                            Text("Offline")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
        }
        .task {
            await viewModel.loadLibrary()
        }
    }
}

// MARK: - LibraryViewModel

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var books: [LibraryBook] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMorePages = false
    @Published var shouldPaginate = false
    @Published var isOfflineNoCache = false // Track if error is due to offline with no cache

    private let libraryManager = LibraryManager.shared
    private var totalBooks = 0
    private var currentPage = 1
    private let pageSize = 20
    private let paginationThreshold = 50
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownVersion = 0

    init() {
        // Observe library changes and auto-reload when library is modified
        libraryManager.$libraryVersion
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newVersion in
                guard let self else { return }
                // Only reload if version changed (prevents duplicate reloads)
                if newVersion != self.lastKnownVersion {
                    self.lastKnownVersion = newVersion
                    DebugLogger.database("Library version changed to \(newVersion), reloading...")
                    Task {
                        await self.loadLibrary()
                    }
                }
            }
            .store(in: &cancellables)
    }

    func loadLibrary() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        isOfflineNoCache = false
        currentPage = 1

        do {
            // Fetch library books (backend returns sorted by addedAt desc)
            let fetchedBooks = try await libraryManager.fetchLibraryBooks()
            self.books = fetchedBooks
            self.totalBooks = fetchedBooks.count

            // Smart pagination: only paginate if >= 50 books
            self.shouldPaginate = totalBooks >= paginationThreshold

            if shouldPaginate {
                // If paginating, only show first page
                self.books = Array(fetchedBooks.prefix(pageSize))
                self.hasMorePages = totalBooks > pageSize
            } else {
                // If not paginating, show all books
                self.hasMorePages = false
            }

            isLoading = false
        } catch let error as LibraryError {
            isLoading = false
            errorMessage = error.localizedDescription
            isOfflineNoCache = (error == .offlineNoCache)
            DebugLogger.error("Failed to load library", error: error)
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            isOfflineNoCache = false
            DebugLogger.error("Failed to load library", error: error)
        }
    }

    func loadMoreBooks() async {
        guard !isLoading, hasMorePages, shouldPaginate else { return }

        isLoading = true
        currentPage += 1

        do {
            // Fetch fresh data to get the next page
            let fetchedBooks = try await libraryManager.fetchLibraryBooks()

            // Calculate which books to show for this page
            let startIndex = (currentPage - 1) * pageSize
            let endIndex = min(startIndex + pageSize, fetchedBooks.count)

            if startIndex < fetchedBooks.count {
                let newBooks = Array(fetchedBooks[startIndex ..< endIndex])
                self.books.append(contentsOf: newBooks)
                self.hasMorePages = endIndex < fetchedBooks.count
            } else {
                self.hasMorePages = false
            }

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            DebugLogger.error("Failed to load more library books", error: error)
        }
    }

    func refreshLibrary() async {
        // Pull-to-refresh: Don't set ANY @Published properties before the network call
        // because SwiftUI view re-evaluation during .refreshable can cancel the task.
        // See: SwiftUI .refreshable + @Published bug

        do {
            // Force refresh from API (bypasses cache)
            let fetchedBooks = try await libraryManager.fetchLibraryBooks(forceRefresh: true)

            // Only update @Published properties AFTER the network call succeeds
            self.books = fetchedBooks
            self.totalBooks = fetchedBooks.count
            self.currentPage = 1

            // Smart pagination: only paginate if >= 50 books
            self.shouldPaginate = totalBooks >= paginationThreshold

            if shouldPaginate {
                self.books = Array(fetchedBooks.prefix(pageSize))
                self.hasMorePages = totalBooks > pageSize
            } else {
                self.hasMorePages = false
            }
        } catch let error as LibraryError {
            // Only show error if it wasn't a cancellation
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                errorMessage = error.localizedDescription
                isOfflineNoCache = (error == .offlineNoCache)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    struct PreviewWrapper: View {
        @State private var tab: Tab = .library

        var body: some View {
            LibraryView(selectedTab: $tab)
        }
    }

    return PreviewWrapper()
}

#Preview("With Books") {
    struct PreviewWrapper: View {
        @State private var tab: Tab = .library

        var body: some View {
            LibraryView(selectedTab: $tab)
        }
    }

    return PreviewWrapper()
}
