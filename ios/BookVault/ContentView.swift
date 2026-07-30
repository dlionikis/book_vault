//
//  ContentView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

// MARK: - Tab

enum Tab {
    case catalog // All books (was library)
    case browse // Metadata browse
    case search // Keyword search
    case library // User's personal library
    case downloads // Offline downloads (Phase 7)
    case restores // Archive restore requests
    case settings // Settings and account
    case offline // Offline mode placeholder (Phase 8)
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLoadedInitialBook = false
    @State private var selectedTab: Tab = .catalog
    @State private var previousOnlineTab: Tab? // Remember tab when going offline

    /// Identifiable wrapper so a book id can drive `.sheet(item:)`.
    private struct DeepLinkedBook: Identifiable { let id: String }

    /// The book to present from a push-notification tap (drives the sheet below).
    private var deepLinkedBook: Binding<DeepLinkedBook?> {
        Binding(
            get: {
                if case let .book(id) = deepLinkManager.pendingDeepLink { return DeepLinkedBook(id: id) }
                return nil
            },
            set: { newValue in
                if newValue == nil { deepLinkManager.consume() }
            }
        )
    }

    var body: some View {
        if authManager.isRestoringSession {
            // Show loading state while restoring session from keychain
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        } else if authManager.isAuthenticated || authManager.isOfflineMode {
            // User is logged in (online) or in a local offline-only session -
            // show tab view with mini player. The networkMonitor.isConnected
            // logic below then renders the offline tab set automatically.
            TabView(selection: $selectedTab) {
                if networkMonitor.isConnected {
                    // Online mode: 6 tabs
                    CatalogView()
                        .tabItem {
                            Label("Catalog", systemImage: "books.vertical.fill")
                                .accessibilityIdentifier(A11y.Tab.catalog)
                        }
                        .tag(Tab.catalog)

                    BrowseView()
                        .tabItem {
                            Label("Browse", systemImage: "square.grid.2x2")
                                .accessibilityIdentifier(A11y.Tab.browse)
                        }
                        .tag(Tab.browse)

                    SearchView()
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                                .accessibilityIdentifier(A11y.Tab.search)
                        }
                        .tag(Tab.search)
                } else {
                    // Offline mode: Replace Catalog/Browse/Search with Offline tab
                    OfflineModeView(selectedTab: $selectedTab)
                        .tabItem {
                            Label("Offline", systemImage: "wifi.slash")
                                .accessibilityIdentifier(A11y.Tab.offline)
                        }
                        .tag(Tab.offline)
                }

                // Always show Library, Downloads, Settings
                LibraryView(selectedTab: $selectedTab)
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                            .accessibilityIdentifier(A11y.Tab.library)
                    }
                    .tag(Tab.library)

                DownloadsView()
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                            .accessibilityIdentifier(A11y.Tab.downloads)
                    }
                    .tag(Tab.downloads)

                NavigationStack {
                    RestoreRequestsView()
                }
                .tabItem {
                    Label("Restores", systemImage: "clock.arrow.circlepath")
                        .accessibilityIdentifier(A11y.Tab.restores)
                }
                .tag(Tab.restores)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                            .accessibilityIdentifier(A11y.Tab.settings)
                    }
                    .tag(Tab.settings)
            }
            .onChange(of: networkMonitor.isConnected) { oldValue, isConnected in
                DebugLogger.network("onChange triggered: \(oldValue) -> \(isConnected)")
                handleNetworkChange(isOnline: isConnected)
            }
            .task {
                // Auto-load most recently played book on first appearance.
                // Suppressed under UI testing so the mini player only appears
                // as a result of playback the test actually started.
                if !UITestEnvironment.shouldSkipInitialBookLoad,
                   !hasLoadedInitialBook, audioPlayer.currentBook == nil {
                    await loadMostRecentlyPlayedBook()
                    hasLoadedInitialBook = true
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                value: audioPlayer.currentBook != nil
            )
            // Keeps the tab bar and mini bar pinned when the keyboard shows,
            // rather than being lifted with it (L7).
            .ignoresSafeArea(.keyboard)
            .preferredColorScheme(themeManager.selectedTheme.colorScheme)
            // Phase 7b: request push authorization once authenticated so the
            // backend can notify us when a restore completes.
            .task {
                await NotificationRegistrar.shared.requestAuthorizationAndRegister()
            }
            // Phase 7b: a restore-complete notification tap opens the book here,
            // regardless of the current tab.
            .sheet(item: deepLinkedBook) { boxed in
                NavigationStack {
                    BookDetailLoader(bookId: boxed.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { deepLinkManager.consume() }
                            }
                        }
                }
            }
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
            // If we were in a local offline-only session, try to upgrade to a
            // full online session now that connectivity is back.
            if authManager.isOfflineMode {
                Task { await authManager.promoteToOnlineIfPossible() }
            }
            // Going online: restore previous tab if it was Catalog/Browse/Search
            DebugLogger
                .network(
                    "Going online - selectedTab: \(selectedTab), previousOnlineTab: \(String(describing: previousOnlineTab))"
                )
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
            // Fetch only books in user's library (not all books)
            let libraryBooks = try await LibraryManager.shared.fetchLibraryBooks()
            var booksWithProgress: [(book: Book, progress: UserProgress)] = []

            for libraryBook in libraryBooks {
                let book = libraryBook.asBook
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

            // Load the most recent book for mini-player display only (no playback/download)
            if let mostRecent = booksWithProgress.first {
                await MainActor.run {
                    audioPlayer.loadForMiniPlayer(
                        book: mostRecent.book,
                        savedPosition: mostRecent.progress.positionSeconds
                    )
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
