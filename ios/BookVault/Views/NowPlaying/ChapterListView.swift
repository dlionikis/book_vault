//
//  ChapterListView.swift
//  BookVault
//
//  Created by Claude on 2025-12-28.
//  Phase 5: Chapter Navigation
//

import SwiftUI

/// Displays a list of chapters for the current audiobook
struct ChapterListView: View {
    // MARK: - Properties

    let chapters: [Chapter]
    let currentChapterId: UUID?
    let onChapterTap: (Chapter) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationView {
            Group {
                if chapters.isEmpty {
                    emptyState
                } else {
                    chapterList
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .imageScale(.large)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No Chapters")
                .font(.headline)

            Text("This audiobook doesn't have chapter information")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chapterList: some View {
        List {
            ForEach(chapters, id: \.id) { chapter in
                ChapterRow(
                    chapter: chapter,
                    isCurrentChapter: chapter.id == currentChapterId,
                    onTap: {
                        onChapterTap(chapter)
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Chapter Row

private struct ChapterRow: View {
    let chapter: Chapter
    let isCurrentChapter: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Chapter number badge
                VStack {
                    Text("\(chapter.index)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentChapter ? .white : .primary)
                        .frame(minWidth: 32)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(isCurrentChapter ? Color.blue : Color.gray.opacity(0.2))
                        )
                }

                // Chapter title and playing indicator
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(chapter.title)
                            .font(.subheadline)
                            .fontWeight(isCurrentChapter ? .semibold : .regular)
                            .foregroundColor(isCurrentChapter ? .blue : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if isCurrentChapter {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    HStack(spacing: 4) {
                        Text("Start:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(formatTime(chapter.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(formatTime(chapter.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrentChapter ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrentChapter ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(ChapterButtonStyle(isCurrentChapter: isCurrentChapter))
        .accessibilityLabel("\(chapter.title), starts at \(formatTime(chapter.startTime)), duration \(formatTime(chapter.duration))")
        .accessibilityHint(isCurrentChapter ? "Currently playing" : "Tap to skip to this chapter")
    }

    // MARK: - Helper Methods

    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Custom Button Style

private struct ChapterButtonStyle: ButtonStyle {
    let isCurrentChapter: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        configuration.isPressed
                            ? Color.blue.opacity(0.2)  // Pressed state - more visible
                            : Color.clear
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("With Chapters") {
    ChapterListView(
        chapters: Chapter.mockChapters,
        currentChapterId: Chapter.mockChapter2.id,
        onChapterTap: { _ in }
    )
}

#Preview("Empty State") {
    ChapterListView(
        chapters: [],
        currentChapterId: nil,
        onChapterTap: { _ in }
    )
}

#Preview("Single Chapter") {
    ChapterListView(
        chapters: [Chapter.mockChapter1],
        currentChapterId: Chapter.mockChapter1.id,
        onChapterTap: { _ in }
    )
}

#Preview("Many Chapters") {
    ChapterListView(
        chapters: Array(repeating: Chapter.mockChapters, count: 4).flatMap { $0 },
        currentChapterId: Chapter.mockChapter3.id,
        onChapterTap: { _ in }
    )
}

#Preview("Dark Mode") {
    ChapterListView(
        chapters: Chapter.mockChapters,
        currentChapterId: Chapter.mockChapter2.id,
        onChapterTap: { _ in }
    )
    .preferredColorScheme(.dark)
}
