//
//  MiniPlayerUITests.swift
//  BookVaultUITests
//
//  U5 (partial) from docs/plans/ios-ui-testing-plan.md.
//

import XCTest

/// U5 — the mini player is absent until playback starts.
///
/// **The rest of U5 is deferred.** Starting playback requires tapping a library cell
/// and then the play button, and those taps currently fail for the same reason as U3
/// (elements exist but report `hittable == false`). So these remain unwritten here:
///
/// - mini player appears after playback starts
/// - tapping it presents the full player
/// - play/pause is separately addressable despite
///   `.accessibilityElement(children: .combine)` — still an open question, and it
///   overlaps Plan B requirement A1
///
/// See the "Deferred" section of docs/plans/ios-ui-testing-plan.md.
///
/// What *is* covered below matters on its own: it proves
/// `UITestEnvironment.shouldSkipInitialBookLoad` actually suppresses the launch-time
/// auto-load. Without that, `ContentView` populates `currentBook` before any playback
/// and every future "the mini player appeared" assertion would pass vacuously.
final class MiniPlayerUITests: UITestCase {
    func testMiniPlayerIsHiddenBeforePlayback() {
        logIn()

        XCTAssertFalse(
            app.otherElements[A11yID.MiniPlayer.root]
                .waitForExistence(timeout: 3),
            """
            The mini player should not be visible before playback starts. If this fails, \
            UITestEnvironment.shouldSkipInitialBookLoad is not suppressing the launch-time \
            auto-load, and future playback assertions would be meaningless.
            """
        )
    }
}
