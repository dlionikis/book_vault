//
//  MockAudioPlayerManager.swift
//  BookVaultTests
//
//  Mock AudioPlayerManager for testing - simulates audio playback.
//  Phase 3: Playback Core Tests
//

import Combine
import Foundation
@testable import BookVault

/// Mock audio player manager for testing
@MainActor
class MockAudioPlayerManager: AudioPlayerManaging, ObservableObject {
    // MARK: - Published Properties

    @Published var currentBook: Book?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var chapters: [Chapter] = []
    @Published var currentChapterId: UUID?
    @Published var isPlayingOffline: Bool = false

    // MARK: - Computed Properties

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Playback State (for testing)

    var playbackState: PlaybackState {
        if isLoading { return .loading }
        if let error { return .error(error.localizedDescription) }
        if isPlaying { return .playing }
        if currentBook != nil { return .paused }
        return .idle
    }

    // MARK: - Call Tracking

    var playBookCalls: [Book] = []
    var resumeCalled: Int = 0
    var pauseCalled: Int = 0
    var togglePlayPauseCalled: Int = 0
    var stopCalled: Int = 0
    var seekCalls: [TimeInterval] = []
    var skipForwardCalls: [TimeInterval] = []
    var skipBackwardCalls: [TimeInterval] = []
    var setPlaybackRateCalls: [Float] = []
    var setVolumeCalls: [Float] = []
    var skipToChapterCalls: [Chapter] = []
    var updateChaptersCalls: [[Chapter]] = []
    var clearChaptersCalled: Int = 0

    // MARK: - Behavior Configuration

    var loadShouldFail: Bool = false
    var loadFailureError: Error = NSError(
        domain: "MockAudioPlayerManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to load audio"]
    )
    var autoUpdateCurrentChapter: Bool = true

    // MARK: - Protocol Implementation

    func play(book: Book) {
        playBookCalls.append(book)

        if loadShouldFail {
            error = loadFailureError
            isLoading = false
            return
        }

        isLoading = true

        // Simulate async loading
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

            self.currentBook = book
            self.duration = Double(book.runtimeMinutes ?? 0) * 60
            self.isLoading = false
            self.isPlaying = true
            self.currentTime = 0
            self.isPlayingOffline = false
        }
    }

    func resume() {
        resumeCalled += 1
        guard currentBook != nil else { return }
        isPlaying = true
    }

    func pause() {
        pauseCalled += 1
        isPlaying = false
    }

    func togglePlayPause() {
        togglePlayPauseCalled += 1
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func stop() {
        stopCalled += 1
        currentBook = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        chapters = []
        currentChapterId = nil
        isPlayingOffline = false
        error = nil
    }

    func seek(to time: TimeInterval) {
        seekCalls.append(time)
        // Clamp to valid range
        currentTime = max(0, min(time, duration))

        // Update current chapter if enabled
        if autoUpdateCurrentChapter {
            updateCurrentChapterBasedOnTime()
        }
    }

    func skipForward(seconds: TimeInterval = 30) {
        skipForwardCalls.append(seconds)
        let newTime = min(currentTime + seconds, duration)
        currentTime = newTime

        if autoUpdateCurrentChapter {
            updateCurrentChapterBasedOnTime()
        }
    }

    func skipBackward(seconds: TimeInterval = 30) {
        skipBackwardCalls.append(seconds)
        let newTime = max(currentTime - seconds, 0)
        currentTime = newTime

        if autoUpdateCurrentChapter {
            updateCurrentChapterBasedOnTime()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        setPlaybackRateCalls.append(rate)
        playbackRate = rate
    }

    func setVolume(_ volume: Float) {
        setVolumeCalls.append(volume)
        self.volume = volume
    }

    // MARK: - Chapter Navigation

    func getCurrentChapter() -> Chapter? {
        guard !chapters.isEmpty else { return nil }
        return chapters.first { chapter in
            currentTime >= chapter.startTime && currentTime < chapter.endTime
        }
    }

    func skipToChapter(_ chapter: Chapter) {
        skipToChapterCalls.append(chapter)
        currentTime = chapter.startTime
        currentChapterId = chapter.id
    }

    func updateChapters(_ chapters: [Chapter]) {
        updateChaptersCalls.append(chapters)
        self.chapters = chapters

        // Update current chapter based on current time
        if autoUpdateCurrentChapter {
            updateCurrentChapterBasedOnTime()
        }
    }

    func clearChapters() {
        clearChaptersCalled += 1
        chapters = []
        currentChapterId = nil
    }

    // MARK: - Helper Methods

    private func updateCurrentChapterBasedOnTime() {
        if let chapter = getCurrentChapter() {
            currentChapterId = chapter.id
        }
    }

    /// Simulate playing from a local file
    func simulateOfflinePlayback() {
        isPlayingOffline = true
    }

    /// Simulate time passing during playback
    func simulateTimeProgress(to time: TimeInterval) {
        currentTime = max(0, min(time, duration))
        if autoUpdateCurrentChapter {
            updateCurrentChapterBasedOnTime()
        }
    }

    /// Simulate loading completion
    func simulateLoadComplete(book: Book, duration: TimeInterval) {
        currentBook = book
        self.duration = duration
        isLoading = false
        isPlaying = true
    }

    /// Simulate an error during playback
    func simulateError(_ error: Error) {
        self.error = error
        isPlaying = false
    }

    // MARK: - Reset

    func reset() {
        currentBook = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playbackRate = 1.0
        volume = 1.0
        isLoading = false
        error = nil
        chapters = []
        currentChapterId = nil
        isPlayingOffline = false

        playBookCalls = []
        resumeCalled = 0
        pauseCalled = 0
        togglePlayPauseCalled = 0
        stopCalled = 0
        seekCalls = []
        skipForwardCalls = []
        skipBackwardCalls = []
        setPlaybackRateCalls = []
        setVolumeCalls = []
        skipToChapterCalls = []
        updateChaptersCalls = []
        clearChaptersCalled = 0

        loadShouldFail = false
        autoUpdateCurrentChapter = true
    }
}
