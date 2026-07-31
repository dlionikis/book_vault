//
//  AudioPlayerManagerTests.swift
//  BookVaultTests
//
//  Tests for AudioPlayerManager - Phase 3: Playback Core Tests
//

import XCTest
@testable import BookVault

@MainActor
final class AudioPlayerManagerTests: XCTestCase {
    var sut: MockAudioPlayerManager!

    override func setUp() async throws {
        sut = MockAudioPlayerManager()
    }

    override func tearDown() async throws {
        sut.reset()
        sut = nil
    }

    // MARK: - Initial State Tests

    func testInitialStateIsIdle() {
        // Given a fresh AudioPlayerManager
        // Then state should be idle
        XCTAssertEqual(sut.playbackState, .idle)
        XCTAssertNil(sut.currentBook)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.currentTime, 0)
        XCTAssertEqual(sut.duration, 0)
        XCTAssertEqual(sut.playbackRate, 1.0)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertNil(sut.currentChapterId)
    }

    // MARK: - State Machine Tests

    func testPlayBookTransitionsToLoading() async throws {
        // Given idle state
        let book = TestFixtures.makeBook()

        // When play is called
        sut.play(book: book)

        // Then state should transition to loading immediately
        XCTAssertTrue(sut.isLoading)
        XCTAssertEqual(sut.playbackState, .loading)
    }

    func testSuccessfulLoadTransitionsToPlaying() async throws {
        // Given a book to play
        let book = TestFixtures.makeBook(runtimeMinutes: 120)

        // When play is called and loading completes
        sut.play(book: book)

        // Wait for async loading to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Then state should be playing
        XCTAssertEqual(sut.playbackState, .playing)
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(sut.currentBook?.id, book.id)
        XCTAssertEqual(sut.duration, 7200) // 120 minutes * 60 seconds
    }

    func testFailedLoadTransitionsToError() async throws {
        // Given load will fail
        sut.loadShouldFail = true
        let book = TestFixtures.makeBook()

        // When play is called
        sut.play(book: book)

        // Wait for async handling
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Then state should be error
        XCTAssertNotNil(sut.error)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertFalse(sut.isLoading)
    }

    func testPauseTransitionsFromPlayingToPaused() async throws {
        // Given playing state
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        XCTAssertTrue(sut.isPlaying)

        // When pause is called
        sut.pause()

        // Then state should be paused
        XCTAssertEqual(sut.playbackState, .paused)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertNotNil(sut.currentBook)
        XCTAssertEqual(sut.pauseCalled, 1)
    }

    func testResumeTransitionsFromPausedToPlaying() {
        // Given paused state
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.pause()
        XCTAssertFalse(sut.isPlaying)

        // When resume is called
        sut.resume()

        // Then state should be playing
        XCTAssertEqual(sut.playbackState, .playing)
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(sut.resumeCalled, 1)
    }

    func testTogglePlayPauseFromPlaying() {
        // Given playing state
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        XCTAssertTrue(sut.isPlaying)

        // When togglePlayPause is called
        sut.togglePlayPause()

        // Then should be paused
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.togglePlayPauseCalled, 1)
    }

    func testTogglePlayPauseFromPaused() {
        // Given paused state
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.pause()
        XCTAssertFalse(sut.isPlaying)

        // When togglePlayPause is called
        sut.togglePlayPause()

        // Then should be playing
        XCTAssertTrue(sut.isPlaying)
    }

    func testStopTransitionsToIdle() {
        // Given playing state
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.currentTime = 100

        // When stop is called
        sut.stop()

        // Then state should be idle
        XCTAssertEqual(sut.playbackState, .idle)
        XCTAssertNil(sut.currentBook)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.currentTime, 0)
        XCTAssertEqual(sut.duration, 0)
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertNil(sut.currentChapterId)
        XCTAssertEqual(sut.stopCalled, 1)
    }

    // MARK: - Seek Tests

    func testSeekUpdatesCurrentTime() {
        // Given playing book
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)

        // When seek is called
        sut.seek(to: 1200)

        // Then currentTime should update
        XCTAssertEqual(sut.currentTime, 1200)
        XCTAssertEqual(sut.seekCalls.count, 1)
        XCTAssertEqual(sut.seekCalls.first, 1200)
    }

    func testSeekClampsToDuration() {
        // Given book with duration
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)

        // When seek is called beyond duration
        sut.seek(to: 5000)

        // Then currentTime should be clamped to duration
        XCTAssertEqual(sut.currentTime, 3600)
    }

    func testSeekClampsToZero() {
        // Given book
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.currentTime = 100

        // When seek is called with negative value
        sut.seek(to: -100)

        // Then currentTime should be clamped to 0
        XCTAssertEqual(sut.currentTime, 0)
    }

    // MARK: - Skip Tests

    func testSkipForward30Seconds() {
        // Given current time at 60s
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.currentTime = 60

        // When skipForward(30) is called
        sut.skipForward(seconds: 30)

        // Then currentTime should be 90s
        XCTAssertEqual(sut.currentTime, 90)
        XCTAssertEqual(sut.skipForwardCalls.count, 1)
        XCTAssertEqual(sut.skipForwardCalls.first, 30)
    }

    func testSkipForwardDoesNotExceedDuration() {
        // Given current time near end
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 100)
        sut.currentTime = 90

        // When skipForward(30) is called
        sut.skipForward(seconds: 30)

        // Then currentTime should be clamped to duration
        XCTAssertEqual(sut.currentTime, 100)
    }

    func testSkipBackward15Seconds() {
        // Given current time at 60s
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.currentTime = 60

        // When skipBackward(15) is called
        sut.skipBackward(seconds: 15)

        // Then currentTime should be 45s
        XCTAssertEqual(sut.currentTime, 45)
        XCTAssertEqual(sut.skipBackwardCalls.count, 1)
        XCTAssertEqual(sut.skipBackwardCalls.first, 15)
    }

    func testSkipBackwardDoesNotGoBelowZero() {
        // Given current time at 5s
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        sut.currentTime = 5

        // When skipBackward(15) is called
        sut.skipBackward(seconds: 15)

        // Then currentTime should be 0
        XCTAssertEqual(sut.currentTime, 0)
    }

    // MARK: - Playback Rate Tests

    func testSetPlaybackRateUpdatesRate() {
        // Given default rate (1.0)
        XCTAssertEqual(sut.playbackRate, 1.0)

        // When setPlaybackRate(1.5) is called
        sut.setPlaybackRate(1.5)

        // Then playbackRate should be 1.5
        XCTAssertEqual(sut.playbackRate, 1.5)
        XCTAssertEqual(sut.setPlaybackRateCalls.count, 1)
        XCTAssertEqual(sut.setPlaybackRateCalls.first, 1.5)
    }

    func testSetPlaybackRateToHalfSpeed() {
        // When setPlaybackRate(0.5) is called
        sut.setPlaybackRate(0.5)

        // Then playbackRate should be 0.5
        XCTAssertEqual(sut.playbackRate, 0.5)
    }

    func testSetPlaybackRateToDoubleSpeed() {
        // When setPlaybackRate(2.0) is called
        sut.setPlaybackRate(2.0)

        // Then playbackRate should be 2.0
        XCTAssertEqual(sut.playbackRate, 2.0)
    }

    // MARK: - Volume Tests

    func testSetVolumeUpdatesVolume() {
        // Given default volume
        XCTAssertEqual(sut.volume, 1.0)

        // When setVolume is called
        sut.setVolume(0.5)

        // Then volume should update
        XCTAssertEqual(sut.volume, 0.5)
        XCTAssertEqual(sut.setVolumeCalls.count, 1)
    }

    // MARK: - Progress Calculation Tests

    func testProgressCalculation() {
        // Given book at 50% progress
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 1000)
        sut.currentTime = 500

        // Then progress should be 0.5
        XCTAssertEqual(sut.progress, 0.5, accuracy: 0.001)
    }

    func testProgressIsZeroWhenDurationIsZero() {
        // Given no duration
        XCTAssertEqual(sut.duration, 0)

        // Then progress should be 0
        XCTAssertEqual(sut.progress, 0)
    }

    // MARK: - Chapter Navigation Tests

    func testGetCurrentChapterReturnsCorrectChapter() {
        // Given chapters and current time within chapter 2
        let chapters = TestFixtures.makeChapterList(count: 5)
        sut.updateChapters(chapters)
        sut.currentTime = 750 // Middle of chapter 2 (600-1200)

        // When getCurrentChapter is called
        let currentChapter = sut.getCurrentChapter()

        // Then should return chapter 2
        XCTAssertNotNil(currentChapter)
        XCTAssertEqual(currentChapter?.title, "Chapter 2")
        XCTAssertEqual(currentChapter?.index, 1)
    }

    func testGetCurrentChapterReturnsNilWhenNoChapters() {
        // Given no chapters
        XCTAssertTrue(sut.chapters.isEmpty)

        // When getCurrentChapter is called
        let currentChapter = sut.getCurrentChapter()

        // Then should return nil
        XCTAssertNil(currentChapter)
    }

    func testSkipToChapterSeeksToChapterStart() {
        // Given chapters
        let chapters = TestFixtures.makeChapterList(count: 5)
        sut.updateChapters(chapters)

        let targetChapter = chapters[2] // Chapter 3

        // When skipToChapter is called
        sut.skipToChapter(targetChapter)

        // Then currentTime should be chapter start time
        XCTAssertEqual(sut.currentTime, targetChapter.startTime)
        XCTAssertEqual(sut.currentChapterId, targetChapter.id)
        XCTAssertEqual(sut.skipToChapterCalls.count, 1)
    }

    func testUpdateChaptersStoresChapters() {
        // Given chapters
        let chapters = TestFixtures.makeChapterList(count: 3)

        // When updateChapters is called
        sut.updateChapters(chapters)

        // Then chapters should be stored
        XCTAssertEqual(sut.chapters.count, 3)
        XCTAssertEqual(sut.updateChaptersCalls.count, 1)
    }

    func testClearChaptersRemovesAllChapters() {
        // Given chapters
        let chapters = TestFixtures.makeChapterList(count: 3)
        sut.updateChapters(chapters)
        sut.currentChapterId = chapters[0].id

        // When clearChapters is called
        sut.clearChapters()

        // Then chapters should be empty
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertNil(sut.currentChapterId)
        XCTAssertEqual(sut.clearChaptersCalled, 1)
    }

    func testCurrentChapterUpdatesOnSeek() {
        // Given chapters and auto-update enabled with proper duration
        sut.autoUpdateCurrentChapter = true
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3000) // 5 chapters × 600s each
        let chapters = TestFixtures.makeChapterList(count: 5)
        sut.updateChapters(chapters)

        // When seeking to middle of chapter 3
        sut.seek(to: 1500) // Chapter 3 is 1200-1800

        // Then currentChapterId should be chapter 3
        XCTAssertNotNil(sut.currentChapterId)
        let currentChapter = sut.getCurrentChapter()
        XCTAssertNotNil(currentChapter)
        XCTAssertEqual(currentChapter?.index, 2)
        XCTAssertEqual(currentChapter?.title, "Chapter 3")
        XCTAssertEqual(sut.currentChapterId, currentChapter?.id)
    }

    // MARK: - Offline Playback Tests

    func testIsPlayingOfflineInitiallyFalse() {
        // Given fresh state
        // Then isPlayingOffline should be false
        XCTAssertFalse(sut.isPlayingOffline)
    }

    func testSimulateOfflinePlaybackSetsFlag() {
        // When simulateOfflinePlayback is called
        sut.simulateOfflinePlayback()

        // Then isPlayingOffline should be true
        XCTAssertTrue(sut.isPlayingOffline)
    }

    // MARK: - Playing Same Book Tests

    func testPlayingSameBookIsTracked() async throws {
        // Given a book already loaded
        let book = TestFixtures.makeBook()
        sut.play(book: book)
        try await Task.sleep(nanoseconds: 50_000_000)

        // When play is called again with same book
        sut.play(book: book)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then both calls should be tracked
        XCTAssertEqual(sut.playBookCalls.count, 2)
    }

    // MARK: - Time Progress Simulation Tests

    func testSimulateTimeProgressUpdatesCurrentTime() {
        // Given playing book
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)

        // When simulating time progress
        sut.simulateTimeProgress(to: 500)

        // Then currentTime should update
        XCTAssertEqual(sut.currentTime, 500)
    }

    func testSimulateTimeProgressClampsToValidRange() {
        // Given playing book
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 1000)

        // When simulating time beyond duration
        sut.simulateTimeProgress(to: 2000)

        // Then currentTime should be clamped
        XCTAssertEqual(sut.currentTime, 1000)
    }

    // MARK: - Error Simulation Tests

    func testSimulateErrorSetsErrorAndStopsPlayback() {
        // Given playing book
        let book = TestFixtures.makeBook()
        sut.simulateLoadComplete(book: book, duration: 3600)
        XCTAssertTrue(sut.isPlaying)

        // When error is simulated
        let error = NSError(domain: "Test", code: 500, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        sut.simulateError(error)

        // Then error should be set and playback stopped
        XCTAssertNotNil(sut.error)
        XCTAssertFalse(sut.isPlaying)
    }
}
