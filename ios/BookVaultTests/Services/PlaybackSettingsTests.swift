//
//  PlaybackSettingsTests.swift
//  BookVaultTests
//
//  Round-trip tests for the UserDefaults-backed playback preferences.
//

import XCTest
@testable import BookVault

@MainActor
final class PlaybackSettingsTests: XCTestCase {
    // MARK: - Properties

    private var suiteName: String!
    private var testDefaults: UserDefaults!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        suiteName = "PlaybackSettingsTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
    }

    // MARK: - Sleep Timer Duration

    func testLastSleepTimerDuration_DefaultsTo30Minutes() {
        let settings = PlaybackSettings(userDefaults: testDefaults)

        XCTAssertEqual(settings.lastSleepTimerDuration, 30 * 60)
    }

    func testLastSleepTimerDuration_RoundTripsThroughUserDefaults() {
        let settings = PlaybackSettings(userDefaults: testDefaults)
        settings.lastSleepTimerDuration = 45 * 60

        // A fresh instance reads back the written value.
        let reloaded = PlaybackSettings(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.lastSleepTimerDuration, 45 * 60)
    }

    func testLastSleepTimerDuration_SnapsNonPresetValueToDefault() {
        // A value the picker can't represent (e.g. left by an older build).
        testDefaults.set(37.0 * 60, forKey: PlaybackSettings.lastSleepTimerDurationKey)

        let settings = PlaybackSettings(userDefaults: testDefaults)
        XCTAssertEqual(settings.lastSleepTimerDuration, 30 * 60)
    }

    /// 0.0 is a valid `Double` but not a valid duration — the existence check
    /// must not let it through as a real preference.
    func testLastSleepTimerDuration_ZeroStoredValueFallsBackToDefault() {
        testDefaults.set(0.0, forKey: PlaybackSettings.lastSleepTimerDurationKey)

        let settings = PlaybackSettings(userDefaults: testDefaults)
        XCTAssertEqual(settings.lastSleepTimerDuration, 30 * 60)
    }

    func testLastSleepTimerDuration_AcceptsEveryPreset() {
        for preset in SleepTimerManager.presets {
            testDefaults.set(preset, forKey: PlaybackSettings.lastSleepTimerDurationKey)

            let settings = PlaybackSettings(userDefaults: testDefaults)
            XCTAssertEqual(
                settings.lastSleepTimerDuration,
                preset,
                "Preset \(preset)s should survive a round trip"
            )
        }
    }

    // MARK: - Playback Rate (regression guard)

    func testDefaultPlaybackRate_StillDefaultsToOne() {
        let settings = PlaybackSettings(userDefaults: testDefaults)

        XCTAssertEqual(settings.defaultPlaybackRate, 1.0)
    }

    func testDefaultPlaybackRate_StillRoundTrips() {
        let settings = PlaybackSettings(userDefaults: testDefaults)
        settings.defaultPlaybackRate = 1.5

        let reloaded = PlaybackSettings(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.defaultPlaybackRate, 1.5)
    }

    func testDefaultPlaybackRate_StillClampsOutOfRange() {
        testDefaults.set(9.0, forKey: "defaultPlaybackRate")

        let settings = PlaybackSettings(userDefaults: testDefaults)
        XCTAssertEqual(settings.defaultPlaybackRate, 3.0)
    }
}
