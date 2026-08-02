//
//  PlaybackSettings.swift
//  BookVault
//
//  Created by Claude Code on 1/3/26.
//

import Foundation

/// Manages playback preference settings with UserDefaults persistence
@MainActor
class PlaybackSettings: ObservableObject {
    static let shared = PlaybackSettings()

    // MARK: - Constants

    private static let defaultPlaybackRateKey = "defaultPlaybackRate"
    static let lastSleepTimerDurationKey = "lastSleepTimerDuration"

    /// Fallback when nothing has been chosen yet (30 minutes).
    static let defaultSleepTimerDuration: TimeInterval = 30 * 60

    // MARK: - Properties

    private let userDefaults: UserDefaults

    /// Default playback speed for new audiobooks (0.5 to 3.0)
    @Published var defaultPlaybackRate: Float {
        didSet {
            userDefaults.set(defaultPlaybackRate, forKey: PlaybackSettings.defaultPlaybackRateKey)
        }
    }

    /// Last sleep-timer duration the user picked, pre-selected in the picker.
    @Published var lastSleepTimerDuration: TimeInterval {
        didSet {
            userDefaults.set(lastSleepTimerDuration, forKey: PlaybackSettings.lastSleepTimerDurationKey)
        }
    }

    // MARK: - Initialization

    /// Production singleton initializer using standard UserDefaults
    private convenience init() {
        self.init(userDefaults: .standard)
    }

    /// Testable initializer that accepts a UserDefaults instance
    /// - Parameter userDefaults: The UserDefaults store to use for persistence
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults

        // Load saved rate or default to 1.0
        // Check if key exists (0.0 is a valid float but not a valid playback rate)
        if userDefaults.object(forKey: PlaybackSettings.defaultPlaybackRateKey) != nil {
            let savedRate = userDefaults.float(forKey: PlaybackSettings.defaultPlaybackRateKey)
            // Clamp to valid range
            self.defaultPlaybackRate = min(max(savedRate, 0.5), 3.0)
        } else {
            self.defaultPlaybackRate = 1.0
        }

        // Same existence check: 0.0 is a valid Double but not a valid duration.
        if userDefaults.object(forKey: PlaybackSettings.lastSleepTimerDurationKey) != nil {
            let saved = userDefaults.double(forKey: PlaybackSettings.lastSleepTimerDurationKey)
            // Snap to a known preset — a value outside the set can't be
            // represented in the picker.
            self.lastSleepTimerDuration = SleepTimerManager.presets.contains(saved)
                ? saved
                : PlaybackSettings.defaultSleepTimerDuration
        } else {
            self.lastSleepTimerDuration = PlaybackSettings.defaultSleepTimerDuration
        }
    }
}
