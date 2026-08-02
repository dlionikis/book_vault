//
//  NowPlayingLayoutUITests.swift
//  BookVaultUITests
//
//  Layout checks for the full player, rendered against mock data.
//

import XCTest

/// Renders `NowPlayingView` via the harness (no backend, no session, no audio)
/// and asserts the vertical arrangement.
///
/// Does not subclass `UITestCase`: that launches the app into the normal login
/// flow, and this needs the harness launch argument instead.
final class NowPlayingLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--harness-now-playing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    /// Attaches a screenshot so the layout can be eyeballed from the test
    /// results bundle.
    func testCaptureLayout() throws {
        XCTAssertTrue(
            app.staticTexts["Chapter 2"].waitForExistence(timeout: 20),
            "Expected the harness to render the player"
        )

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "now-playing-layout"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The controls block should sit against the bottom of the sheet rather
    /// than directly under the title, which is what leaves a visible gap.
    func testControlsAreAnchoredToTheBottom() throws {
        XCTAssertTrue(
            app.staticTexts["Chapter 2"].waitForExistence(timeout: 20),
            "Expected the harness to render the player"
        )

        let window = app.windows.firstMatch.frame
        let sleepButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Sleep timer"))
            .firstMatch
        XCTAssertTrue(sleepButton.waitForExistence(timeout: 5), "Expected the sleep button")

        // The gap below the last control, as a fraction of the window. The old
        // fixed-percentage layout left ~17% here; anything that large reads as
        // the sheet being unfinished.
        let gapBelow = window.maxY - sleepButton.frame.maxY
        XCTAssertLessThan(
            gapBelow / window.height,
            0.12,
            "Controls should be anchored near the bottom; gap was \(gapBelow)pt of \(window.height)pt"
        )
    }

    /// The gap between the two blocks is intentional breathing room, but it
    /// shouldn't grow back into the empty band the fixed-percentage layout left.
    func testGapBetweenBlocksStaysModest() throws {
        let author = app.staticTexts["Marina Solano"]
        XCTAssertTrue(author.waitForExistence(timeout: 20), "Expected the author label")

        let chapterRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Chapter 2:"))
            .firstMatch
        XCTAssertTrue(chapterRow.waitForExistence(timeout: 5), "Expected the chapter row")

        let window = app.windows.firstMatch.frame
        let gap = chapterRow.frame.minY - author.frame.maxY
        XCTAssertLessThan(
            gap / window.height,
            0.15,
            "Mid-screen gap should stay modest; was \(gap)pt of \(window.height)pt"
        )
    }

    /// The slack should collect between the title and the chapter row, so the
    /// two blocks read as top- and bottom-anchored groups.
    func testSlackSitsAboveTheChapterRow() throws {
        let chapterRow = app.staticTexts["Chapter 2"]
        XCTAssertTrue(chapterRow.waitForExistence(timeout: 20), "Expected the chapter row")

        let author = app.staticTexts["Marina Solano"]
        XCTAssertTrue(author.waitForExistence(timeout: 5), "Expected the author label")

        XCTAssertGreaterThan(
            chapterRow.frame.minY - author.frame.maxY,
            0,
            "Chapter row should sit below the author label"
        )
    }
}
