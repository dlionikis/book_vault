//
//  SleepTimerManagerRealTests.swift
//  BookVaultTests
//
//  Real-service tests for SleepTimerManager.
//
//  Every test here is synchronous and instant: `decide` and `arm` take the
//  clock as a parameter, so 90-minute behavior is exercised without real
//  timers or waiting.
//

import XCTest
@testable import BookVault

@MainActor
final class SleepTimerManagerRealTests: XCTestCase {
    // MARK: - Properties

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var settings: PlaybackSettings!
    private var timer: SleepTimerManager!

    /// Fixed reference clock. Never `Date()` — these tests must be deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        suiteName = "SleepTimerManagerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        settings = PlaybackSettings(userDefaults: testDefaults)
        timer = SleepTimerManager(settings: settings)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        settings = nil
        timer = nil
        suiteName = nil
    }

    // MARK: - Helpers

    private func makeChapter(
        startTime: Double = 0,
        endTime: Double = 600
    ) -> Chapter {
        Chapter(
            id: UUID(),
            title: "Chapter 1",
            startTime: startTime,
            endTime: endTime,
            duration: endTime - startTime,
            index: 1
        )
    }

    private func decide(
        at offset: TimeInterval,
        currentTime: TimeInterval = 0
    ) -> SleepTimerDecision {
        timer.decide(
            now: now.addingTimeInterval(offset),
            currentTime: currentTime
        )
    }

    // MARK: - Arming

    func testArmDuration_SetsFireDateAtNowPlusInterval() {
        timer.arm(.duration(15 * 60), now: now)

        guard case let .armed(mode, fireDate) = timer.state else {
            return XCTFail("Expected armed state, got \(timer.state)")
        }
        XCTAssertEqual(mode, .duration(15 * 60))
        XCTAssertEqual(fireDate, now.addingTimeInterval(15 * 60))
        XCTAssertTrue(timer.isArmed)
    }

    func testArmDuration_PersistsLastUsedDuration() {
        timer.arm(.duration(45 * 60), now: now)

        XCTAssertEqual(settings.lastSleepTimerDuration, 45 * 60)
    }

    func testArmEndOfChapter_HasNoFireDate() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        guard case let .armed(mode, fireDate) = timer.state else {
            return XCTFail("Expected armed state, got \(timer.state)")
        }
        XCTAssertEqual(mode, .endOfChapter(boundary: 600))
        XCTAssertNil(fireDate)
    }

    func testArmEndOfChapter_DoesNotPersistDuration() {
        // Given: a previously stored duration
        timer.arm(.duration(8 * 60), now: now)
        XCTAssertEqual(settings.lastSleepTimerDuration, 8 * 60)

        // When: arming end-of-chapter
        timer.arm(.endOfChapter(boundary: 600), now: now)

        // Then: the stored duration is untouched
        XCTAssertEqual(settings.lastSleepTimerDuration, 8 * 60)
    }

    func testArmEndOfChapter_CapturesBoundaryFromChapter() {
        let armed = timer.armEndOfChapter(chapter: makeChapter(endTime: 742))

        XCTAssertTrue(armed)
        XCTAssertEqual(timer.mode, .endOfChapter(boundary: 742))
    }

    func testArmEndOfChapter_WithNoChapter_DoesNotArm() {
        let armed = timer.armEndOfChapter(chapter: nil)

        XCTAssertFalse(armed)
        XCTAssertFalse(timer.isArmed)
    }

    func testArmWhileArmed_ReplacesDeadline() {
        timer.arm(.duration(60 * 60), now: now)
        timer.arm(.duration(8 * 60), now: now)

        guard case let .armed(_, fireDate) = timer.state else {
            return XCTFail("Expected armed state")
        }
        XCTAssertEqual(fireDate, now.addingTimeInterval(8 * 60))
    }

    // MARK: - Decide: duration

    func testDecideWhenOff_ReturnsNone() {
        XCTAssertEqual(decide(at: 0), .none)
    }

    func testDecideBeforeDeadline_ReturnsNone() {
        timer.arm(.duration(15 * 60), now: now)

        XCTAssertEqual(decide(at: 60), .none)
    }

    func testDecideInsideFadeWindow_ReturnsBeginFade() {
        timer.arm(.duration(15 * 60), now: now)

        // 5s before the deadline, still `.armed`
        XCTAssertEqual(decide(at: 15 * 60 - 5), .beginFade)
    }

    func testDecideWhenAlreadyFading_ReturnsContinueFadeWithProgress() {
        timer.arm(.duration(15 * 60), now: now)
        timer.beginFading()

        // 5s remaining of a 10s fade → halfway
        guard case let .continueFade(progress) = decide(at: 15 * 60 - 5) else {
            return XCTFail("Expected continueFade")
        }
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testDecideAtDeadline_ReturnsFire() {
        timer.arm(.duration(15 * 60), now: now)

        XCTAssertEqual(decide(at: 15 * 60), .fire)
    }

    /// The suspended-app case, and the acceptance test for the whole design:
    /// if the deadline passed while the app was not ticking, the very next
    /// check must fire rather than reading as "deep in the fade window".
    func testDecideDeadline40MinutesInPast_ReturnsFire() {
        timer.arm(.duration(8 * 60), now: now)

        XCTAssertEqual(decide(at: 48 * 60), .fire)
    }

    // MARK: - Decide: end of chapter

    func testDecideEndOfChapter_BeforeBoundary_ReturnsNone() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        XCTAssertEqual(decide(at: 0, currentTime: 100), .none)
    }

    func testDecideEndOfChapter_InsideFadeWindow_ReturnsBeginFade() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        // 5 playback-seconds from the boundary
        XCTAssertEqual(decide(at: 0, currentTime: 595), .beginFade)
    }

    func testDecideEndOfChapter_AtBoundary_ReturnsFire() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        XCTAssertEqual(decide(at: 0, currentTime: 600), .fire)
    }

    /// Regression: the boundary is captured at arm time rather than re-resolved
    /// from `getCurrentChapter()`, which returns nil once playback reaches
    /// `endTime`. Re-resolving made the timer fade to silence and never fire.
    func testDecideEndOfChapter_PastBoundary_StillFires() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        XCTAssertEqual(decide(at: 0, currentTime: 600.5), .fire)
        XCTAssertEqual(decide(at: 0, currentTime: 9999), .fire)
    }

    /// Wall clock must not affect end-of-chapter; only playback position does.
    func testDecideEndOfChapter_IgnoresWallClock() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        XCTAssertEqual(decide(at: 60 * 60, currentTime: 100), .none)
    }

    // MARK: - Extend

    func testExtend_PushesDeadline() {
        timer.arm(.duration(8 * 60), now: now)
        timer.extend(by: 15 * 60, now: now)

        guard case let .armed(_, fireDate) = timer.state else {
            return XCTFail("Expected armed state")
        }
        // Extends from the existing deadline, not from now.
        XCTAssertEqual(fireDate, now.addingTimeInterval(8 * 60 + 15 * 60))
    }

    func testExtendWhileFading_ReturnsToArmed() {
        timer.arm(.duration(8 * 60), now: now)
        timer.beginFading()
        guard case .fading = timer.state else {
            return XCTFail("Expected fading state")
        }

        timer.extend(by: 15 * 60, now: now)

        guard case .armed = timer.state else {
            return XCTFail("Expected armed state after extend, got \(timer.state)")
        }
    }

    func testExtendEndOfChapter_ConvertsToDuration() {
        timer.arm(.endOfChapter(boundary: 600), now: now)
        timer.extend(by: 15 * 60, now: now)

        guard case let .armed(mode, fireDate) = timer.state else {
            return XCTFail("Expected armed state")
        }
        XCTAssertEqual(mode, .duration(15 * 60))
        XCTAssertEqual(fireDate, now.addingTimeInterval(15 * 60))
    }

    func testExtendWhenOff_DoesNothing() {
        timer.extend(by: 15 * 60, now: now)

        XCTAssertEqual(timer.state, .off)
    }

    // MARK: - Cancel

    func testCancel_ReturnsToOff() {
        timer.arm(.duration(15 * 60), now: now)
        timer.cancel()

        XCTAssertEqual(timer.state, .off)
        XCTAssertFalse(timer.isArmed)
        XCTAssertNil(timer.mode)
    }

    // MARK: - Countdown text

    func testCountdownText_FormatsMinutesSecondsZeroPadded() {
        timer.arm(.duration(12 * 60 + 45), now: now)

        let text = SleepTimerManager.countdownText(for: timer.state, now: now)
        XCTAssertEqual(text, "12:45")
    }

    func testCountdownText_FormatsHoursWhenOverAnHour() {
        timer.arm(.duration(90 * 60), now: now)

        let text = SleepTimerManager.countdownText(for: timer.state, now: now)
        XCTAssertEqual(text, "1:30:00")
    }

    func testCountdownText_ReturnsNilWhenOff() {
        XCTAssertNil(SleepTimerManager.countdownText(for: .off, now: now))
    }

    func testCountdownText_ReturnsChapterLabelForEndOfChapter() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        let text = SleepTimerManager.countdownText(
            for: timer.state, now: now, currentTime: 100
        )
        XCTAssertEqual(text, "Chapter")
    }

    func testCountdownText_ShowsCountdownNearChapterEnd() {
        timer.arm(.endOfChapter(boundary: 600), now: now)

        // Inside the final minute, show the actual remaining time.
        let text = SleepTimerManager.countdownText(
            for: timer.state, now: now, currentTime: 570
        )
        XCTAssertEqual(text, "0:30")
    }

    func testCountdownText_ClampsAtZeroNotNegative() {
        timer.arm(.duration(8 * 60), now: now)

        let text = SleepTimerManager.countdownText(
            for: timer.state,
            now: now.addingTimeInterval(40 * 60)
        )
        XCTAssertEqual(text, "0:00")
    }
}
