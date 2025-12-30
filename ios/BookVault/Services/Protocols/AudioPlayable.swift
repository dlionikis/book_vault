//
//  AudioPlayable.swift
//  BookVault
//
//  Created for Phase 4 testing support.
//  Enables testing AudioPlayerManager without real AVPlayer.
//

import AVFoundation
import Combine
import Foundation

// MARK: - AudioPlayable

/// Protocol for audio player operations to enable testing
/// Wraps AVPlayer functionality for dependency injection
protocol AudioPlayable: AnyObject {
    // MARK: - Player State

    /// Current playback time in seconds
    var currentTimeSeconds: TimeInterval { get }

    /// Duration of current item in seconds
    var durationSeconds: TimeInterval { get }

    /// Whether the player is currently playing
    var isCurrentlyPlaying: Bool { get }

    /// Current playback rate
    var currentRate: Float { get set }

    /// Player volume (0.0 to 1.0)
    var playerVolume: Float { get set }

    /// Current player item status
    var itemStatus: AVPlayerItem.Status { get }

    // MARK: - Playback Control

    /// Start or resume playback
    func play()

    /// Pause playback
    func pause()

    /// Seek to a specific time
    /// - Parameters:
    ///   - time: Time to seek to in seconds
    ///   - completion: Called when seek completes
    func seek(to time: TimeInterval, completion: @escaping (Bool) -> Void)

    // MARK: - Item Management

    /// Replace the current player item
    /// - Parameter item: New player item, or nil to clear
    func replaceCurrentItem(with item: AVPlayerItem?)

    /// Add a periodic time observer
    /// - Parameters:
    ///   - interval: Interval for observer callbacks
    ///   - queue: Queue to call observer on
    ///   - block: Callback block with current time
    /// - Returns: Observer token to remove later
    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping (CMTime) -> Void
    ) -> Any

    /// Remove a time observer
    /// - Parameter observer: Observer token from addPeriodicTimeObserver
    func removeTimeObserver(_ observer: Any)
}

// MARK: - AVPlayerWrapper

/// Wrapper around AVPlayer that conforms to AudioPlayable
/// Provides real AVPlayer functionality for production
final class AVPlayerWrapper: AudioPlayable {
    private let player: AVPlayer

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
    }

    var currentTimeSeconds: TimeInterval {
        player.currentTime().seconds
    }

    var durationSeconds: TimeInterval {
        player.currentItem?.duration.seconds ?? 0
    }

    var isCurrentlyPlaying: Bool {
        player.timeControlStatus == .playing
    }

    var currentRate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    var playerVolume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var itemStatus: AVPlayerItem.Status {
        player.currentItem?.status ?? .unknown
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval, completion: @escaping (Bool) -> Void) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player.seek(to: cmTime) { completed in
            completion(completed)
        }
    }

    func replaceCurrentItem(with item: AVPlayerItem?) {
        player.replaceCurrentItem(with: item)
    }

    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping (CMTime) -> Void
    ) -> Any {
        player.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: block)
    }

    func removeTimeObserver(_ observer: Any) {
        player.removeTimeObserver(observer)
    }
}
