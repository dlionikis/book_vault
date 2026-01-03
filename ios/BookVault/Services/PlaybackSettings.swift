//
//  PlaybackSettings.swift
//  BookVault
//
//  Created by Claude Code on 1/3/26.
//

import Foundation

/// Manages playback preference settings with UserDefaults persistence
class PlaybackSettings: ObservableObject {
    static let shared = PlaybackSettings()

    // MARK: - Constants

    private static let defaultPlaybackRateKey = "defaultPlaybackRate"

    // MARK: - Properties

    private let userDefaults: UserDefaults

    /// Default playback speed for new audiobooks (0.5 to 3.0)
    @Published var defaultPlaybackRate: Float {
        didSet {
            userDefaults.set(defaultPlaybackRate, forKey: PlaybackSettings.defaultPlaybackRateKey)
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
    }
}
