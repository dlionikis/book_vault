//
//  NowPlayingHarnessView.swift
//  BookVault
//
//  Renders the real NowPlayingView against mock data for layout screenshots.
//

import SwiftUI

/// Hosts `NowPlayingView` with a mock book and chapters loaded, so its layout
/// can be inspected without a backend, a session or an audio stream.
///
/// Only reachable under `--uitesting --harness-now-playing`; see
/// `UITestEnvironment.shouldShowNowPlayingHarness`.
struct NowPlayingHarnessView: View {
    var body: some View {
        NowPlayingView()
            .onAppear {
                // State is populated directly rather than via play(book:),
                // which would start a real async load that fails without a
                // network and clears everything back out.
                let manager = AudioPlayerManager.shared
                manager.currentBook = .mockScreenshot

                // Mid-chapter-2, so every time label has a non-trivial value
                // and "time left in book" is neither the full runtime nor zero.
                manager.currentTime = 2000
                manager.duration = 29_520

                // After currentTime: updateChapters resolves the current
                // chapter against it, so the reverse order leaves
                // currentChapterId nil and the chapter row unrendered.
                manager.updateChapters(Chapter.mockChapters)
            }
    }
}
