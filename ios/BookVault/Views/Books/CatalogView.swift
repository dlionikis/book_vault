//
//  CatalogView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//  Renamed from BooksListView.swift on 12/29/25 (Phase 3: Library UX Alignment)
//

import SwiftUI

// MARK: - CatalogView

struct CatalogView: View {
    @StateObject private var viewModel = CatalogViewModel()
    @StateObject private var authManager = AuthManager.shared

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = DebugLogger.info("🎨 CatalogView.body EVALUATED - isLoading: \(viewModel.isLoading), booksCount: \(viewModel.books.count)")
        NavigationView {
            ScrollView {
                if viewModel.isLoading, viewModel.books.isEmpty {
                    // Initial loading state
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading books...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let error = viewModel.errorMessage {
                    // Error state
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Error Loading Books")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task {
                                await viewModel.loadBooks()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if viewModel.books.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No Books Found")
                            .font(.headline)
                        Text("No books in catalog")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        // All Books grid
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All Books")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(viewModel.books, id: \.id) { book in
                                    NavigationLink(destination: BookDetailView(book: book)) {
                                        BookGridItem(book: book)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Load more indicator
                                if viewModel.hasMorePages {
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
            .navigationTitle("Catalog")
            .refreshable {
                DebugLogger.info("🔄 CatalogView .refreshable TRIGGERED - isLoading: \(viewModel.isLoading)")
                if Task.isCancelled {
                    DebugLogger.error("🔄 CatalogView .refreshable - Task ALREADY CANCELLED at start!")
                }
                await viewModel.refreshBooks()
                DebugLogger.info("🔄 CatalogView .refreshable COMPLETED")
            }
        }
        .task {
            DebugLogger.info("🚀 CatalogView .task TRIGGERED")
            await viewModel.loadBooks()
            DebugLogger.info("🚀 CatalogView .task COMPLETED")
        }
        .onDisappear {
            DebugLogger.info("👋 CatalogView onDisappear")
        }
    }
}

// MARK: - BookGridItem

struct BookGridItem: View {
    let book: Book
    @State private var userProgress: UserProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image with progress overlay
            ZStack(alignment: .bottom) {
                CachedCoverImage(bookId: book.id, coverUrl: book.coverUrl)

                // Progress indicator
                if let progress = userProgress {
                    ProgressIndicator(progress: progress, runtimeMinutes: book.runtimeMinutes ?? 0)
                }
            }
            // Archive/restore badge (top-trailing); renders nothing when available.
            .overlay(alignment: .topTrailing) {
                ArchiveBadge(status: book.archiveStatus)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)

            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if let firstAuthor = book.authors.first {
                    Text(firstAuthor.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Runtime
                Text(formatRuntime(book.runtimeMinutes ?? 0))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .task {
            // Fetch progress for this book
            await fetchProgress()
        }
    }

    private func fetchProgress() async {
        do {
            userProgress = try await ProgressManager.shared.fetchProgress(for: book.id.uuidString)
        } catch {
            // Silently fail - progress is optional
            DebugLogger.verbose("Failed to fetch progress for book \(book.id): \(error)")
        }
    }

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - CatalogCache

/// In-memory cache for catalog pages
private struct CatalogCache {
    var pages: [Int: [Book]] = [:]
    var totalPages: Int = 1
    var lastUpdate: Date?
    let ttl: TimeInterval = 600 // 10 minutes

    var isValid: Bool {
        guard let lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < ttl
    }

    mutating func invalidate() {
        pages.removeAll()
        totalPages = 1
        lastUpdate = nil
    }
}

// MARK: - CatalogViewModel

@MainActor
class CatalogViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMorePages = true

    private let apiClient = APIClient.shared
    private var currentPage = 1
    private let pageSize = 20
    private var totalPages = 1
    private let instanceId = UUID().uuidString.prefix(8)

    /// In-memory cache shared across all CatalogViewModel instances
    private static var cache = CatalogCache()

    init() {
        DebugLogger.info("🆕 CatalogViewModel INIT - instance: \(instanceId)")
    }

    deinit {
        DebugLogger.info("💀 CatalogViewModel DEINIT - instance: \(instanceId)")
    }

    func loadBooks() async {
        DebugLogger.info("📚 [\(instanceId)] loadBooks() START - isLoading: \(isLoading)")
        guard !isLoading else {
            DebugLogger.info("📚 loadBooks() SKIPPED - already loading")
            return
        }

        // Check cache first
        if Self.cache.isValid, !Self.cache.pages.isEmpty {
            DebugLogger.network("Using cached catalog (page 1)")
            self.books = Self.cache.pages.sorted { $0.key < $1.key }.flatMap(\.value)
            self.totalPages = Self.cache.totalPages
            self.currentPage = Self.cache.pages.keys.max() ?? 1
            self.hasMorePages = currentPage < totalPages
            DebugLogger.info("📚 loadBooks() END - used cache")
            return
        }

        DebugLogger.info("📚 [\(instanceId)] BEFORE setting isLoading=true, Task.isCancelled=\(Task.isCancelled)")
        isLoading = true
        DebugLogger.info("📚 [\(instanceId)] AFTER setting isLoading=true, Task.isCancelled=\(Task.isCancelled)")
        errorMessage = nil
        currentPage = 1

        DebugLogger.info("📚 [\(instanceId)] loadBooks() fetching from API...")

        // DEBUG: Test if the issue is with Task cancellation during ANY async work
        DebugLogger.info("📚 [\(instanceId)] DEBUG: sleeping 100ms to test cancellation...")
        do {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            DebugLogger.info("📚 [\(instanceId)] DEBUG: sleep completed successfully")
        } catch {
            DebugLogger.error("📚 [\(instanceId)] DEBUG: sleep was CANCELLED - \(error)")
        }

        do {
            let response = try await apiClient.fetchBooks(page: currentPage, limit: pageSize)
            DebugLogger.info("📚 loadBooks() API SUCCESS - got \(response.books.count) books")
            self.books = response.books
            self.totalPages = response.pagination.pages
            self.hasMorePages = currentPage < totalPages

            // Update cache
            Self.cache.pages = [1: response.books]
            Self.cache.totalPages = response.pagination.pages
            Self.cache.lastUpdate = Date()

            isLoading = false
            DebugLogger.info("📚 loadBooks() END - success")
        } catch {
            isLoading = false
            let isCancellation = (error as NSError).code == NSURLErrorCancelled
            DebugLogger.info("📚 loadBooks() FAILED - isCancellation: \(isCancellation), error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreBooks() async {
        guard !isLoading, hasMorePages else { return }

        let nextPage = currentPage + 1

        // Check if next page is cached
        if Self.cache.isValid, let cachedPage = Self.cache.pages[nextPage] {
            DebugLogger.network("Using cached catalog (page \(nextPage))")
            self.books.append(contentsOf: cachedPage)
            self.currentPage = nextPage
            self.hasMorePages = currentPage < totalPages
            return
        }

        isLoading = true
        currentPage = nextPage

        do {
            let response = try await apiClient.fetchBooks(page: currentPage, limit: pageSize)
            self.books.append(contentsOf: response.books)
            self.totalPages = response.pagination.pages
            self.hasMorePages = currentPage < totalPages

            // Update cache
            Self.cache.pages[currentPage] = response.books
            Self.cache.totalPages = response.pagination.pages
            Self.cache.lastUpdate = Date()

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshBooks() async {
        // Pull-to-refresh: Don't set ANY @Published properties before the network call
        // because SwiftUI view re-evaluation during .refreshable can cancel the task.
        // See: SwiftUI .refreshable + @Published bug

        // Invalidate cache to force fresh data (this is not @Published, safe to call)
        Self.cache.invalidate()

        do {
            let response = try await apiClient.fetchBooks(page: 1, limit: pageSize)

            // Only update @Published properties AFTER the network call succeeds
            self.books = response.books
            self.totalPages = response.pagination.pages
            self.currentPage = 1
            self.hasMorePages = currentPage < totalPages

            // Update cache
            Self.cache.pages = [1: response.books]
            Self.cache.totalPages = response.pagination.pages
            Self.cache.lastUpdate = Date()
        } catch {
            // Only show error if it wasn't a cancellation (user swiped away, etc.)
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - ProgressBar

struct ProgressBar: View {
    let progress: UserProgress
    let runtimeMinutes: Int

    private var progressPercentage: Double {
        let totalSeconds = Double(runtimeMinutes * 60)
        guard totalSeconds > 0 else { return 0 }
        return min(progress.positionSeconds / totalSeconds, 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.black.opacity(0.4))

                // Progress
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * progressPercentage)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - ProgressIndicator

struct ProgressIndicator: View {
    let progress: UserProgress
    let runtimeMinutes: Int

    private var progressPercentage: Double {
        let totalSeconds = Double(runtimeMinutes * 60)
        guard totalSeconds > 0 else { return 0 }
        return min(progress.positionSeconds / totalSeconds, 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.black.opacity(0.3))

                    // Progress
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progressPercentage)
                }
            }
            .frame(height: 4)

            // Completed badge
            if progress.completed {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Completed")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    CatalogView()
}

#Preview("Grid Item - Standard") {
    NavigationView {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 20) {
                NavigationLink(destination: BookDetailView(book: .mockStandard)) {
                    BookGridItem(book: .mockStandard)
                }
                NavigationLink(destination: BookDetailView(book: .mockLongTitle)) {
                    BookGridItem(book: .mockLongTitle)
                }
                NavigationLink(destination: BookDetailView(book: .mockMultipleAuthors)) {
                    BookGridItem(book: .mockMultipleAuthors)
                }
                NavigationLink(destination: BookDetailView(book: .mockMinimal)) {
                    BookGridItem(book: .mockMinimal)
                }
            }
            .padding()
        }
        .navigationTitle("Catalog")
    }
}

#Preview("Dark Mode") {
    NavigationView {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 20) {
                NavigationLink(destination: BookDetailView(book: .mockStandard)) {
                    BookGridItem(book: .mockStandard)
                }
                NavigationLink(destination: BookDetailView(book: .mockLongTitle)) {
                    BookGridItem(book: .mockLongTitle)
                }
            }
            .padding()
        }
        .navigationTitle("Catalog")
    }
    .preferredColorScheme(.dark)
}
