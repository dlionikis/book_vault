//
//  MiniPlayerView.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 3.5: Mini Player UI
//

import SwiftUI

// MARK: - MiniPlayerView

/// Persistent mini player bar pinned to the bottom of the window, below the tab bar.
///
/// Rendered as `ContentView`'s bottom `safeAreaInset`, so the framework shrinks every
/// screen's safe area by this bar's height — content insets are handled automatically
/// and nothing here may hardcode a height (see A3 in
/// docs/plans/ios-mini-player-bottom-bar-plan.md).
///
/// The bar sizes to its content so Dynamic Type grows it, and the material background
/// extends into the bottom safe area beneath the row.
struct MiniPlayerView: View {
    @ObservedObject var audioManager = AudioPlayerManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingFullPlayer = false

    var body: some View {
        if let book = audioManager.currentBook {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 12) {
                    // Tapping anywhere in this region opens the full player. It is a
                    // `contentShape` + `onTapGesture` rather than a `Button` on purpose:
                    // wrapping the row in a Button made the nested play/pause Button fire
                    // *both* actions, so pausing also presented the sheet (F5/A1).
                    HStack(spacing: 12) {
                        coverArt(for: book)

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

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showingFullPlayer = true }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Now playing: \(book.title)")
                    .accessibilityHint("Opens the full player")
                    .accessibilityIdentifier(A11y.MiniPlayer.info)

                    // Its own accessibility element, so VoiceOver can reach play/pause
                    // independently of the label above (A1).
                    Button(
                        action: { audioManager.togglePlayPause() },
                        label: {
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundColor(.primary)
                                // ≥44x44pt hit target (A2).
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier(A11y.MiniPlayer.playPause)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            // Material rather than a solid fill so content scrolling beneath reads as
            // layered, matching the tab bar sitting directly below (V2).
            .background(.bar)
            // Children are addressable individually; the bar itself is not one element.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11y.MiniPlayer.root)
            .transition(barTransition)
            .sheet(isPresented: $showingFullPlayer) {
                NowPlayingView()
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Slides up from the bottom edge, or cross-fades under Reduce Motion (A5).
    private var barTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private func coverArt(for book: Book) -> some View {
        CachedCoverImage(bookId: book.id, coverUrl: book.coverUrl)
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - MiniPlayerPreviewHost

/// Previewed inside a `safeAreaInset` to match how `ContentView` mounts it: the bar
/// spans the full width and the material extends into the bottom safe area.
private struct MiniPlayerPreviewHost<Content: View>: View {
    @ViewBuilder var configure: () -> Content

    var body: some View {
        List(0 ..< 20, id: \.self) { index in
            Text("Row \(index)")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView()
        }
        .overlay { configure().frame(width: 0, height: 0) }
    }
}

#Preview("Playing") {
    MiniPlayerPreviewHost {
        Color.clear.onAppear {
            AudioPlayerManager.shared.play(book: .mockStandard)
        }
    }
}

#Preview("Paused") {
    MiniPlayerPreviewHost {
        Color.clear.onAppear {
            let manager = AudioPlayerManager.shared
            manager.play(book: .mockStandard)
            manager.pause()
        }
    }
}

#Preview("Long Title") {
    MiniPlayerPreviewHost {
        Color.clear.onAppear {
            AudioPlayerManager.shared.play(book: .mockLongTitle)
        }
    }
}

#Preview("Dark Mode") {
    MiniPlayerPreviewHost {
        Color.clear.onAppear {
            AudioPlayerManager.shared.play(book: .mockStandard)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Accessibility XL") {
    MiniPlayerPreviewHost {
        Color.clear.onAppear {
            AudioPlayerManager.shared.play(book: .mockLongTitle)
        }
    }
    .environment(\.sizeCategory, .accessibilityExtraLarge)
}
