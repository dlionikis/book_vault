//
//  AudioPlayerManaging.swift
//  BookVault
//
//  Protocol for AudioPlayerManager to enable testing with mocks.
//  Phase 3: Playback Core Tests
//

import Combine
import Foundation

// MARK: - PlaybackState

/// Playback state enumeration for testing
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case error(String)

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): true
        case (.loading, .loading): true
        case (.playing, .playing): true
        case (.paused, .paused): true
        case let (.error(msg1), .error(msg2)): msg1 == msg2
        default: false
        }
    }
}

// MARK: - AudioPlayerManaging

/// Protocol for AudioPlayerManager to enable testing
@MainActor
protocol AudioPlayerManaging: ObservableObject {
    // MARK: - State Properties

    /// The currently loaded book
    var currentBook: Book? { get }

    /// Whether audio is currently playing
    var isPlaying: Bool { get }

    /// Current playback position in seconds
    var currentTime: TimeInterval { get }

    /// Total duration of the audio in seconds
    var duration: TimeInterval { get }

    /// Current playback rate (1.0 = normal speed)
    var playbackRate: Float { get }

    /// Whether the audio is currently loading
    var isLoading: Bool { get }

    /// Any error that occurred during playback
    var error: Error? { get }

    /// Available chapters for the current book
    var chapters: [Chapter] { get }

    /// ID of the currently playing chapter
    var currentChapterId: UUID? { get }

    /// Whether playing from local file (offline) vs streaming
    var isPlayingOffline: Bool { get }

    // MARK: - Computed Properties

    /// Progress as a percentage (0.0 to 1.0)
    var progress: Double { get }

    // MARK: - Playback Control

    /// Load and play a book
    /// - Parameter book: The book to play
    func play(book: Book)

    /// Resume playback of the current book
    func resume()

    /// Pause playback
    func pause()

    /// Toggle between play and pause
    func togglePlayPause()

    /// Stop playback and cleanup
    func stop()

    /// Seek to a specific time
    /// - Parameter time: The time to seek to in seconds
    func seek(to time: TimeInterval)

    /// Skip forward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip forward (default 30)
    func skipForward(seconds: TimeInterval)

    /// Skip backward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip backward (default 30)
    func skipBackward(seconds: TimeInterval)

    /// Set the playback speed
    /// - Parameter rate: The playback rate (0.5 to 2.0)
    func setPlaybackRate(_ rate: Float)

    /// Set the volume
    /// - Parameter volume: Volume level (0.0 to 1.0)
    func setVolume(_ volume: Float)

    // MARK: - Chapter Navigation

    /// Get the current chapter based on playback position
    /// - Returns: The current chapter, or nil if no chapters
    func getCurrentChapter() -> Chapter?

    /// Skip to a specific chapter
    /// - Parameter chapter: The chapter to skip to
    func skipToChapter(_ chapter: Chapter)

    /// Update chapters for the current book
    /// - Parameter chapters: Array of chapters
    func updateChapters(_ chapters: [Chapter])

    /// Clear chapters (called when stopping playback)
    func clearChapters()
}
