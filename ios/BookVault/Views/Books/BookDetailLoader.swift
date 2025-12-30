//
//  BookDetailLoader.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - BookDetailLoader

/// Wrapper view that loads a book by ID and displays BookDetailView
struct BookDetailLoader: View {
    let bookId: String

    @State private var book: Book?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading book...")
                    .accessibilityLabel("Loading book details")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Failed to Load Book")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            await loadBook()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let book {
                BookDetailView(book: book)
            }
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBook()
        }
    }

    private func loadBook() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let uuid = UUID(uuidString: bookId) else {
                throw APIError.invalidURL
            }

            let fetchedBook = try await APIClient.shared.fetchBook(id: uuid)
            book = fetchedBook
            DebugLogger.info("Loaded book: \(fetchedBook.title)")
        } catch {
            DebugLogger.error("Failed to load book", error: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - BookDetailLoader_Previews

struct BookDetailLoader_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BookDetailLoader(bookId: "00000000-0000-0000-0000-000000000000")
        }
    }
}
