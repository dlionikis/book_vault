//
//  MiniPlayerInset.swift
//  BookVault
//
//  Reserves space for the mini player at the bottom of a screen's content.
//

import SwiftUI

// MARK: - MiniPlayerInset

/// Adds the mini player as a bottom safe-area inset.
///
/// **Where this must be applied, and why it is not one call on the `TabView`.**
///
/// Two placements were measured on the simulator and both failed:
///
/// 1. On the `TabView`. The system tab bar is laid out as a *sibling* outside the
///    TabView's inset chain and occupies the whole bottom strip to the window edge, so
///    inset content placed there renders **behind** the tab bar rather than above it.
///    (`TabBar` measured at y 791–874 on a 874pt-tall window, with the inset content at
///    y 779.7–874.) This is also why the mini bar cannot sit *below* the tab bar with a
///    system `TabView` at all — see §2 of
///    docs/plans/ios-mini-player-bottom-bar-plan.md.
/// 2. On a tab root *outside* its `NavigationStack`. The bar then draws in the right
///    place, but the `ScrollView` inside the stack derives its content inset from the
///    stack's own safe area, which an inset applied outside the stack does not change —
///    so the last row scrolled under the bar and was clipped mid-title.
///
/// So it goes **inside** the `NavigationStack`, on the scrollable content. Then the
/// framework shrinks that scroll view's content inset by the bar's height and nothing is
/// occluded (L1, L2), with no per-screen hardcoded padding (A3).
struct MiniPlayerInset: ViewModifier {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if audioPlayer.currentBook != nil {
                MiniPlayerView()
            }
        }
    }
}

extension View {
    /// Reserves space for the mini player beneath this screen's content.
    ///
    /// Apply to the scrollable content **inside** a `NavigationStack`, not to the stack
    /// or the `TabView` — see `MiniPlayerInset` for the measurements behind that.
    func miniPlayerInset() -> some View {
        modifier(MiniPlayerInset())
    }
}
