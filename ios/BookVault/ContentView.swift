//
//  ContentView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

enum Tab {
    case catalog   // All books (was library)
    case browse    // Metadata browse
    case search    // Keyword search
    case library   // User's personal library
    case downloads // Offline downloads (Phase 7)
    case settings  // Settings and account
    case offline   // Offline mode placeholder (Phase 8)
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @State private var hasLoadedInitialBook = false
    @State private var selectedTab: Tab = .catalog
    @State private var previousOnlineTab: Tab? = nil  // Remember tab when going offline

    var body: some View {
        if authManager.isAuthenticated {
            // User is logged in - show tab view with mini player
            ZStack(alignment: .top) {
                TabView(selection: $selectedTab) {
                    if networkMonitor.isConnected {
                        // Online mode: 6 tabs
                        CatalogView()
                            .tabItem {
                                Label("Catalog", systemImage: "books.vertical.fill")
                            }
                            .tag(Tab.catalog)

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
                    } else {
                        // Offline mode: Replace Catalog/Browse/Search with Offline tab
                        OfflineModeView(selectedTab: $selectedTab)
                            .tabItem {
                                Label("Offline", systemImage: "wifi.slash")
                            }
                            .tag(Tab.offline)
                    }

                    // Always show Library, Downloads, Settings
                    LibraryView(selectedTab: $selectedTab)
                        .tabItem {
                            Label("Library", systemImage: "books.vertical")
                        }
                        .tag(Tab.library)

                    DownloadsView()
                        .tabItem {
                            Label("Downloads", systemImage: "arrow.down.circle")
                        }
                        .tag(Tab.downloads)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(Tab.settings)
                }
                .onChange(of: networkMonitor.isConnected) { oldValue, isConnected in
                    DebugLogger.network("onChange triggered: \(oldValue) -> \(isConnected)")
                    handleNetworkChange(isOnline: isConnected)
                }
                .task {
                    // Auto-load most recently played book on first appearance
                    if !hasLoadedInitialBook && audioPlayer.currentBook == nil {
                        await loadMostRecentlyPlayedBook()
                        hasLoadedInitialBook = true
                    }
                }

                // Mini player overlay - floats at top, below navigation bar
                if audioPlayer.currentBook != nil {
                    VStack(spacing: 0) {
                        MiniPlayerView()
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: audioPlayer.currentBook != nil)
                }
            }
            .ignoresSafeArea(.keyboard)
            .preferredColorScheme(themeManager.selectedTheme.colorScheme)
        } else {
            // User is not logged in - show login screen
            LoginView()
                .preferredColorScheme(themeManager.selectedTheme.colorScheme)
        }
    }

    /// Handle tab transitions when network state changes
    private func handleNetworkChange(isOnline: Bool) {
        DebugLogger.network("handleNetworkChange called with isOnline: \(isOnline), currentTab: \(selectedTab)")
        if isOnline {
            // Going online: restore previous tab if it was Catalog/Browse/Search
            DebugLogger.network("Going online - selectedTab: \(selectedTab), previousOnlineTab: \(String(describing: previousOnlineTab))")
            if selectedTab == .offline {
                if let previousTab = previousOnlineTab {
                    DebugLogger.network("Restoring previous tab: \(previousTab)")
                    selectedTab = previousTab
                } else {
                    DebugLogger.network("No previous tab, switching to catalog")
                    selectedTab = .catalog
                }
            }
            previousOnlineTab = nil
        } else {
            // Going offline: switch from Catalog/Browse/Search to Offline tab
            let onlineOnlyTabs: [Tab] = [.catalog, .browse, .search]
            if onlineOnlyTabs.contains(selectedTab) {
                DebugLogger.network("Going offline - saving current tab: \(selectedTab)")
                previousOnlineTab = selectedTab
                selectedTab = .offline
            }
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
