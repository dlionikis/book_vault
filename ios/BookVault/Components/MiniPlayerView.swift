//
//  MiniPlayerView.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 3.5: Mini Player UI
//

import SwiftUI

/// Persistent mini player bar that shows at the bottom of all screens when audio is playing
struct MiniPlayerView: View {
    @ObservedObject var audioManager = AudioPlayerManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let book = audioManager.currentBook {
            NavigationLink(destination: NowPlayingView()) {
                HStack(spacing: 12) {
                    // Cover Art
                    coverArt(for: book)

                    // Book Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        Text(book.authors.map { $0.name }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Play/Pause Button
                    Button(action: {
                        audioManager.togglePlayPause()
                    }) {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(.systemBackground).opacity(0.95))
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 8, y: -2)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing: \(book.title)")
            .accessibilityHint("Tap to open full player")
        }
    }

    @ViewBuilder
    private func coverArt(for book: Book) -> some View {
        // Use cached cover image if available
        if let coverImage = audioManager.currentBookCoverImage {
            Image(uiImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // Placeholder while loading
            ZStack {
                Color(.systemGray5)
                Image(systemName: "book.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Preview

#Preview("Mini Player - Playing", traits: .sizeThatFitsLayout) {
    VStack {
        Spacer()
        MiniPlayerView()
    }
}

#Preview("Mini Player - Dark Mode", traits: .sizeThatFitsLayout) {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .preferredColorScheme(.dark)
}
