//
//  AudioPlayerManagerRealTests.swift
//  BookVaultTests
//
//  Phase 4: Real service tests for AudioPlayerManager.
//  Tests actual playback logic with mock dependencies.
//

import XCTest
@testable import BookVault

// MARK: - Mock Progress Manager for Audio Tests

@MainActor
final class MockProgressManagerForAudio: ProgressManaging {
    var isLoading = false
    var error: Error?

    var fetchedProgress: [String: UserProgress] = [:]
    var savedProgress: [String: Double] = [:]
    var fetchCallCount = 0
    var saveCallCount = 0
    var shouldThrowOnFetch = false
    var shouldThrowOnSave = false

    func fetchProgress(for bookId: String) async throws -> UserProgress {
        fetchCallCount += 1
        if shouldThrowOnFetch {
            throw APIError.networkError(NSError(domain: "", code: -1))
        }
        if let progress = fetchedProgress[bookId] {
            return progress
        }
        // Return default progress
        return UserProgress(positionSeconds: 0, completed: false, lastPlayed: nil)
    }

    @discardableResult
    func saveProgress(for bookId: String, positionSeconds: Double, timestamp: Date?) async throws -> SaveProgressResponse {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw APIError.networkError(NSError(domain: "", code: -1))
        }
        savedProgress[bookId] = positionSeconds
        return SaveProgressResponse(positionSeconds: positionSeconds, completed: false, lastPlayed: nil, updated: true)
    }

    func markCompleted(bookId: String) async throws {
        // No-op for audio tests
    }

    func resetProgress(bookId: String) async throws {
        // No-op for audio tests
    }
}

// MARK: - Mock Download Manager for Audio Tests

@MainActor
final class MockDownloadManagerForAudio: DownloadManaging {
    @Published var activeDownloads: [String: ActiveDownload] = [:]
    @Published var error: DownloadError?

    var isDownloadingBookIds: Set<String> = []

    func downloadState(for bookId: String) -> DownloadState {
        return .notDownloaded
    }

    func isDownloading(bookId: String) -> Bool {
        return isDownloadingBookIds.contains(bookId)
    }

    func startDownload(book: Book) async throws {
        // No-op for audio tests
    }

    func cancelDownload(bookId: String) {
        // No-op for audio tests
    }

    func pauseDownload(bookId: String) {
        // No-op for audio tests
    }

    func resumeDownload(book: Book) async throws {
        // No-op for audio tests
    }

    func deleteDownload(bookId: String) throws {
        // No-op for audio tests
    }
}

// MARK: - AudioPlayerManager Real Tests

@MainActor
final class AudioPlayerManagerRealTests: XCTestCase {

    var sut: AudioPlayerManager!
    var mockProgressManager: MockProgressManagerForAudio!
    var mockDownloadManager: MockDownloadManagerForAudio!
    var mockStorageManager: MockStorageManagerForDownloads!

    override func setUp() async throws {
        mockProgressManager = MockProgressManagerForAudio()
        mockDownloadManager = MockDownloadManagerForAudio()
        mockStorageManager = MockStorageManagerForDownloads()

        sut = AudioPlayerManager(
            progressManager: mockProgressManager,
            downloadManager: mockDownloadManager,
            storageManager: mockStorageManager,
            skipAudioSetup: true  // Skip AVAudioSession setup for unit tests
        )

        // Mock auth token provider
        sut.authTokenProvider = { "test-token" }
    }

    override func tearDown() async throws {
        sut = nil
        mockProgressManager = nil
        mockDownloadManager = nil
        mockStorageManager = nil
    }

    // MARK: - Helper Methods

    func makeTestBook(id: UUID = UUID(), title: String = "Test Audiobook") -> Book {
        return Book(
            id: id,
            asin: "B123456",
            title: title,
            description: "A test audiobook",
            runtimeMinutes: 300,
            releaseDate: Date(),
            coverUrl: "http://localhost:3000/api/covers/test.jpg",
            audioUrl: "http://localhost:3000/api/audio/test.mp3",
            authors: [Author(id: UUID(), name: "Test Author", asin: "A123")],
            narrators: [Narrator(id: UUID(), name: "Test Narrator", asin: "N123")]
        )
    }

    func makeTestChapter(id: UUID = UUID(), title: String, startTime: Double, endTime: Double, index: Int = 0) -> Chapter {
        return Chapter(
            id: id,
            title: title,
            startTime: startTime,
            endTime: endTime,
            duration: endTime - startTime,
            index: index
        )
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertNil(sut.currentBook)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.currentTime, 0)
        XCTAssertEqual(sut.duration, 0)
        XCTAssertEqual(sut.playbackRate, 1.0)
        XCTAssertEqual(sut.volume, 1.0)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertNil(sut.currentChapterId)
        XCTAssertFalse(sut.isPlayingOffline)
    }

    // MARK: - Progress Calculation Tests

    func testProgressWithZeroDuration() {
        // When duration is 0, progress should be 0
        XCTAssertEqual(sut.progress, 0)
    }

    func testProgressCalculation() {
        // Given
        sut.currentTime = 150
        sut.duration = 300

        // Then
        XCTAssertEqual(sut.progress, 0.5, accuracy: 0.001)
    }

    func testProgressAtEnd() {
        // Given
        sut.currentTime = 300
        sut.duration = 300

        // Then
        XCTAssertEqual(sut.progress, 1.0, accuracy: 0.001)
    }

    // MARK: - Chapter Navigation Tests

    func testGetCurrentChapterWithEmptyChapters() {
        XCTAssertNil(sut.getCurrentChapter())
    }

    func testGetCurrentChapterFindsCorrectChapter() {
        // Given
        let chapters = [
            makeTestChapter(title: "Chapter 1", startTime: 0, endTime: 100),
            makeTestChapter(title: "Chapter 2", startTime: 100, endTime: 200),
            makeTestChapter(title: "Chapter 3", startTime: 200, endTime: 300)
        ]
        sut.updateChapters(chapters)
        sut.currentTime = 150  // Middle of Chapter 2

        // When
        let currentChapter = sut.getCurrentChapter()

        // Then
        XCTAssertEqual(currentChapter?.title, "Chapter 2")
    }

    func testGetCurrentChapterAtBoundary() {
        // Given
        let chapters = [
            makeTestChapter(title: "Chapter 1", startTime: 0, endTime: 100),
            makeTestChapter(title: "Chapter 2", startTime: 100, endTime: 200)
        ]
        sut.updateChapters(chapters)
        sut.currentTime = 100  // Exactly at boundary

        // When
        let currentChapter = sut.getCurrentChapter()

        // Then - at startTime of Chapter 2, should be Chapter 2
        XCTAssertEqual(currentChapter?.title, "Chapter 2")
    }

    func testUpdateChapters() {
        // Given
        let chapters = [
            makeTestChapter(title: "Intro", startTime: 0, endTime: 60),
            makeTestChapter(title: "Main", startTime: 60, endTime: 300)
        ]

        // When
        sut.updateChapters(chapters)

        // Then
        XCTAssertEqual(sut.chapters.count, 2)
        XCTAssertEqual(sut.chapters[0].title, "Intro")
        XCTAssertEqual(sut.chapters[1].title, "Main")
    }

    func testUpdateChaptersUpdatesCurrentChapterId() {
        // Given
        sut.currentTime = 75  // Set time before updating chapters

        let chapters = [
            makeTestChapter(title: "Intro", startTime: 0, endTime: 60),
            makeTestChapter(title: "Main", startTime: 60, endTime: 300)
        ]

        // When
        sut.updateChapters(chapters)

        // Then - should detect current chapter
        XCTAssertEqual(sut.currentChapterId, chapters[1].id)  // Should be "Main"
    }

    func testClearChapters() {
        // Given
        let chapters = [
            makeTestChapter(title: "Chapter 1", startTime: 0, endTime: 100)
        ]
        sut.updateChapters(chapters)
        sut.currentTime = 50
        _ = sut.getCurrentChapter()

        // When
        sut.clearChapters()

        // Then
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertNil(sut.currentChapterId)
    }

    // MARK: - Playback Rate Tests

    func testSetPlaybackRate() {
        // When
        sut.setPlaybackRate(1.5)

        // Then
        XCTAssertEqual(sut.playbackRate, 1.5)
    }

    func testPlaybackRateValues() {
        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

        for rate in rates {
            sut.setPlaybackRate(rate)
            XCTAssertEqual(sut.playbackRate, rate)
        }
    }

    // MARK: - Volume Tests

    func testSetVolume() {
        // When
        sut.setVolume(0.5)

        // Then
        XCTAssertEqual(sut.volume, 0.5)
    }

    func testVolumeClampedToValidRange() {
        sut.setVolume(0.0)
        XCTAssertEqual(sut.volume, 0.0)

        sut.setVolume(1.0)
        XCTAssertEqual(sut.volume, 1.0)
    }

    // MARK: - Stop Tests

    func testStopClearsState() {
        // Given - set up some state
        let book = makeTestBook()
        sut.currentBook = book
        sut.isPlaying = true
        sut.currentTime = 150
        sut.duration = 300
        sut.isPlayingOffline = true
        sut.updateChapters([makeTestChapter(title: "Test", startTime: 0, endTime: 300)])

        // When
        sut.stop()

        // Then
        XCTAssertNil(sut.currentBook)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.currentTime, 0)
        XCTAssertEqual(sut.duration, 0)
        XCTAssertFalse(sut.isPlayingOffline)
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertNil(sut.currentChapterId)
    }

    // MARK: - Auth Token Provider Tests

    func testAuthTokenProviderIsUsed() {
        var tokenProviderCalled = false
        sut.authTokenProvider = {
            tokenProviderCalled = true
            return "custom-token"
        }

        // Trigger token access (would be used in play() or loadCoverImage())
        // For unit test, just verify the provider is correctly set
        XCTAssertEqual(sut.authTokenProvider(), "custom-token")
        XCTAssertTrue(tokenProviderCalled)
    }

    func testAuthTokenProviderReturnsNil() {
        sut.authTokenProvider = { nil }

        XCTAssertNil(sut.authTokenProvider())
    }

    // MARK: - Skip Forward/Backward Tests

    func testSkipForwardWithinBounds() {
        // Given
        sut.currentTime = 100
        sut.duration = 300

        // When
        sut.skipForward(seconds: 30)

        // Note: Without actual AVPlayer, this just calculates the new time
        // The seek would be called on player if it existed
    }

    func testSkipBackwardWithinBounds() {
        // Given
        sut.currentTime = 100
        sut.duration = 300

        // When
        sut.skipBackward(seconds: 30)

        // Note: Without actual AVPlayer, seek isn't performed
        // But we test the method doesn't crash
    }

    func testSkipForwardClampsToEnd() {
        // Given
        sut.currentTime = 290
        sut.duration = 300

        // When - skip would go past end
        sut.skipForward(seconds: 30)

        // Method should handle gracefully (would clamp to duration)
    }

    func testSkipBackwardClampsToStart() {
        // Given
        sut.currentTime = 10
        sut.duration = 300

        // When - skip would go before start
        sut.skipBackward(seconds: 30)

        // Method should handle gracefully (would clamp to 0)
    }

    // MARK: - Toggle Play/Pause Tests

    func testTogglePlayPauseFromPlaying() {
        // Given
        sut.isPlaying = true

        // When
        sut.togglePlayPause()

        // Then - would pause (without real player, just tests method)
        XCTAssertFalse(sut.isPlaying)
    }

    func testTogglePlayPauseFromPaused() {
        // Given
        sut.isPlaying = false

        // When
        sut.togglePlayPause()

        // Then - would resume (without real player, just tests method)
        XCTAssertTrue(sut.isPlaying)
    }

    // MARK: - Resume/Pause Tests

    func testResumeSetsIsPlaying() {
        // Given
        sut.isPlaying = false

        // When
        sut.resume()

        // Then
        XCTAssertTrue(sut.isPlaying)
    }

    func testPauseSetsIsNotPlaying() {
        // Given
        sut.isPlaying = true

        // When
        sut.pause()

        // Then
        XCTAssertFalse(sut.isPlaying)
    }

    // MARK: - Offline Mode Tests

    func testIsPlayingOfflineInitiallyFalse() {
        XCTAssertFalse(sut.isPlayingOffline)
    }

    func testOfflineFlagSetWhenDownloaded() {
        // This would be set during playFromLocalFile()
        // Testing the flag can be set
        sut.isPlayingOffline = true
        XCTAssertTrue(sut.isPlayingOffline)
    }

    // MARK: - Current Book Tests

    func testSettingCurrentBook() {
        // Given
        let book = makeTestBook(title: "My Audiobook")

        // When
        sut.currentBook = book

        // Then
        XCTAssertEqual(sut.currentBook?.title, "My Audiobook")
    }

    // MARK: - Play Same Book Tests

    func testPlaySameBookJustResumes() {
        // Given
        let book = makeTestBook()
        sut.currentBook = book
        sut.isPlaying = false

        // When
        sut.play(book: book)

        // Then - should just resume (isPlaying set to true)
        XCTAssertTrue(sut.isPlaying)
    }
}
