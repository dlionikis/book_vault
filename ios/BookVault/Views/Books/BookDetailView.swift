//
//  BookDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

// MARK: - BookDetailView

struct BookDetailView: View {
    let book: Book
    @StateObject private var chapterManager = ChapterManager()
    @ObservedObject private var libraryManager = LibraryManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var storageManager = StorageManager.shared
    @State private var showingNowPlaying = false
    @State private var isInLibrary = false
    @State private var isCheckingLibrary = false
    @State private var showingRemoveConfirmation = false
    @State private var showingSeriesDialog = false
    @State private var noticeMessage: String?

    /// Check if book is downloaded for offline playback
    private var isBookDownloaded: Bool {
        storageManager.isBookDownloaded(bookId: book.id.uuidString)
    }

    /// Check if we're currently online
    private var isOnline: Bool {
        networkMonitor.isConnected
    }

    /// The book's audio is archived in cold storage or a restore is in flight
    /// (absent archiveStatus is treated as available for backward compatibility).
    private var isArchivedOrRestoring: Bool {
        book.archiveStatus == .archived || book.archiveStatus == .restoring
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cover image
                CachedCoverImage(bookId: book.id, coverUrl: book.coverUrl)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .padding(.horizontal)

                // Book info
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(book.title)
                        .font(.title)
                        .fontWeight(.bold)

                    // Authors (tappable links to author detail)
                    if !book.authors.isEmpty {
                        HStack(spacing: 4) {
                            Text("By")
                                .foregroundColor(.secondary)
                            ForEach(Array(book.authors.enumerated()), id: \.element.id) { index, author in
                                if index > 0 {
                                    Text(",")
                                        .foregroundColor(.secondary)
                                }
                                NavigationLink(destination: AuthorDetailView(authorId: author.id.uuidString)) {
                                    Text(author.name)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }

                    // Narrators (tappable links to narrator detail)
                    if let narrators = book.narrators, !narrators.isEmpty {
                        HStack(spacing: 4) {
                            Text("Narrated by")
                                .foregroundColor(.secondary)
                            ForEach(Array(narrators.enumerated()), id: \.element.id) { index, narrator in
                                if index > 0 {
                                    Text(",")
                                        .foregroundColor(.secondary)
                                }
                                NavigationLink(destination: NarratorDetailView(narratorId: narrator.id.uuidString)) {
                                    Text(narrator.name)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .font(.subheadline)
                    }

                    Divider()

                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        if let releaseDate = book.releaseDate {
                            MetadataRow(
                                icon: "calendar",
                                label: "Release Date",
                                value: formatDate(releaseDate)
                            )
                        }

                        MetadataRow(
                            icon: "clock",
                            label: "Runtime",
                            value: formatRuntime(book.runtimeMinutes ?? 0)
                        )

                        if let publisher = book.publisher {
                            MetadataRow(
                                icon: "building.2",
                                label: "Publisher",
                                value: publisher
                            )
                        }

                        // Series (tappable links to series detail)
                        if let series = book.series, !series.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(series, id: \.id) { seriesInfo in
                                    HStack(spacing: 12) {
                                        Image(systemName: "books.vertical")
                                            .foregroundColor(.blue)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Series")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            NavigationLink(destination: SeriesDetailView(seriesId: seriesInfo.id.uuidString)) {
                                                Text("\(seriesInfo.title) #\(seriesInfo.sequence.map { String($0) } ?? "?")")
                                                    .font(.subheadline)
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Categories (tappable links to category detail)
                        if let categories = book.categories, !categories.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "tag")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Categories")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    // Tappable category pills
                                    HStack(alignment: .top, spacing: 6) {
                                        ForEach(categories.prefix(3), id: \.id) { category in
                                            NavigationLink(destination: CategoryDetailView(categoryId: category.id.uuidString)) {
                                                Text(category.name)
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .foregroundColor(.accentColor)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        if categories.count > 3 {
                                            Text("+\(categories.count - 3)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Description (expecting markdown from backend)
                    if let publisherSummary = book.publisherSummary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)

                            // Render markdown as attributed text
                            if let attributedString = try? AttributedString(
                                markdown: publisherSummary,
                                options: AttributedString
                                    .MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                            ) {
                                Text(attributedString)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            } else {
                                // Fallback to plain text if markdown parsing fails
                                Text(publisherSummary)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Play and Download buttons (only shown if book is in library)
                    if isInLibrary {
                        // A book already downloaded locally plays regardless of its
                        // archive status (the file is on-device). Otherwise, when the
                        // audio is archived / restoring, show the restore CTA in place
                        // of Play + Download.
                        if !isBookDownloaded, isOnline, isArchivedOrRestoring {
                            BookRestoreCTA(book: book)
                                .padding(.top, 8)
                        } else {
                            // Play button: show if online OR if book is downloaded for offline playback
                            if isOnline || isBookDownloaded {
                                BookPlayButton(
                                    book: book,
                                    chapterManager: chapterManager,
                                    showingNowPlaying: $showingNowPlaying
                                )
                                .padding(.top, 8)
                            } else {
                                // Offline and not downloaded - show unavailable message
                                HStack {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.secondary)
                                    Text("Download to play offline")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.top, 8)
                            }

                            // Download button (Phase 7) - only show when online
                            if isOnline {
                                DownloadButton(book: book)
                            }
                        }
                    } else if isCheckingLibrary {
                        // Show placeholder while checking library status
                        HStack {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Checking library...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                    }

                    // Library button
                    LibraryButton(
                        book: book,
                        isInLibrary: $isInLibrary,
                        isCheckingLibrary: $isCheckingLibrary,
                        showingRemoveConfirmation: $showingRemoveConfirmation,
                        showingSeriesDialog: $showingSeriesDialog,
                        noticeMessage: $noticeMessage,
                        onLibraryStatusChanged: {
                            // Refresh library status after add/remove
                            Task {
                                await checkLibraryStatus()
                            }
                        }
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11y.BookDetail.root)
        .sheet(isPresented: $showingNowPlaying) {
            // Tapping the player's title while this book's page is already
            // underneath should just close the sheet, not stack a duplicate.
            NowPlayingView(presentedFromBookId: book.id)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            // DEBUG: Log book data once when view appears (only in debug builds)
            DebugLogger.ui("📖 Book Detail Appeared: \(book.title) (ID: \(book.id))")
            DebugLogger.verbose("Categories: \(book.categories?.map(\.name).joined(separator: ", ") ?? "none")")

            // Dump full JSON only if verbose logging is enabled
            if let jsonData = try? JSONEncoder().encode(book),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                DebugLogger.verbose("Full Book JSON:\n\(jsonString)")
            }

            // Check library status
            Task {
                await checkLibraryStatus()
            }
        }
        .overlay(alignment: .top) {
            if let notice = noticeMessage {
                Text(notice)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: noticeMessage)
            }
        }
    }

    // MARK: - Library Status Check

    private func checkLibraryStatus() async {
        isCheckingLibrary = true
        defer { isCheckingLibrary = false }

        do {
            isInLibrary = try await libraryManager.isInLibrary(bookId: book.id.uuidString)
            DebugLogger.ui("Library status for \(book.title): \(isInLibrary)")
        } catch {
            DebugLogger.error("Failed to check library status", error: error)
            isInLibrary = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") \(mins) min"
        } else {
            return "\(mins) minutes"
        }
    }
}

// MARK: - BookPlayButton

/// Isolated play button component that observes audio player state
/// This prevents BookDetailView from re-rendering on every audio player update
struct BookPlayButton: View {
    let book: Book
    @ObservedObject var chapterManager: ChapterManager
    @Binding var showingNowPlaying: Bool
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    private var isCurrentBookPlaying: Bool {
        audioPlayer.currentBook?.id == book.id && audioPlayer.isPlaying
    }

    var body: some View {
        Button {
            if isCurrentBookPlaying {
                // Same book and playing - just pause (don't show player)
                audioPlayer.pause()
            } else {
                // Start playing or resume, and show full player
                // Always call play() - it handles resume internally when player is ready
                // play(book:) loads chapters itself, so no fetch is needed here.
                audioPlayer.play(book: book)
                showingNowPlaying = true
            }
        } label: {
            HStack {
                Image(systemName: isCurrentBookPlaying ? "pause.fill" : "play.fill")
                Text(isCurrentBookPlaying ? "Playing" : "Play Audiobook")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier(A11y.BookDetail.play)
    }
}

// MARK: - LibraryButton

/// Library management button component
struct LibraryButton: View {
    let book: Book
    @Binding var isInLibrary: Bool
    @Binding var isCheckingLibrary: Bool
    @Binding var showingRemoveConfirmation: Bool
    @Binding var showingSeriesDialog: Bool
    @Binding var noticeMessage: String?
    let onLibraryStatusChanged: () -> Void

    @ObservedObject private var libraryManager = LibraryManager.shared

    private var hasSeries: Bool {
        book.series?.isEmpty == false
    }

    var body: some View {
        Button {
            if isInLibrary {
                // Show remove confirmation
                showingRemoveConfirmation = true
            } else {
                // Show series dialog if book has series, otherwise add directly
                if hasSeries {
                    showingSeriesDialog = true
                } else {
                    addBookToLibrary()
                }
            }
        } label: {
            HStack {
                Image(systemName: isInLibrary ? "checkmark.circle.fill" : "plus")
                Text(isInLibrary ? "In Library" : "Add to Library")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isInLibrary ? Color.green : Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isCheckingLibrary || libraryManager.isLoading)
        .confirmationDialog(
            "Remove from Library?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                removeBookFromLibrary()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Add to Library",
            isPresented: $showingSeriesDialog,
            titleVisibility: .visible
        ) {
            VStack {
                Text("This book is part of a series.")
                Text("What would you like to add?")
            }

            Button("Add Entire Series") {
                addSeriesToLibrary()
            }
            Button("Add Just This Book") {
                addBookToLibrary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This book is part of a series. What would you like to add?")
        }
    }

    private func addBookToLibrary() {
        Task {
            do {
                let message = try await libraryManager.addToLibrary(bookId: book.id.uuidString)
                await MainActor.run {
                    isInLibrary = true
                    onLibraryStatusChanged()

                    // Show notice if book was already in library
                    if message.lowercased().contains("already") {
                        noticeMessage = message
                        // Auto-dismiss after 2 seconds
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run {
                                noticeMessage = nil
                            }
                        }
                    }
                }
                DebugLogger.success("Added '\(book.title)' to library: \(message)")
            } catch {
                DebugLogger.error("Failed to add book to library", error: error)
            }
        }
    }

    private func removeBookFromLibrary() {
        Task {
            do {
                try await libraryManager.removeFromLibrary(bookId: book.id.uuidString)
                await MainActor.run {
                    isInLibrary = false
                    onLibraryStatusChanged()
                }
                DebugLogger.success("Removed '\(book.title)' from library")
            } catch {
                DebugLogger.error("Failed to remove book from library", error: error)
            }
        }
    }

    private func addSeriesToLibrary() {
        Task {
            // Get the first series ID
            guard let firstSeries = book.series?.first else {
                DebugLogger.error("No valid series ID found")
                return
            }

            do {
                try await libraryManager.addSeriesToLibrary(seriesId: firstSeries.id.uuidString)
                await MainActor.run {
                    isInLibrary = true
                    onLibraryStatusChanged()
                }
                DebugLogger.success("Added series '\(firstSeries.title)' to library")
            } catch {
                DebugLogger.error("Failed to add series to library", error: error)
                // Fallback to adding just this book
                addBookToLibrary()
            }
        }
    }
}

// MARK: - MetadataRow

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - DownloadButton

/// Download management button component
struct DownloadButton: View {
    let book: Book
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var storageManager = StorageManager.shared
    @State private var showingDeleteConfirmation = false
    @State private var downloadError: String?
    @State private var showingError = false

    private var bookId: String {
        book.id.uuidString
    }

    private var downloadState: DownloadState {
        downloadManager.downloadState(for: bookId)
    }

    private var isDownloaded: Bool {
        storageManager.isBookDownloaded(bookId: bookId)
    }

    private var downloadedSize: Int64? {
        storageManager.downloadedFileSize(for: bookId)
    }

    var body: some View {
        VStack(spacing: 8) {
            switch downloadState {
            case .notDownloaded:
                // Show download button
                Button {
                    startDownload()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Download for Offline")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

            case .waiting:
                // Show waiting state
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Preparing download...")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case let .downloading(progress):
                // Show download progress
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.blue)

                    HStack {
                        Text("\(Int(progress * 100))% downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Cancel") {
                            downloadManager.cancelDownload(bookId: bookId)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case let .backgroundDownloading(lastProgress):
                // Show background download state
                VStack(spacing: 8) {
                    ProgressView(value: lastProgress)
                        .tint(.blue)

                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.blue)
                        Text("Downloading in background...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("\(Int(lastProgress * 100))% when last checked")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button("Cancel") {
                        downloadManager.cancelDownload(bookId: bookId)
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case let .paused(progress):
                // Show paused state with resume option
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.orange)

                    HStack {
                        Text("Paused at \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Resume") {
                            Task {
                                try? await downloadManager.resumeDownload(book: book)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .completed:
                // Show downloaded state with delete option
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Downloaded")
                        Spacer()
                        if let size = downloadedSize {
                            Text(StorageManager.formatFileSize(size))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

            case let .failed(errorMessage):
                // Show error state with retry option
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Download failed")
                            .foregroundColor(.red)
                    }

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        startDownload()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case let .restoring(estimatedCompletion):
                // Archived in cold storage — a restore was initiated; downloading
                // becomes available once it finishes (~3-5h).
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.orange)
                        Text("Restoring from archive…")
                            .foregroundColor(.primary)
                    }

                    Text(ArchiveStatusFormatter.restoringDetail(estimatedCompletion: estimatedCompletion))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            "Delete Download?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Download", role: .destructive) {
                deleteDownload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the downloaded file from your device. You can always download it again.")
        }
        .alert("Download Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(downloadError ?? "An unknown error occurred")
        }
    }

    private func startDownload() {
        Task {
            do {
                try await downloadManager.startDownload(book: book)
            } catch let error as DownloadError {
                downloadError = error.localizedDescription
                showingError = true
            } catch {
                downloadError = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteDownload() {
        do {
            try downloadManager.deleteDownload(bookId: bookId)
        } catch {
            downloadError = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Previews

#Preview("Screenshot") {
    NavigationStack {
        BookDetailView(book: .mockScreenshot)
    }
}

#Preview("Standard Book") {
    NavigationStack {
        BookDetailView(book: .mockStandard)
    }
}

#Preview("Long Title with Series") {
    NavigationStack {
        BookDetailView(book: .mockLongTitle)
    }
}

#Preview("Minimal Book") {
    NavigationStack {
        BookDetailView(book: .mockMinimal)
    }
}

#Preview("Multiple Authors") {
    NavigationStack {
        BookDetailView(book: .mockMultipleAuthors)
    }
}

#Preview("Dark Mode") {
    NavigationStack {
        BookDetailView(book: .mockStandard)
    }
    .preferredColorScheme(.dark)
}
