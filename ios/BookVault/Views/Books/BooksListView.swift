//
//  BooksListView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct BooksListView: View {
    @StateObject private var viewModel = BooksListViewModel()
    @StateObject private var authManager = AuthManager.shared

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.isLoading && viewModel.books.isEmpty {
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
                        Text("Your library is empty")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    // Books grid
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
                    .padding()
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await authManager.logout()
                        }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .refreshable {
                await viewModel.refreshBooks()
            }
        }
        .task {
            await viewModel.loadBooks()
        }
    }
}

// MARK: - Book Grid Item

struct BookGridItem: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            AsyncImage(url: URL(string: book.coverUrl)) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
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
                Text(formatRuntime(book.runtimeMinutes))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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

// MARK: - View Model

@MainActor
class BooksListViewModel: ObservableObject {
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
        guard !isLoading && hasMorePages else { return }

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

#Preview {
    BooksListView()
}
