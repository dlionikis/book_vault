//
//  BookDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct BookDetailView: View {
    let book: Book
    @StateObject private var chapterManager = ChapterManager()
    @StateObject private var libraryManager = LibraryManager.shared
    @State private var showingNowPlaying = false
    @State private var isInLibrary = false
    @State private var isCheckingLibrary = false
    @State private var showingRemoveConfirmation = false
    @State private var showingSeriesDialog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cover image
                AsyncImage(url: URL(string: book.coverUrl ?? "")) { phase in
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
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
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

                    // Authors
                    if !book.authors.isEmpty {
                        HStack(spacing: 4) {
                            Text("By")
                                .foregroundColor(.secondary)
                            Text(book.authors.map { $0.name }.joined(separator: ", "))
                                .fontWeight(.medium)
                        }
                    }

                    // Narrators
                    if let narrators = book.narrators, !narrators.isEmpty {
                        HStack(spacing: 4) {
                            Text("Narrated by")
                                .foregroundColor(.secondary)
                            Text(narrators.map { $0.name }.joined(separator: ", "))
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

                        if let series = book.series, !series.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(series, id: \.asin) { seriesInfo in
                                    MetadataRow(
                                        icon: "books.vertical",
                                        label: "Series",
                                        value: "\(seriesInfo.title) #\(seriesInfo.sequence ?? "?")"
                                    )
                                }
                            }
                        }

                        // Categories
                        if let categories = book.categories, !categories.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "tag")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Categories")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    // Use simple wrapping for now
                                    HStack(alignment: .top, spacing: 6) {
                                        ForEach(categories.prefix(3), id: \.id) { category in
                                            Text(category.name)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue)
                                                .clipShape(Capsule())
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
                    if let description = book.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)

                            // Render markdown as attributed text
                            if let attributedString = try? AttributedString(
                                markdown: description,
                                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                            ) {
                                Text(attributedString)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            } else {
                                // Fallback to plain text if markdown parsing fails
                                Text(description)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Play button (isolated to prevent unnecessary parent re-renders)
                    BookPlayButton(
                        book: book,
                        chapterManager: chapterManager,
                        showingNowPlaying: $showingNowPlaying
                    )
                    .padding(.top, 8)

                    // Library button
                    LibraryButton(
                        book: book,
                        isInLibrary: $isInLibrary,
                        isCheckingLibrary: $isCheckingLibrary,
                        showingRemoveConfirmation: $showingRemoveConfirmation,
                        showingSeriesDialog: $showingSeriesDialog,
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
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            // DEBUG: Log book data once when view appears (only in debug builds)
            DebugLogger.ui("📖 Book Detail Appeared: \(book.title) (ID: \(book.id))")
            DebugLogger.verbose("Categories: \(book.categories?.map { $0.name }.joined(separator: ", ") ?? "none")")

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

// MARK: - Book Play Button

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
                if audioPlayer.currentBook?.id != book.id {
                    audioPlayer.play(book: book)
                    // Fetch chapters in background (non-blocking)
                    Task {
                        let chapters = await chapterManager.fetchChapters(bookId: book.id.uuidString)
                        audioPlayer.updateChapters(chapters)
                    }
                } else {
                    audioPlayer.resume()
                }
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
    }
}

// MARK: - Library Button

/// Library management button component
struct LibraryButton: View {
    let book: Book
    @Binding var isInLibrary: Bool
    @Binding var isCheckingLibrary: Bool
    @Binding var showingRemoveConfirmation: Bool
    @Binding var showingSeriesDialog: Bool
    let onLibraryStatusChanged: () -> Void

    @StateObject private var libraryManager = LibraryManager.shared

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
                try await libraryManager.addToLibrary(bookId: book.id.uuidString)
                await MainActor.run {
                    isInLibrary = true
                    onLibraryStatusChanged()
                }
                DebugLogger.success("Added '\(book.title)' to library")
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
            guard let firstSeries = book.series?.first,
                  let asinString = firstSeries.asin,
                  let seriesId = UUID(uuidString: asinString) else {
                DebugLogger.error("No valid series ID found")
                return
            }

            do {
                try await libraryManager.addSeriesToLibrary(seriesId: seriesId.uuidString)
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

// MARK: - Metadata Row

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

// MARK: - Flow Layout (for categories)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}

// MARK: - Previews

#Preview("Standard Book") {
    NavigationView {
        BookDetailView(book: .mockStandard)
    }
}

#Preview("Long Title with Series") {
    NavigationView {
        BookDetailView(book: .mockLongTitle)
    }
}

#Preview("Minimal Book") {
    NavigationView {
        BookDetailView(book: .mockMinimal)
    }
}

#Preview("Multiple Authors") {
    NavigationView {
        BookDetailView(book: .mockMultipleAuthors)
    }
}

#Preview("Dark Mode") {
    NavigationView {
        BookDetailView(book: .mockStandard)
    }
    .preferredColorScheme(.dark)
}
