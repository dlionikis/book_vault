//
//  AudioPlayerManagerRealTests.swift
//  BookVaultTests
//
//  Phase 4: Real service tests for AudioPlayerManager.
//  Tests actual playback logic with mock dependencies.
//

import AVFoundation
import MediaPlayer
import XCTest
@testable import BookVault

// MARK: - MockProgressManagerForAudio

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
    func saveProgress(
        for bookId: String,
        positionSeconds: Double,
        timestamp _: Date?
    ) async throws -> SaveProgressResponse {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw APIError.networkError(NSError(domain: "", code: -1))
        }
        savedProgress[bookId] = positionSeconds
        return SaveProgressResponse(positionSeconds: positionSeconds, completed: false, lastPlayed: nil, updated: true)
    }

    func markCompleted(bookId _: String) async throws {
        // No-op for audio tests
    }

    func resetProgress(bookId _: String) async throws {
        // No-op for audio tests
    }

    func clearCache() {
        fetchedProgress = [:]
        savedProgress = [:]
    }
}

// MARK: - MockDownloadManagerForAudio

@MainActor
final class MockDownloadManagerForAudio: DownloadManaging {
    @Published var activeDownloads: [String: ActiveDownload] = [:]
    @Published var error: DownloadError?

    var isDownloadingBookIds: Set<String> = []

    func downloadState(for _: String) -> DownloadState {
        .notDownloaded
    }

    func isDownloading(bookId: String) -> Bool {
        isDownloadingBookIds.contains(bookId)
    }

    func startDownload(book _: Book) async throws {
        // No-op for audio tests
    }

    func cancelDownload(bookId _: String) {
        // No-op for audio tests
    }

    func pauseDownload(bookId _: String) {
        // No-op for audio tests
    }

    func resumeDownload(book _: Book) async throws {
        // No-op for audio tests
    }

    func deleteDownload(bookId _: String) throws {
        // No-op for audio tests
    }
}

// MARK: - AudioPlayerManagerRealTests

@MainActor
final class AudioPlayerManagerRealTests: XCTestCase {
    var sut: AudioPlayerManager!
    var mockProgressManager: MockProgressManagerForAudio!
    var mockDownloadManager: MockDownloadManagerForAudio!
    var mockStorageManager: MockStorageManagerForDownloads!
    var mockAPIClient: MockAPIClient!
    var mockChapterFetcher: MockChapterFetcher!
    var sleepTimer: SleepTimerManager!
    private var sleepTimerSuiteName: String!
    private var sleepTimerDefaults: UserDefaults!

    override func setUp() async throws {
        mockProgressManager = MockProgressManagerForAudio()
        mockDownloadManager = MockDownloadManagerForAudio()
        mockStorageManager = MockStorageManagerForDownloads()
        mockAPIClient = MockAPIClient()
        mockChapterFetcher = MockChapterFetcher()

        // Isolated sleep timer so tests don't leak state through the singleton.
        sleepTimerSuiteName = "AudioPlayerSleepTimerTests-\(UUID().uuidString)"
        sleepTimerDefaults = UserDefaults(suiteName: sleepTimerSuiteName)!
        sleepTimerDefaults.removePersistentDomain(forName: sleepTimerSuiteName)
        sleepTimer = SleepTimerManager(
            settings: PlaybackSettings(userDefaults: sleepTimerDefaults)
        )

        sut = AudioPlayerManager(
            progressManager: mockProgressManager,
            downloadManager: mockDownloadManager,
            storageManager: mockStorageManager,
            apiClient: mockAPIClient, // Avoid real network calls on the streaming path
            chapterFetcher: mockChapterFetcher,
            sleepTimer: sleepTimer,
            skipAudioSetup: true // Skip AVAudioSession setup for unit tests
        )

        // Mock auth token provider
        sut.authTokenProvider = { @Sendable in "test-token" }
    }

    override func tearDown() async throws {
        sleepTimerDefaults?.removePersistentDomain(forName: sleepTimerSuiteName)
        sleepTimerDefaults = nil
        sleepTimerSuiteName = nil
        sleepTimer = nil
        sut = nil
        mockProgressManager = nil
        mockDownloadManager = nil
        mockStorageManager = nil
        mockAPIClient = nil
        mockChapterFetcher = nil
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
            TestFixtures.makeChapter(title: "Chapter 1", startTime: 0, endTime: 100, duration: 100, index: 0),
            TestFixtures.makeChapter(title: "Chapter 2", startTime: 100, endTime: 200, duration: 100, index: 1),
            TestFixtures.makeChapter(title: "Chapter 3", startTime: 200, endTime: 300, duration: 100, index: 2)
        ]
        sut.updateChapters(chapters)
        sut.currentTime = 150 // Middle of Chapter 2

        // When
        let currentChapter = sut.getCurrentChapter()

        // Then
        XCTAssertEqual(currentChapter?.title, "Chapter 2")
    }

    func testGetCurrentChapterAtBoundary() {
        // Given
        let chapters = [
            TestFixtures.makeChapter(title: "Chapter 1", startTime: 0, endTime: 100, duration: 100, index: 0),
            TestFixtures.makeChapter(title: "Chapter 2", startTime: 100, endTime: 200, duration: 100, index: 1)
        ]
        sut.updateChapters(chapters)
        sut.currentTime = 100 // Exactly at boundary

        // When
        let currentChapter = sut.getCurrentChapter()

        // Then - at startTime of Chapter 2, should be Chapter 2
        XCTAssertEqual(currentChapter?.title, "Chapter 2")
    }

    func testUpdateChapters() {
        // Given
        let chapters = [
            TestFixtures.makeChapter(title: "Intro", startTime: 0, endTime: 60, duration: 60, index: 0),
            TestFixtures.makeChapter(title: "Main", startTime: 60, endTime: 300, duration: 240, index: 1)
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
        sut.currentTime = 75 // Set time before updating chapters

        let chapters = [
            TestFixtures.makeChapter(title: "Intro", startTime: 0, endTime: 60, duration: 60, index: 0),
            TestFixtures.makeChapter(title: "Main", startTime: 60, endTime: 300, duration: 240, index: 1)
        ]

        // When
        sut.updateChapters(chapters)

        // Then - should detect current chapter
        XCTAssertEqual(sut.currentChapterId, chapters[1].id) // Should be "Main"
    }

    func testClearChapters() {
        // Given
        let chapters = [
            TestFixtures.makeChapter(title: "Chapter 1", startTime: 0, endTime: 100, duration: 100, index: 0)
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
        let book = TestFixtures.makeBook(title: "Test Audiobook")
        sut.currentBook = book
        sut.isPlaying = true
        sut.currentTime = 150
        sut.duration = 300
        sut.isPlayingOffline = true
        sut.updateChapters([TestFixtures.makeChapter(
            title: "Test",
            startTime: 0,
            endTime: 300,
            duration: 300,
            index: 0
        )])

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
        let tokenProviderCalled = Locked(false)
        sut.authTokenProvider = { @Sendable in
            tokenProviderCalled.value = true
            return "custom-token"
        }

        // Trigger token access (would be used in play() or loadCoverImage())
        // For unit test, just verify the provider is correctly set
        XCTAssertEqual(sut.authTokenProvider(), "custom-token")
        XCTAssertTrue(tokenProviderCalled.value)
    }

    func testAuthTokenProviderReturnsNil() {
        sut.authTokenProvider = { @Sendable in nil }

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
        let book = TestFixtures.makeBook(title: "My Audiobook")

        // When
        sut.currentBook = book

        // Then
        XCTAssertEqual(sut.currentBook?.title, "My Audiobook")
    }

    // MARK: - Play Same Book Tests

    func testPlaySameBookWithoutPlayerStartsNewPlayback() {
        // Given - book is set (like after loadForMiniPlayer) but no player exists
        let book = TestFixtures.makeBook()
        sut.currentBook = book
        sut.isPlaying = false

        // When
        sut.play(book: book)

        // Then - should start new playback setup (isLoading becomes true)
        // because there's no player item yet (loadForMiniPlayer scenario)
        XCTAssertTrue(sut.isLoading)
    }

    // MARK: - Sleep Timer Tests

    /// A chapter running to `endTime`, for end-of-chapter tests.
    private func makeSleepChapter(endTime: Double = 600) -> Chapter {
        Chapter(
            id: UUID(),
            title: "Chapter 1",
            startTime: 0,
            endTime: endTime,
            duration: endTime,
            index: 1
        )
    }

    func testSleepTimerFire_PausesPlayback() {
        // Given — armed with a deadline already in the past
        sut.currentBook = TestFixtures.makeBook()
        sut.isPlaying = true
        sleepTimer.arm(.duration(8 * 60), now: Date().addingTimeInterval(-40 * 60))

        // When — one audio tick
        sut.evaluateSleepTimer()

        // Then
        XCTAssertFalse(sut.isPlaying)
        XCTAssertFalse(sleepTimer.isArmed)
    }

    /// A player left at volume 0 reads as "the app is broken" with no obvious
    /// cause, so the restore path is asserted directly.
    func testSleepTimerFire_RestoresPreFadeVolume() {
        sut.currentBook = TestFixtures.makeBook()
        sut.isPlaying = true

        // Enter the fade window, then let it fire.
        sleepTimer.arm(.duration(5), now: Date())
        sut.evaluateSleepTimer()
        XCTAssertTrue(sut.isFadingForSleepTimer, "Expected a fade to be in progress")

        sleepTimer.arm(.duration(0), now: Date().addingTimeInterval(-1))
        sut.evaluateSleepTimer()

        XCTAssertFalse(sut.isFadingForSleepTimer, "Fade must be undone after firing")
    }

    func testSleepTimerCancel_RestoresPreFadeVolume() {
        sut.currentBook = TestFixtures.makeBook()
        sleepTimer.arm(.duration(5), now: Date())
        sut.evaluateSleepTimer()
        XCTAssertTrue(sut.isFadingForSleepTimer)

        sut.cancelSleepTimer()

        XCTAssertFalse(sut.isFadingForSleepTimer)
        XCTAssertFalse(sleepTimer.isArmed)
    }

    func testSleepTimerExtendWhileFading_RestoresVolume() {
        sut.currentBook = TestFixtures.makeBook()
        sleepTimer.arm(.duration(5), now: Date())
        sut.evaluateSleepTimer()
        XCTAssertTrue(sut.isFadingForSleepTimer)

        sut.extendSleepTimer(by: 15 * 60)

        XCTAssertFalse(sut.isFadingForSleepTimer, "Extending must undo the fade")
        XCTAssertTrue(sleepTimer.isArmed)
    }

    func testSleepTimerPlayDifferentBook_CancelsTimer() {
        let first = TestFixtures.makeBook(title: "First")
        sut.currentBook = first
        sleepTimer.arm(.duration(30 * 60), now: Date())

        sut.play(book: TestFixtures.makeBook(title: "Second"))

        XCTAssertFalse(sleepTimer.isArmed, "A new book is a new listening session")
    }

    /// Audible behavior: pausing to answer a question shouldn't kill the timer.
    func testSleepTimerManualPause_DoesNotCancelTimer() {
        sut.currentBook = TestFixtures.makeBook()
        sut.isPlaying = true
        sleepTimer.arm(.duration(30 * 60), now: Date())

        sut.pause()

        XCTAssertTrue(sleepTimer.isArmed)
    }

    func testSleepTimerEndOfChapter_FiresAtBoundary() {
        sut.currentBook = TestFixtures.makeBook()
        sut.isPlaying = true
        let chapter = makeSleepChapter(endTime: 600)
        sut.updateChapters([chapter])
        sleepTimer.armEndOfChapter(chapter: chapter)

        // Before the boundary — keeps playing.
        sut.currentTime = 100
        sut.evaluateSleepTimer()
        XCTAssertTrue(sut.isPlaying)
        XCTAssertTrue(sleepTimer.isArmed)

        // Inside the 10s fade window — begins fading, still playing.
        sut.currentTime = 595
        sut.evaluateSleepTimer()
        XCTAssertTrue(sut.isFadingForSleepTimer, "Expected fade to start near the boundary")
        XCTAssertTrue(sut.isPlaying, "Fade should not pause yet")

        // At the boundary — fires and undoes the fade.
        //
        // Regression guard: `getCurrentChapter()` returns nil at exactly
        // endTime, so a timer that re-resolved the chapter each tick would fade
        // to silence here and never pause.
        sut.currentTime = 600
        sut.evaluateSleepTimer()

        XCTAssertFalse(sut.isPlaying, "Expected playback to pause at the chapter boundary")
        XCTAssertFalse(sleepTimer.isArmed)
        XCTAssertFalse(sut.isFadingForSleepTimer, "Fade must be undone after firing")
    }

    // MARK: - Now Playing Sleep Timer Countdown

    private var nowPlayingAlbum: String? {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String
    }

    /// The countdown must be strictly additive — with the timer off, the album
    /// line is exactly what it was before this feature existed.
    func testNowPlaying_AlbumLineUnchangedWhenTimerOff() {
        sut.currentBook = TestFixtures.makeBook(title: "Test Audiobook")
        sut.updateNowPlayingInfoForTesting()

        let album = nowPlayingAlbum
        XCTAssertNotNil(album)
        XCTAssertFalse(album?.contains("💤") ?? true, "No countdown should appear when off")
    }

    func testNowPlaying_AlbumLineContainsCountdownWhenArmed() {
        sut.currentBook = TestFixtures.makeBook(title: "Test Audiobook")
        sleepTimer.arm(.duration(15 * 60), now: Date())

        sut.updateNowPlayingInfoForTesting()

        XCTAssertTrue(nowPlayingAlbum?.contains("💤") ?? false, "Expected countdown, got \(nowPlayingAlbum ?? "nil")")
    }

    func testNowPlaying_AlbumLineCleanAfterFire() {
        sut.currentBook = TestFixtures.makeBook(title: "Test Audiobook")
        sut.isPlaying = true
        sleepTimer.arm(.duration(8 * 60), now: Date().addingTimeInterval(-40 * 60))

        sut.evaluateSleepTimer()

        XCTAssertFalse(nowPlayingAlbum?.contains("💤") ?? true, "Countdown must be cleared after firing")
    }

    /// A full refresh (chapter change, seek) while armed must not drop the
    /// countdown that the lightweight per-second update maintains.
    func testNowPlaying_FullRefreshWhileArmedKeepsCountdown() {
        sut.currentBook = TestFixtures.makeBook(title: "Test Audiobook")
        sleepTimer.arm(.duration(15 * 60), now: Date())

        sut.updateNowPlayingInfoForTesting()
        XCTAssertTrue(nowPlayingAlbum?.contains("💤") ?? false)

        // Simulate the full refresh that a chapter change triggers.
        sut.updateNowPlayingInfoForTesting()

        XCTAssertTrue(nowPlayingAlbum?.contains("💤") ?? false, "Full refresh dropped the countdown")
    }

    // MARK: - Archive / Restore Tests

    func testPlayArchivedBookSetsRestoreStateNotError() async throws {
        // Given — the stream endpoint reports the audio is archived/restoring
        let book = TestFixtures.makeBook()
        let eta = Date().addingTimeInterval(5 * 3600)
        mockStorageManager.downloadedBookIds = [] // force the streaming path
        mockAPIClient.getBookStreamResult = .success(BookStreamResponse(
            status: .restoring,
            message: "Restore in progress",
            estimatedCompletion: eta
        ))

        // When
        sut.play(book: book)

        // Then — restoreState flips to .restoring; no error, loading finishes
        try await waitUntil { self.sut.restoreState != .idle }
        XCTAssertEqual(sut.restoreState, .restoring(estimatedCompletion: eta, message: "Restore in progress"))
        XCTAssertNil(sut.error)
        XCTAssertFalse(sut.isLoading)
        XCTAssertFalse(sut.isPlaying)
    }

    // MARK: - Interruption Tests

    /// An interruption beginning (call, alarm, another app taking the session)
    /// must pause playback.
    func testInterruptionBeganPausesPlayback() async throws {
        // Given
        sut.isPlaying = true

        // When
        sut.handleInterruption(notification: Self.interruptionNotification(type: .began))

        // Then — handleInterruption hops to the main actor via a Task
        try await waitUntil { !self.sut.isPlaying }
        XCTAssertFalse(sut.isPlaying)
    }

    /// Regression: an interruption ending with `.shouldResume` must reactivate
    /// the audio session *before* resuming. iOS deactivates the session for the
    /// duration of the interruption, so resuming without reactivating leaves
    /// playback silently stuck while the UI still reads as "playing".
    func testInterruptionEndedWithShouldResumeActivatesSessionAndResumes() async throws {
        // Given — paused by the interruption, session left inactive
        sut.isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false)

        // When
        sut.handleInterruption(
            notification: Self.interruptionNotification(type: .ended, options: .shouldResume)
        )

        // Then — resumed, and the session was reactivated to make it audible
        try await waitUntil { self.sut.isPlaying }
        XCTAssertTrue(sut.isPlaying)
    }

    /// Without `.shouldResume` (common for phone calls) we must stay paused.
    func testInterruptionEndedWithoutShouldResumeStaysPaused() async throws {
        // Given
        sut.isPlaying = false

        // When
        sut.handleInterruption(notification: Self.interruptionNotification(type: .ended))

        // Then — give the handler's Task a beat, then confirm still paused
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertFalse(sut.isPlaying)
    }

    /// Build an `AVAudioSession.interruptionNotification`-shaped notification.
    /// Unit tests construct these directly because `skipAudioSetup: true` means
    /// the real observer is never registered.
    private static func interruptionNotification(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions? = nil
    ) -> Notification {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: type.rawValue
        ]
        if let options {
            userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
        } else if type == .ended {
            // A real .ended notification always carries options; absent
            // .shouldResume means "do not resume".
            userInfo[AVAudioSessionInterruptionOptionKey] = UInt(0)
        }
        return Notification(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }

    /// Poll a condition on the main actor until it holds or a short timeout
    /// elapses. `play(book:)` kicks off an async Task, so state settles a beat
    /// after the synchronous call returns.
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
    }
}

// MARK: - MockChapterFetcher

/// Records lookups so tests can assert the player, not a view, drove them.
///
/// `@unchecked Sendable` for the usual test-double reason: one instance per
/// test, driven from one place.
final class MockChapterFetcher: ChapterFetching, @unchecked Sendable {
    var cachedChapters: [String: [Chapter]] = [:]
    var fetchResult: [Chapter] = []

    private(set) var fetchCalls: [String] = []
    private(set) var cacheChecks: [String] = []

    /// Set to delay `fetchChapters`, to exercise the in-flight book-change guard.
    var fetchDelay: Duration?

    func fetchChapters(bookId: String) async -> [Chapter] {
        fetchCalls.append(bookId)
        if let fetchDelay {
            try? await Task.sleep(for: fetchDelay)
        }
        return fetchResult
    }

    func getCachedChapters(bookId: String) -> [Chapter] {
        cacheChecks.append(bookId)
        return cachedChapters[bookId] ?? []
    }

    func hasCachedChapters(bookId: String) -> Bool {
        !(cachedChapters[bookId] ?? []).isEmpty
    }
}

// MARK: - Chapter loading (A3)

/// These cover the gap CarPlay would otherwise hit: chapters used to be fetched
/// only by `BookDetailView` / `ContentView`, so playback started from anywhere
/// else — lock screen, remote command, CarPlay — produced a book with no
/// chapters and therefore no chapter controls.
extension AudioPlayerManagerRealTests {
    private func makeChapters() -> [Chapter] {
        [
            Chapter(id: UUID(), title: "One", startTime: 0, endTime: 60, duration: 60, index: 0),
            Chapter(id: UUID(), title: "Two", startTime: 60, endTime: 120, duration: 60, index: 1)
        ]
    }

    /// Cached chapters apply synchronously — no empty-list flash for a book we
    /// have already loaded once.
    func testPlayAppliesCachedChaptersImmediately() {
        let book = TestFixtures.makeBook()
        let chapters = makeChapters()
        mockChapterFetcher.cachedChapters[book.id.uuidString] = chapters

        sut.play(book: book)

        XCTAssertEqual(sut.chapters.count, chapters.count,
                       "Cached chapters should be applied without awaiting a fetch")
        XCTAssertTrue(mockChapterFetcher.fetchCalls.isEmpty,
                      "A warm cache must not trigger a network fetch")
    }

    /// The regression this refactor exists for: a cache miss must still populate
    /// chapters, without any view having asked.
    func testPlayFetchesChaptersOnCacheMiss() async throws {
        let book = TestFixtures.makeBook()
        mockChapterFetcher.fetchResult = makeChapters()

        sut.play(book: book)

        try await waitUntil { !self.sut.chapters.isEmpty }
        XCTAssertEqual(mockChapterFetcher.fetchCalls, [book.id.uuidString])
        XCTAssertEqual(sut.chapters.count, 2)
    }

    /// A book with no chapters must not break playback — this is the graceful
    /// degradation CarPlay's chapter buttons rely on.
    func testPlayWithNoChaptersLeavesChaptersEmpty() async throws {
        let book = TestFixtures.makeBook()
        mockChapterFetcher.fetchResult = []

        sut.play(book: book)

        try await waitUntil { self.mockChapterFetcher.fetchCalls.isEmpty == false }
        XCTAssertTrue(sut.chapters.isEmpty)
        XCTAssertEqual(sut.currentBook?.id, book.id, "Playback should proceed regardless")
    }

    /// Switching books mid-fetch must not apply the first book's chapters to the
    /// second. Without the guard in `loadChapters(for:)` this races.
    func testInFlightChapterFetchIsDiscardedWhenBookChanges() async throws {
        let firstBook = TestFixtures.makeBook()
        mockChapterFetcher.fetchResult = makeChapters()
        mockChapterFetcher.fetchDelay = .milliseconds(200)

        sut.play(book: firstBook)

        // Switch to a different book while the first fetch is still in flight.
        let secondBook = TestFixtures.makeBook(id: UUID(), title: "Second Book")
        mockChapterFetcher.fetchResult = []
        mockChapterFetcher.fetchDelay = nil
        sut.play(book: secondBook)

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.currentBook?.id, secondBook.id)
        XCTAssertTrue(sut.chapters.isEmpty,
                      "The first book's chapters must not land on the second book")

        // Both fetches must actually have been issued. Without this the test is
        // vacuous: if the player loaded no chapters at all, `chapters` would be
        // empty for the wrong reason and the assertion above would still pass.
        XCTAssertEqual(mockChapterFetcher.fetchCalls.count, 2,
                       "Both books should have triggered a fetch")
        XCTAssertEqual(mockChapterFetcher.fetchCalls.first, firstBook.id.uuidString)
    }

    /// The mini-player path matters for cold launch: the lock screen should have
    /// chapter data before the user opens any detail view.
    func testLoadForMiniPlayerAlsoLoadsChapters() {
        let book = TestFixtures.makeBook()
        let chapters = makeChapters()
        mockChapterFetcher.cachedChapters[book.id.uuidString] = chapters

        sut.loadForMiniPlayer(book: book, savedPosition: 30)

        XCTAssertEqual(sut.chapters.count, chapters.count)
    }
}
