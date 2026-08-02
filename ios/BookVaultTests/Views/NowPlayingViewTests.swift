//
//  NowPlayingViewTests.swift
//  BookVaultTests
//
//  Tests for the Now Playing "time left in book" formatter.
//

import XCTest
@testable import BookVault

@MainActor
final class NowPlayingViewTests: XCTestCase {
    // MARK: - formatRemaining

    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(NowPlayingView.formatRemaining(8 * 3600 + 12 * 60), "8h 12m left")
    }

    func testOmitsHoursUnderOneHour() {
        XCTAssertEqual(NowPlayingView.formatRemaining(45 * 60), "45m left")
    }

    /// Rounds up, so a book still playing never reads "0m left".
    func testRoundsPartialMinutesUp() {
        XCTAssertEqual(NowPlayingView.formatRemaining(1), "1m left")
        XCTAssertEqual(NowPlayingView.formatRemaining(61), "2m left")
    }

    func testZeroRemainingReadsAsZero() {
        XCTAssertEqual(NowPlayingView.formatRemaining(0), "0m left")
    }

    /// 59m59s must not render as "0h 60m left".
    func testRollsUpToWholeHour() {
        XCTAssertEqual(NowPlayingView.formatRemaining(59 * 60 + 59), "1h 0m left")
    }

    func testLongBook() {
        XCTAssertEqual(NowPlayingView.formatRemaining(26 * 3600 + 5 * 60), "26h 5m left")
    }

    // MARK: - formatRemainingSpoken

    /// VoiceOver reads "h"/"m" as letters, so the spoken form spells the units
    /// out and says what is being counted down.
    func testSpokenFormSpellsOutUnits() {
        XCTAssertEqual(
            NowPlayingView.formatRemainingSpoken(8 * 3600 + 12 * 60),
            "8 hours 12 minutes left in the book"
        )
    }

    func testSpokenFormOmitsHoursUnderOneHour() {
        XCTAssertEqual(NowPlayingView.formatRemainingSpoken(45 * 60), "45 minutes left in the book")
    }

    func testSpokenFormSingularizes() {
        XCTAssertEqual(
            NowPlayingView.formatRemainingSpoken(3600 + 60),
            "1 hour 1 minute left in the book"
        )
    }

    /// Both forms round the same way, so they can never disagree.
    func testSpokenAndVisualFormsAgreeOnRounding() {
        let remaining: TimeInterval = 59 * 60 + 59
        XCTAssertEqual(NowPlayingView.formatRemaining(remaining), "1h 0m left")
        XCTAssertEqual(NowPlayingView.formatRemainingSpoken(remaining), "1 hour 0 minutes left in the book")
    }
}
