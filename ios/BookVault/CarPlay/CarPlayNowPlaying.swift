//
//  CarPlayNowPlaying.swift
//  BookVault
//
//  CarPlay task B7 — Now Playing template configuration.
//

import CarPlay
import UIKit

/// Configures `CPNowPlayingTemplate.shared`.
///
/// The template itself is system-provided and binds to `MPNowPlayingInfoCenter`,
/// which `AudioPlayerManager.updateNowPlayingInfo()` already populates — title,
/// artist, artwork, elapsed, duration, rate. Nothing here reimplements playback;
/// this only decides which extra buttons appear and what they do.
@MainActor
enum CarPlayNowPlaying {
    /// Which chapter to move to from a given position.
    ///
    /// Pulled out as a pure function so the edge cases are testable without
    /// CarPlay, a player, or an audio session. The rules:
    ///
    /// - **Previous** restarts the current chapter when you are more than
    ///   `restartThreshold` into it, and only jumps back a chapter when you are
    ///   near its start. This is the convention every audio player uses, and it
    ///   is what makes a single "back" press feel right while driving.
    /// - **Next** moves forward one chapter, and is `nil` on the last one.
    enum ChapterStep {
        case previous
        case next
    }

    /// How far into a chapter "previous" starts meaning "restart this one"
    /// rather than "go back one".
    static let restartThreshold: TimeInterval = 3

    /// Resolve a chapter step, or `nil` when there is nowhere to go.
    ///
    /// Returns the chapter to seek to. For `.previous` that may be the *current*
    /// chapter (a restart).
    static func chapter(
        for step: ChapterStep,
        chapters: [Chapter],
        currentTime: TimeInterval
    ) -> Chapter? {
        guard !chapters.isEmpty else { return nil }

        let ordered = chapters.sorted { $0.startTime < $1.startTime }
        guard let index = ordered.lastIndex(where: { $0.startTime <= currentTime }) else {
            // Before the first chapter starts: next goes to the first, previous
            // has nowhere to go.
            return step == .next ? ordered.first : nil
        }

        switch step {
        case .next:
            let nextIndex = ordered.index(after: index)
            return nextIndex < ordered.endIndex ? ordered[nextIndex] : nil

        case .previous:
            let current = ordered[index]
            let elapsed = currentTime - current.startTime
            if elapsed > restartThreshold {
                return current // restart, don't skip back
            }
            let previousIndex = ordered.index(before: index)
            return previousIndex >= ordered.startIndex ? ordered[previousIndex] : current
        }
    }

    /// Whether chapter buttons should be shown at all.
    ///
    /// Q4's graceful degradation: a book with no chapters gets no chapter
    /// buttons rather than dead controls. A single chapter is also not worth
    /// navigating.
    static func shouldShowChapterButtons(chapters: [Chapter]) -> Bool {
        chapters.count > 1
    }

    // MARK: - Configuration

    /// Apply the current player state to the shared Now Playing template.
    ///
    /// Safe to call repeatedly; it fully replaces the button set each time.
    static func configure(
        template: CPNowPlayingTemplate = .shared,
        player: AudioPlayerManager = .shared
    ) {
        // No "up next" queue and no album-artist drill-down: neither exists in
        // this app, and CarPlay renders dead buttons if they are enabled.
        template.isUpNextButtonEnabled = false
        template.isAlbumArtistButtonEnabled = false

        var buttons: [CPNowPlayingButton] = []

        if shouldShowChapterButtons(chapters: player.chapters) {
            buttons.append(CPNowPlayingImageButton(image: Self.chapterImage(.previous)) { _ in
                Task { @MainActor in
                    step(.previous, player: player)
                }
            })
            buttons.append(CPNowPlayingImageButton(image: Self.chapterImage(.next)) { _ in
                Task { @MainActor in
                    step(.next, player: player)
                }
            })
        }

        // System-provided: CarPlay renders and cycles the rate label itself, we
        // only apply the result. `setPlaybackRate` already exists on the player.
        buttons.append(CPNowPlayingPlaybackRateButton { _ in
            Task { @MainActor in
                player.setPlaybackRate(nextPlaybackRate(after: player.playbackRate))
            }
        })

        template.updateNowPlayingButtons(buttons)
    }

    /// Perform a chapter step against the player.
    static func step(_ step: ChapterStep, player: AudioPlayerManager = .shared) {
        guard let target = chapter(
            for: step,
            chapters: player.chapters,
            currentTime: player.currentTime
        ) else { return }
        player.skipToChapter(target)
    }

    /// Cycle through the same rates the phone UI offers.
    static func nextPlaybackRate(after current: Float) -> Float {
        let rates: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]
        guard let index = rates.firstIndex(where: { abs($0 - current) < 0.01 }) else {
            return 1.0
        }
        return rates[(index + 1) % rates.count]
    }

    private static func chapterImage(_ step: ChapterStep) -> UIImage {
        let name = step == .previous ? "backward.end.fill" : "forward.end.fill"
        return UIImage(systemName: name) ?? UIImage()
    }
}
