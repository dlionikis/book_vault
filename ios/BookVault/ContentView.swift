//
//  ContentView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

enum Tab {
    case library
    case browse
    case search
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @State private var hasLoadedInitialBook = false
    @State private var selectedTab: Tab = .library

    var body: some View {
        if authManager.isAuthenticated {
            // User is logged in - show tab view with mini player
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    BooksListView()
                        .tabItem {
                            Label("Library", systemImage: "books.vertical")
                        }
                        .tag(Tab.library)

                    BrowseView()
                        .tabItem {
                            Label("Browse", systemImage: "square.grid.2x2")
                        }
                        .tag(Tab.browse)

                    SearchView()
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .tag(Tab.search)
                }
                .task {
                    // Auto-load most recently played book on first appearance
                    if !hasLoadedInitialBook && audioPlayer.currentBook == nil {
                        await loadMostRecentlyPlayedBook()
                        hasLoadedInitialBook = true
                    }
                }

                // Mini player overlay - floats above tab bar
                if audioPlayer.currentBook != nil {
                    VStack(spacing: 0) {
                        Spacer()
                        MiniPlayerView()
                            .padding(.bottom, 49) // Tab bar height
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: audioPlayer.currentBook != nil)
                }
            }
            .ignoresSafeArea(.keyboard)
        } else {
            // User is not logged in - show login screen
            LoginView()
        }
    }

    private func loadMostRecentlyPlayedBook() async {
        do {
            // Fetch all books with progress
            let response = try await APIClient.shared.fetchBooks(page: 1, limit: 50)
            var booksWithProgress: [(book: Book, progress: UserProgress)] = []

            for book in response.books {
                if let progress = try? await ProgressManager.shared.fetchProgress(for: book.id.uuidString) {
                    // Only include books with position > 0 and last played date
                    if progress.positionSeconds > 0, progress.lastPlayed != nil {
                        booksWithProgress.append((book, progress))
                    }
                }
            }

            // Sort by last played (most recent first)
            booksWithProgress.sort { lhs, rhs in
                guard let lhsDate = lhs.progress.lastPlayed, let rhsDate = rhs.progress.lastPlayed else {
                    return false
                }
                return lhsDate > rhsDate
            }

            // Load the most recent book (paused state)
            if let mostRecent = booksWithProgress.first {
                await MainActor.run {
                    audioPlayer.play(book: mostRecent.book)
                    audioPlayer.pause()  // Immediately pause after loading
                }

                // Fetch and load chapters in background
                let chapterManager = ChapterManager()
                let chapters = await chapterManager.fetchChapters(bookId: mostRecent.book.id.uuidString)
                audioPlayer.updateChapters(chapters)
            }
        } catch {
            DebugLogger.error("Failed to load most recently played book", error: error)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
}
