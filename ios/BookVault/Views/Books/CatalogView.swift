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
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top),
    ]

    var body: some View {
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
                await viewModel.refreshBooks()
            }
        }
        .task {
            await viewModel.loadBooks()
        }
    }
}

// MARK: - BookGridItem

struct BookGridItem: View {
    let book: Book
    @State private var userProgress: UserProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image with progress overlay
            ZStack(alignment: .bottom) {
                AsyncImage(url: URL(string: book.coverUrl ?? "")) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                ProgressView()
                            }
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                Image(systemName: "book.fill")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }

                // Progress indicator
                if let progress = userProgress {
                    ProgressIndicator(progress: progress, runtimeMinutes: book.runtimeMinutes ?? 0)
                }
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

    func loadBooks() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await apiClient.fetchBooks(page: currentPage, limit: pageSize)
            self.books = response.books
            self.totalPages = response.pagination.pages
            self.hasMorePages = currentPage < totalPages
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreBooks() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await apiClient.fetchBooks(page: currentPage, limit: pageSize)
            self.books.append(contentsOf: response.books)
            self.totalPages = response.pagination.pages
            self.hasMorePages = currentPage < totalPages
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshBooks() async {
        await loadBooks()
    }
}

// MARK: - ContinueListeningCard

struct ContinueListeningCard: View {
    let book: Book
    @State private var userProgress: UserProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: book.coverUrl ?? "")) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure,
                         .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                Image(systemName: "book.fill")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 200, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Progress bar overlay
                if let progress = userProgress {
                    VStack(spacing: 0) {
                        Spacer()
                        ProgressBar(progress: progress, runtimeMinutes: book.runtimeMinutes ?? 0)
                    }
                }
            }
            .shadow(radius: 6)

            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if let firstAuthor = book.authors.first {
                    Text(firstAuthor.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Time remaining
                if let progress = userProgress {
                    let remainingSeconds = Double((book.runtimeMinutes ?? 0) * 60) - progress.positionSeconds
                    Text(formatTimeRemaining(remainingSeconds))
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 200)
        }
        .task {
            await fetchProgress()
        }
    }

    private func fetchProgress() async {
        do {
            userProgress = try await ProgressManager.shared.fetchProgress(for: book.id.uuidString)
        } catch {
            DebugLogger.verbose("Failed to fetch progress for book \(book.id): \(error)")
        }
    }

    private func formatTimeRemaining(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else {
            return "\(minutes)m left"
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
