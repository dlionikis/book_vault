//
//  MiniPlayerView.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 3.5: Mini Player UI
//

import SwiftUI

/// Persistent mini player bar that shows at the top of all screens when audio is playing
/// Compact style (70% width, right-aligned) to avoid overlapping navigation buttons
struct MiniPlayerView: View {
    @ObservedObject var audioManager = AudioPlayerManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingFullPlayer = false

    var body: some View {
        if let book = audioManager.currentBook {
            GeometryReader { geometry in
                Button(
                    action: { showingFullPlayer = true },
                    label: {
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

                            Text(book.authors.map(\.name).joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Play/Pause Button
                        Button(
                            action: { audioManager.togglePlayPause() },
                            label: {
                                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                            }
                        )
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground).opacity(0.95))
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 8, y: 2)
                    )
                    .frame(width: geometry.size.width * 0.70)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                )
                .buttonStyle(PlainButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Now playing: \(book.title)")
                .accessibilityHint("Tap to open full player")
                .sheet(isPresented: $showingFullPlayer) {
                    NowPlayingView()
                        .presentationDragIndicator(.visible)
                }
            }
            .frame(height: 68)
        }
    }

    @ViewBuilder
    private func coverArt(for _: Book) -> some View {
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

// MARK: - Previews

#Preview("Playing", traits: .sizeThatFitsLayout) {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .onAppear {
        let manager = AudioPlayerManager.shared
        manager.play(book: .mockStandard)
    }
}

#Preview("Paused", traits: .sizeThatFitsLayout) {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .onAppear {
        let manager = AudioPlayerManager.shared
        manager.play(book: .mockLongTitle)
        manager.pause()
    }
}

#Preview("Long Title", traits: .sizeThatFitsLayout) {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .onAppear {
        let manager = AudioPlayerManager.shared
        manager.play(book: .mockLongTitle)
    }
}

#Preview("Dark Mode", traits: .sizeThatFitsLayout) {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .onAppear {
        let manager = AudioPlayerManager.shared
        manager.play(book: .mockStandard)
    }
    .preferredColorScheme(.dark)
}
