//
//  SleepTimerUITests.swift
//  BookVaultUITests
//
//  Flows for the sleep timer control on the full player.
//

import XCTest

final class SleepTimerUITests: UITestCase {
    // MARK: - Helpers

    /// The sleep-timer button on the player.
    ///
    /// Matched on its accessibility label, not its identifier:
    /// `NowPlayingView` sets an identifier on its root container and SwiftUI
    /// propagates that to every descendant, so all buttons on the screen report
    /// `nowPlaying.root`. The label is the only distinguishing attribute.
    private var sleepButton: XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Sleep timer"))
            .firstMatch
    }

    /// Logs in, opens a book, and starts playback so the full player is up.
    private func openPlayer() throws {
        logIn()
        try requireSeededCatalog()
        anyBookCell.tap()
        require(app.buttons[A11yID.BookDetail.play], "the play button").tap()
        require(
            element(withIdentifier: A11yID.NowPlaying.root),
            "the full player",
            timeout: 15
        )
    }

    // MARK: - Tests

    func testSleepTimerButtonIsVisibleOnPlayer() throws {
        try openPlayer()

        require(sleepButton, "the sleep timer button")
        XCTAssertEqual(
            sleepButton.label,
            "Sleep timer, off",
            "Should read as off before anything is armed"
        )
    }

    func testSleepTimerButtonOpensPicker() throws {
        try openPlayer()

        require(sleepButton, "the sleep timer button").tap()

        require(app.staticTexts["Sleep Timer"], "the picker title")
        XCTAssertTrue(app.buttons["8 minutes"].firstMatch.exists)
        XCTAssertTrue(app.buttons["90 minutes"].firstMatch.exists)
    }

    func testSelectingPresetDismissesPickerAndStartsCountdown() throws {
        try openPlayer()

        require(sleepButton, "the sleep timer button").tap()
        require(app.buttons["15 minutes"].firstMatch, "the 15 minute preset").tap()

        // Sheet closes.
        XCTAssertTrue(
            waitForNonExistence(app.staticTexts["Sleep Timer"], timeout: 5),
            "Picker should dismiss after choosing a preset"
        )

        // Button now reports a countdown rather than "off".
        let armed = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Sleep timer,"))
            .firstMatch
        require(armed, "the armed sleep timer button")
        XCTAssertNotEqual(armed.label, "Sleep timer, off", "Expected a running countdown")
        XCTAssertTrue(
            armed.label.contains("minutes"),
            "Expected remaining time in the label, got '\(armed.label)'"
        )
    }

    func testTurningTimerOffReturnsButtonToIdle() throws {
        try openPlayer()

        // Arm it.
        require(sleepButton, "the sleep timer button").tap()
        require(app.buttons["15 minutes"].firstMatch, "the 15 minute preset").tap()
        _ = waitForNonExistence(app.staticTexts["Sleep Timer"], timeout: 5)

        // Turn it off. The row sits above the presets precisely so it stays
        // reachable once the armed header takes the top of the sheet.
        require(sleepButton, "the armed sleep timer button").tap()
        require(app.buttons["Turn Off Sleep Timer"], "the turn-off row").tap()
        _ = waitForNonExistence(app.staticTexts["Sleep Timer"], timeout: 5)

        XCTAssertEqual(
            sleepButton.label,
            "Sleep timer, off",
            "Button should return to the idle label"
        )
    }
}
