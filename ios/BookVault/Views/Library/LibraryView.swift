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
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var libraryManager = LibraryManager.shared
    @Binding var selectedTab: Tab

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    private var isLoading: Bool {
        viewModel.mode == .books ? viewModel.isLoading : viewModel.isLoadingSeriesView
    }

    private var isEmpty: Bool {
        viewModel.mode == .books ? viewModel.books.isEmpty : viewModel.seriesViewItems.isEmpty
    }

    private var errorMessage: String? {
        viewModel.mode == .books ? viewModel.errorMessage : viewModel.seriesViewErrorMessage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading, isEmpty {
                    // Initial loading state
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading your library...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let error = errorMessage {
                    // Error state - check if it's offline-no-cache
                    // (Books mode only; the series feed has no offline cache.)
                    if viewModel.isOfflineNoCache, viewModel.mode == .books {
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
                                    await viewModel.refreshCurrentMode()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                } else if isEmpty {
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

                            // Extracted into their own views: nesting both
                            // branches inline here trips the Swift type-checker
                            // ("unable to type-check this expression in
                            // reasonable time") the same way CatalogView did.
                            if viewModel.mode == .books {
                                LibraryBooksGrid(viewModel: viewModel, columns: columns)
                            } else {
                                LibrarySeriesGrid(viewModel: viewModel, columns: columns)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Library")
            .refreshable {
                // Only allow refresh when online
                if networkMonitor.isConnected {
                    await viewModel.refreshCurrentMode()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $viewModel.mode) {
                        Text(CatalogMode.books.rawValue).tag(CatalogMode.books)
                        Text(CatalogMode.series.rawValue).tag(CatalogMode.series)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

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
            await viewModel.loadCurrentMode()
        }
        .onChange(of: viewModel.mode) {
            Task {
                await viewModel.loadCurrentMode()
            }
        }
    }
}

// MARK: - LibraryBooksGrid

/// Books mode: the user's library books, with the existing client-side pagination.
private struct LibraryBooksGrid: View {
    @ObservedObject var viewModel: LibraryViewModel
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(viewModel.books, id: \.id) { libraryBook in
                NavigationLink(destination: BookDetailView(book: libraryBook.asBook)) {
                    BookGridItem(book: libraryBook.asBook)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11y.bookCell(libraryBook.id.uuidString))
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

// MARK: - LibrarySeriesGrid

/// Series mode: owned series (with "N of M" ownership) interleaved with owned
/// standalone books. Fetched in one page, so there's no load-more indicator.
private struct LibrarySeriesGrid: View {
    @ObservedObject var viewModel: LibraryViewModel
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(viewModel.seriesViewItems) { item in
                CatalogSeriesViewItemCell(item: item)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - LibraryViewModel

@MainActor
class LibraryViewModel: ObservableObject {
    /// Separate from `CatalogViewModel.modeDefaultsKey` — the two toggles are
    /// remembered independently, per requirements Q1.
    static let modeDefaultsKey = "libraryViewMode"

    @Published var books: [LibraryBook] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMorePages = false
    @Published var shouldPaginate = false
    @Published var isOfflineNoCache = false // Track if error is due to offline with no cache

    /// Books/Series toggle state, persisted per-device.
    @Published var mode: CatalogMode = CatalogMode(
        rawValue: UserDefaults.standard.string(forKey: LibraryViewModel.modeDefaultsKey) ?? ""
    ) ?? .books {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeDefaultsKey)
        }
    }

    @Published var seriesViewItems: [CatalogSeriesViewItem] = []
    @Published var isLoadingSeriesView = false
    @Published var seriesViewErrorMessage: String?

    private let libraryManager = LibraryManager.shared
    private let apiClient: any APIClientProtocol
    private var totalBooks = 0
    private var currentPage = 1
    private let pageSize = 20
    private let paginationThreshold = 50
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownVersion = 0

    /// Series mode has no user-visible pagination (mirroring Books mode, which
    /// fetches the whole library at once), so it pages through the feed
    /// internally instead.
    ///
    /// This must not exceed the server's cap — `parsePagination` clamps `limit`
    /// to 100, so asking for more silently returns 100 and everything past it
    /// would be unreachable.
    private let seriesViewPageSize = 100

    /// Stop-loss on the internal paging loop, so a server that always reports
    /// another page can't spin forever.
    private let seriesViewMaxPages = 50

    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient

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
                        // Adding/removing a book can change which series appear
                        // and their owned counts, so refresh whichever mode is showing.
                        await self.reloadCurrentMode()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Loads whichever mode (Books/Series) is currently active — call on first
    /// appearance and whenever `mode` changes.
    func loadCurrentMode() async {
        switch mode {
        case .books:
            await loadLibrary()
        case .series:
            await loadSeriesView()
        }
    }

    /// Refreshes whichever mode is active — for pull-to-refresh.
    func refreshCurrentMode() async {
        switch mode {
        case .books:
            await refreshLibrary()
        case .series:
            await refreshSeriesView()
        }
    }

    /// Reloads the active mode after an external library change, discarding any
    /// cached Series-mode results so ownership counts can't go stale.
    private func reloadCurrentMode() async {
        switch mode {
        case .books:
            await loadLibrary()
        case .series:
            await refreshSeriesView()
        }
    }

    /// Fetches the entire library series feed, following pagination internally.
    ///
    /// The server caps `limit` at 100, so a library with more series-mode items
    /// than that needs multiple requests — Series mode has no load-more UI, so
    /// anything not fetched here would be permanently unreachable.
    private func fetchAllSeriesViewItems() async throws -> [CatalogSeriesViewItem] {
        var items: [CatalogSeriesViewItem] = []
        var page = 1

        while page <= seriesViewMaxPages {
            let response = try await apiClient.fetchLibrarySeriesView(page: page, limit: seriesViewPageSize)
            items.append(contentsOf: response.results)

            // Trust the reported page count, but stop early on a short/empty
            // page so a bad `pages` value can't cause pointless extra requests.
            if page >= response.pagination.pages || response.results.isEmpty {
                break
            }
            page += 1
        }

        if page > seriesViewMaxPages {
            DebugLogger.error(
                "Library series view hit the \(seriesViewMaxPages)-page safety cap; feed may be truncated",
                error: nil
            )
        }

        return items
    }

    func loadSeriesView() async {
        guard !isLoadingSeriesView else { return }
        guard seriesViewItems.isEmpty else { return } // already loaded this session

        isLoadingSeriesView = true
        seriesViewErrorMessage = nil

        do {
            self.seriesViewItems = try await fetchAllSeriesViewItems()
            isLoadingSeriesView = false
        } catch {
            isLoadingSeriesView = false
            seriesViewErrorMessage = error.localizedDescription
            DebugLogger.error("Failed to load library series view", error: error)
        }
    }

    func refreshSeriesView() async {
        // Mirrors refreshLibrary: don't touch @Published state before the network
        // call, since SwiftUI view re-evaluation during .refreshable can cancel the task.
        do {
            let items = try await fetchAllSeriesViewItems()
            self.seriesViewItems = items
            self.seriesViewErrorMessage = nil
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                seriesViewErrorMessage = error.localizedDescription
            }
        }
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
