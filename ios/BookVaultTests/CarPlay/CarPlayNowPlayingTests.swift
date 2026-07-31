//
//  CarPlayNowPlayingTests.swift
//  BookVaultTests
//
//  CarPlay task B7 — chapter stepping and button visibility.
//

import XCTest
@testable import BookVault

@MainActor
final class CarPlayNowPlayingTests: XCTestCase {
    /// Three 60s chapters: 0–60, 60–120, 120–180.
    private func makeChapters() -> [Chapter] {
        (0 ..< 3).map { index in
            Chapter(
                id: UUID(),
                title: "Chapter \(index + 1)",
                startTime: Double(index) * 60,
                endTime: Double(index + 1) * 60,
                duration: 60,
                index: index
            )
        }
    }

    // MARK: - Next

    func testNextMovesForwardOneChapter() {
        let chapters = makeChapters()

        let target = CarPlayNowPlaying.chapter(for: .next, chapters: chapters, currentTime: 30)

        XCTAssertEqual(target?.title, "Chapter 2")
    }

    /// The last chapter has nowhere forward to go; the button must no-op rather
    /// than seek to the end or crash.
    func testNextOnLastChapterReturnsNil() {
        let chapters = makeChapters()

        let target = CarPlayNowPlaying.chapter(for: .next, chapters: chapters, currentTime: 150)

        XCTAssertNil(target)
    }

    // MARK: - Previous

    /// The convention every audio player uses: pressing back mid-chapter
    /// restarts it rather than jumping to the previous one.
    func testPreviousRestartsCurrentChapterWhenPastTheThreshold() {
        let chapters = makeChapters()

        let target = CarPlayNowPlaying.chapter(for: .previous, chapters: chapters, currentTime: 90)

        XCTAssertEqual(target?.title, "Chapter 2", "Should restart chapter 2, not jump to chapter 1")
        XCTAssertEqual(target?.startTime, 60)
    }

    /// Near the start of a chapter, back means back.
    func testPreviousNearChapterStartGoesToPreviousChapter() {
        let chapters = makeChapters()

        let target = CarPlayNowPlaying.chapter(for: .previous, chapters: chapters, currentTime: 61)

        XCTAssertEqual(target?.title, "Chapter 1")
    }

    /// The boundary itself: exactly at the threshold still counts as "near the
    /// start", so a double-press reliably walks backwards.
    func testPreviousAtExactlyTheThresholdGoesBack() {
        let chapters = makeChapters()
        let atThreshold = 60 + CarPlayNowPlaying.restartThreshold

        let target = CarPlayNowPlaying.chapter(for: .previous, chapters: chapters, currentTime: atThreshold)

        XCTAssertEqual(target?.title, "Chapter 1")
    }

    /// In the first chapter there is nothing before it, so back restarts.
    func testPreviousInFirstChapterRestartsIt() {
        let chapters = makeChapters()

        let target = CarPlayNowPlaying.chapter(for: .previous, chapters: chapters, currentTime: 1)

        XCTAssertEqual(target?.title, "Chapter 1")
    }

    // MARK: - Degenerate input

    func testNoChaptersReturnsNilForBothDirections() {
        XCTAssertNil(CarPlayNowPlaying.chapter(for: .next, chapters: [], currentTime: 0))
        XCTAssertNil(CarPlayNowPlaying.chapter(for: .previous, chapters: [], currentTime: 0))
    }

    /// Chapters can arrive out of order; stepping must not depend on the array's
    /// ordering.
    func testSteppingIsIndependentOfArrayOrder() {
        let shuffled = makeChapters().reversed().map { $0 }

        let target = CarPlayNowPlaying.chapter(for: .next, chapters: shuffled, currentTime: 30)

        XCTAssertEqual(target?.title, "Chapter 2")
    }

    // MARK: - Button visibility (Q4 graceful degradation)

    func testChapterButtonsHiddenWithoutChapters() {
        XCTAssertFalse(CarPlayNowPlaying.shouldShowChapterButtons(chapters: []))
    }

    /// A single chapter is the whole book — navigation would be a no-op.
    func testChapterButtonsHiddenForASingleChapter() {
        let one = Array(makeChapters().prefix(1))

        XCTAssertFalse(CarPlayNowPlaying.shouldShowChapterButtons(chapters: one))
    }

    func testChapterButtonsShownForMultipleChapters() {
        XCTAssertTrue(CarPlayNowPlaying.shouldShowChapterButtons(chapters: makeChapters()))
    }

    // MARK: - Playback rate

    func testPlaybackRateCyclesAndWrapsAround() {
        XCTAssertEqual(CarPlayNowPlaying.nextPlaybackRate(after: 1.0), 1.25)
        XCTAssertEqual(CarPlayNowPlaying.nextPlaybackRate(after: 1.75), 2.0)
        XCTAssertEqual(CarPlayNowPlaying.nextPlaybackRate(after: 2.0), 1.0, "Should wrap to the start")
    }

    /// A rate set elsewhere (the phone UI allows others) must not strand the
    /// button — it falls back to a known value rather than doing nothing.
    func testUnknownPlaybackRateFallsBackToNormal() {
        XCTAssertEqual(CarPlayNowPlaying.nextPlaybackRate(after: 1.6), 1.0)
    }
}
