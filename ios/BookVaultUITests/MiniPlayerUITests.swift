//
//  MiniPlayerUITests.swift
//  BookVaultUITests
//
//  U5 from docs/plans/ios-ui-testing-plan.md.
//

import XCTest

/// U5 — starting playback shows the mini player, and tapping it opens the full player.
///
/// **This is the Plan B surface.** The mini-player bottom-bar change moves this
/// element and re-lays-out every screen around it, so these assertions are what guard
/// that work — they cover requirements F1, F2, F4, F5 and A1 of
/// docs/plans/ios-mini-player-bottom-bar-plan.md.
///
/// The mini player must not be present before playback: `--uitesting` suppresses
/// `ContentView`'s launch-time `loadMostRecentlyPlayedBook()`, which would otherwise
/// populate it and make "it appears" vacuously true.
///
/// Requires a running backend with a library book: `npm run dev && npm run e2e:seed`.
final class MiniPlayerUITests: UITestCase {
    /// F2 — absent when no book is loaded.
    func testMiniPlayerIsHiddenBeforePlayback() {
        logIn()

        XCTAssertFalse(
            element(withIdentifier: A11yID.MiniPlayer.root)
                .waitForExistence(timeout: 3),
            """
            The mini player should not be visible before playback starts. If this fails, \
            UITestEnvironment.shouldSkipInitialBookLoad is not suppressing the launch-time \
            auto-load, and every other assertion in this file is meaningless.
            """
        )
    }

    /// F1 — present once playback starts.
    func testStartingPlaybackShowsMiniPlayer() throws {
        logIn()
        try startPlaybackFromLibrary()

        require(
            element(withIdentifier: A11yID.MiniPlayer.root),
            "the mini player after starting playback"
        )
    }

    /// F4 — tapping the bar presents the full player.
    func testTappingMiniPlayerOpensFullPlayer() throws {
        logIn()
        try startPlaybackFromLibrary()

        // Tap the info region, not the bar container: the bar is
        // `accessibilityElement(children: .contain)` so only its children are tappable,
        // which is what keeps play/pause independent (F5).
        let info = require(
            element(withIdentifier: A11yID.MiniPlayer.info),
            "the mini player info region"
        )
        info.tap()

        require(
            element(withIdentifier: A11yID.NowPlaying.root),
            "the full player after tapping the mini player"
        )
    }

    /// F5 + A1 — play/pause toggles playback **without** presenting the full player.
    ///
    /// This was a real defect on `main`, found by this test: `MiniPlayerView` nested the
    /// play/pause `Button` inside an outer `Button` whose action was
    /// `showingFullPlayer = true`, so tapping the inner control fired the outer action
    /// too and the sheet appeared. Fixed by replacing the outer `Button` with
    /// `contentShape` + `onTapGesture` on the info region only.
    ///
    /// **Keep this assertion.** It is the regression net for F5 — reintroducing an outer
    /// `Button` anywhere in the bar fails here.
    func testMiniPlayerPlayPauseDoesNotOpenFullPlayer() throws {
        logIn()
        try startPlaybackFromLibrary()

        require(element(withIdentifier: A11yID.MiniPlayer.root), "the mini player")

        let playPause = require(app.buttons[A11yID.MiniPlayer.playPause], "play/pause")
        playPause.tap()

        // The sheet animates in, so a bare `exists` check could pass simply by racing
        // the presentation. Give it time to appear and assert it never does.
        XCTAssertFalse(
            element(withIdentifier: A11yID.NowPlaying.root).waitForExistence(timeout: 3),
            "Tapping play/pause should toggle playback, not present the full player"
        )

        // The bar itself must survive the toggle.
        XCTAssertTrue(
            element(withIdentifier: A11yID.MiniPlayer.root).exists,
            "The mini player should remain visible after toggling play/pause"
        )
    }

    /// L1 + L2 — the mini bar must not occlude content.
    ///
    /// The bar is a bottom `safeAreaInset` on the `TabView`, so the framework should
    /// shrink every screen's safe area by its height and the last row should scroll
    /// clear of it. This is the one part of L1/L2 that is assertable: scroll to the
    /// bottom of a tab with a book loaded and check the final cell is reachable.
    ///
    /// Frames are compared rather than trusting `isHittable`, which is unreliable in
    /// this app (docs/plans/ios-ui-testing-plan.md §6b).
    func testContentIsNotOccludedByMiniPlayer() throws {
        logIn()
        try startPlaybackFromLibrary()

        let miniPlayer = require(element(withIdentifier: A11yID.MiniPlayer.info), "the mini player")

        // Scroll to the end of the grid so the last cell is the bottom-most content.
        for _ in 0 ..< 6 {
            app.swipeUp()
        }

        let cells = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", A11yID.bookCellPrefix)
        )
        // Not `!cells.isEmpty`: XCUIElementQuery has no `isEmpty`, and SwiftFormat's
        // preferKeyPath/isEmpty rule will try to rewrite this if given the chance.
        let cellCount = cells.count
        guard cellCount > 0 else {
            throw XCTSkip("No book cells to measure against.")
        }

        let lastCell = cells.element(boundBy: cellCount - 1)
        guard lastCell.exists else {
            throw XCTSkip("Last cell not resolvable after scrolling.")
        }

        XCTAssertLessThanOrEqual(
            lastCell.frame.maxY,
            miniPlayer.frame.minY,
            """
            The bottom-most content (\(lastCell.frame)) extends past the top edge of the \
            mini player (\(miniPlayer.frame)) — the safe-area inset is not shrinking the \
            content area, so content is occluded (L1/L2).
            """
        )
    }

    /// V1 + L5 — the bar spans the full width and sits directly above the tab bar,
    /// without overlapping it.
    ///
    /// **Ordering note.** The bar is *above* the tab bar, not below it. The original
    /// request was for below, but that is not achievable with a system `TabView`: the
    /// tab bar is laid out as a sibling outside the inset chain and occupies the bottom
    /// strip to the window edge, so inset content placed there renders *behind* it.
    /// Measured on the simulator; see §2 of
    /// docs/plans/ios-mini-player-bottom-bar-plan.md.
    func testMiniPlayerSitsAboveTabBarFullWidth() throws {
        logIn()
        try startPlaybackFromLibrary()

        let tabBar = require(app.tabBars.firstMatch, "the tab bar")

        // Assert on the bar's *controls*, not its container frame. The container's
        // background intentionally bleeds down behind the tab bar so there is no seam
        // between the two, so its frame extends to the window bottom. What must not
        // overlap is anything interactive or readable.
        for (name, id) in [
            ("info region", A11yID.MiniPlayer.info),
            ("play/pause", A11yID.MiniPlayer.playPause),
        ] {
            let control = require(element(withIdentifier: id), "the mini player \(name)")
            XCTAssertLessThanOrEqual(
                control.frame.maxY,
                tabBar.frame.minY + 1,
                """
                The mini player \(name) (\(control.frame)) extends into the tab bar \
                (\(tabBar.frame)) — the tab bar would draw over it.
                """
            )
        }

        XCTAssertEqual(
            element(withIdentifier: A11yID.MiniPlayer.root).frame.width,
            app.windows.element(boundBy: 0).frame.width,
            accuracy: 1,
            "The mini player should span the full window width (V1)"
        )
    }

    // MARK: - Helpers

    /// Opens the first library book, starts playback, and returns to the library list
    /// with the full player dismissed.
    ///
    /// Uses Library rather than Catalog because the play button only appears for books
    /// already in the user's library.
    ///
    /// **Dismissing the full player matters.** `BookDetailView` sets
    /// `showingNowPlaying = true` when "Play Audiobook" is tapped
    /// (BookDetailView.swift:381), so playback always leaves `NowPlayingView` presented.
    /// Leaving it up made `testTappingMiniPlayerOpensFullPlayer` pass vacuously —
    /// `nowPlaying.root` already existed before the mini player was ever tapped — and
    /// made the F5 assertion fail for the wrong reason.
    private func startPlaybackFromLibrary() throws {
        app.buttons[A11yID.Tab.library].tap()

        let cell = anyBookCell
        guard cell.waitForExistence(timeout: UITestCase.defaultTimeout) else {
            throw XCTSkip(
                """
                No books in the library. These flows need a seeded library:
                  npm run dev && npm run e2e:seed
                """
            )
        }
        cell.tap()

        require(element(withIdentifier: A11yID.BookDetail.root), "the book detail screen")

        let play = app.buttons[A11yID.BookDetail.play]
        guard play.waitForExistence(timeout: UITestCase.defaultTimeout) else {
            throw XCTSkip("No play button on the detail screen — the book may not be in the library.")
        }
        play.tap()

        dismissFullPlayer()

        // Back out of the detail screen so tests start from a scrollable list.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        require(anyBookCell, "the library list after starting playback")
    }

    /// Swipes the presented `NowPlayingView` sheet away.
    ///
    /// It is presented with `.presentationDragIndicator(.visible)` and has no close
    /// button, so a downward swipe is the only dismissal.
    private func dismissFullPlayer() {
        let fullPlayer = element(withIdentifier: A11yID.NowPlaying.root)
        guard fullPlayer.waitForExistence(timeout: 5) else { return }

        app.swipeDown(velocity: .fast)

        XCTAssertTrue(
            waitForNonExistence(fullPlayer, timeout: 5),
            """
            The full player sheet is still presented after swiping down. Every assertion \
            about the mini player would then run with the sheet covering the screen.
            """
        )
    }
}
