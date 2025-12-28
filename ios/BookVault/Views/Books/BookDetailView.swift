//
//  BookDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct BookDetailView: View {
    let book: Book
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @StateObject private var chapterManager = ChapterManager()
    @State private var showingNowPlaying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                            value: formatRuntime(book.runtimeMinutes)
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
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Image(systemName: "tag")
                                        .foregroundColor(.blue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Categories")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        FlowLayout(spacing: 6) {
                                            ForEach(categories, id: \.id) { category in
                                                Text(category.name)
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color.blue.opacity(0.1))
                                                    .foregroundColor(.blue)
                                                    .clipShape(Capsule())
                                            }
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

                    // Play button
                    Button {
                        if audioPlayer.currentBook?.id == book.id && audioPlayer.isPlaying {
                            // Same book and playing - just pause (don't show player)
                            audioPlayer.pause()
                        } else {
                            // Start playing or resume, and show full player
                            if audioPlayer.currentBook?.id != book.id {
                                audioPlayer.play(book: book)
                                // Phase 5: Fetch chapters in background (non-blocking)
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
                            Image(systemName: audioPlayer.currentBook?.id == book.id && audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            Text(audioPlayer.currentBook?.id == book.id && audioPlayer.isPlaying ? "Playing" : "Play Audiobook")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)
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
