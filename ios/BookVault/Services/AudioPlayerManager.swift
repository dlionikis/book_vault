//
//  AudioPlayerManager.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 2: Audio Playback (Basic)
//  Phase 3: Background Audio & Lock Screen Controls
//  Phase 4: Progress Sync
//  Phase 5: Chapter Navigation
//  Phase 7: Offline Downloads - Local file playback support
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer

/// Manages audio playback using AVPlayer
/// Provides playback controls, progress tracking, and state management
@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    // MARK: - Published Properties

    @Published var currentBook: Book?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentBookCoverImage: UIImage?

    // Phase 5: Chapter Navigation
    @Published var chapters: [Chapter] = []
    @Published var currentChapterId: UUID?

    // Phase 7: Offline Downloads
    @Published var isPlayingOffline = false

    // MARK: - Dependencies (DI for testing)

    private let progressManager: any ProgressManaging
    private let downloadManager: any DownloadManaging
    private let storageManager: any StorageManaging

    // Concrete reference for download observation (protocols can't expose $publishers)
    private weak var concreteDownloadManager: DownloadManager?

    // Auth token provider (enables DI for testing)
    var authTokenProvider: () -> String? = {
        AuthManager.shared.token
    }

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var resourceLoaderDelegate: AuthenticatedAVAssetResourceLoaderDelegate?
    private var progressSaveTimer: Timer?
    private var lastSavedPosition: TimeInterval = 0
    private var downloadObserver: AnyCancellable?

    // MARK: - Computed Properties

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Initialization

    // Production singleton init
    private convenience init() {
        self.init(
            progressManager: ProgressManager.shared,
            downloadManager: DownloadManager.shared,
            storageManager: StorageManager.shared,
            concreteDownloadManager: DownloadManager.shared
        )
        setupAudioSession()
        setupNotifications()
        setupRemoteCommandCenter()
    }

    // Testable initializer
    init(
        progressManager: any ProgressManaging,
        downloadManager: any DownloadManaging,
        storageManager: any StorageManaging,
        concreteDownloadManager: DownloadManager? = nil,
        skipAudioSetup: Bool = false
    ) {
        self.progressManager = progressManager
        self.downloadManager = downloadManager
        self.storageManager = storageManager
        self.concreteDownloadManager = concreteDownloadManager

        if !skipAudioSetup {
            setupAudioSession()
            setupNotifications()
            setupRemoteCommandCenter()
        }
    }

    deinit {
        // Note: cleanup() is @MainActor isolated, but deinit is nonisolated.
        // Since AudioPlayerManager is a singleton that never deallocates in practice,
        // we just remove the notification observer directly here.
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // Configure for background audio playback
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )

            try audioSession.setActive(true)

            DebugLogger.audio("Audio session configured for background playback")

            // Setup interruption handling
            setupInterruptionObserver()

            // Setup route change handling
            setupRouteChangeObserver()
        } catch {
            DebugLogger.error("Failed to set up audio session", error: error)
            self.error = error
        }
    }

    private func setupNotifications() {
        // Observe playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        // Skip forward (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 30)
            return .success
        }

        // Skip backward (30 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [30]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 30)
            return .success
        }

        // Change playback position (scrubbing on lock screen)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }

        DebugLogger.audio("Remote command center configured")
    }

    private func updateNowPlayingInfo() {
        guard let book = currentBook else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()

        // Basic metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = book.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = book.authors.map(\.name).joined(separator: ", ")
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = book.series?.first?.title ?? "Audiobook"

        // Playback information
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0

        // Cover artwork (load asynchronously)
        Task { @MainActor in
            if let coverImage = await loadCoverImage(from: book.coverUrl ?? "") {
                let artwork = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in
                    coverImage
                }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        DebugLogger.audio("Updated Now Playing info: \(book.title)")
    }

    private func loadCoverImage(from urlString: String) async -> UIImage? {
        guard let coverUrl = URL(string: urlString) else { return nil }

        do {
            // Add authentication header for cover image
            var request = URLRequest(url: coverUrl)
            if let token = authTokenProvider() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            DebugLogger.error("Failed to load cover image", error: error)
            return nil
        }
    }

    // MARK: - Public Methods

    /// Load and play a book

    func play(book: Book) {
        // If same book, just resume
        if currentBook?.id == book.id {
            resume()
            return
        }

        // Load new book
        isLoading = true
        currentBook = book

        // Load cover image for mini player
        Task {
            currentBookCoverImage = await loadCoverImage(from: book.coverUrl ?? "")
        }

        // Get token and setup player asynchronously
        Task {
            let bookId = book.id.uuidString

            // Phase 7: Check if book is downloaded locally
            if storageManager.isBookDownloaded(bookId: bookId) {
                // Play from local file
                DebugLogger.audio("Playing from local file: \(book.title)")
                await playFromLocalFile(book: book)
                return
            }

            // Play from streaming URL (original behavior)
            await playFromStreamingUrl(book: book)
        }
    }

    /// Load a book for mini-player display without triggering playback or download
    /// Used when restoring the last-played book on app launch
    /// - Parameter book: The book to display in the mini-player
    /// - Parameter savedPosition: Optional saved position to restore
    func loadForMiniPlayer(book: Book, savedPosition: TimeInterval = 0) {
        // Only set the book info for mini-player display - no playback
        currentBook = book
        currentTime = savedPosition
        isPlaying = false
        isLoading = false

        // Load cover image for mini player
        Task {
            currentBookCoverImage = await loadCoverImage(from: book.coverUrl ?? "")
        }

        DebugLogger.audio("Loaded book for mini-player: \(book.title) at \(savedPosition)s")
    }

    /// Play from local downloaded file (Phase 7)

    private func playFromLocalFile(book: Book) async {
        let bookId = book.id.uuidString
        let localUrl = storageManager.audioFilePath(for: bookId)

        DebugLogger.audio("Starting local playback for \(book.title)")
        DebugLogger.verbose("Local file: \(localUrl.path)")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: localUrl.path) else {
            DebugLogger.error("Local file not found: \(localUrl.path)")
            self.error = NSError(
                domain: "AudioPlayerManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded file not found"]
            )
            self.isLoading = false
            return
        }

        // Create AVPlayerItem from local file (no authentication needed)
        let playerItem = AVPlayerItem(url: localUrl)

        // Create or replace player
        if self.player == nil {
            self.player = AVPlayer(playerItem: playerItem)
        } else {
            self.player?.replaceCurrentItem(with: playerItem)
        }

        // Set initial volume
        self.player?.volume = self.volume

        // Mark as playing offline
        self.isPlayingOffline = true

        // Fetch saved progress before starting playback
        if let savedProgress = try? await self.progressManager.fetchProgress(for: book.id.uuidString) {
            DebugLogger.database("Loaded saved position: \(savedProgress.positionSeconds)s")

            // If book is not completed and has saved position, seek to it
            if !savedProgress.completed, savedProgress.positionSeconds > 0 {
                self.lastSavedPosition = savedProgress.positionSeconds
            }
        }

        // Setup time observer
        self.setupTimeObserver()

        // Setup duration observer and start playback when ready
        self.setupDurationObserver(for: playerItem)
    }

    /// Play from streaming URL (original behavior)
    /// Also auto-starts download in background if not already downloading

    private func playFromStreamingUrl(book: Book) async {
        DebugLogger.audio("Starting streaming playback for \(book.title)")
        DebugLogger.verbose("Audio URL: \(book.audioUrl ?? "")")

        // Auto-start download in background (non-blocking)
        startBackgroundDownload(for: book)

        // Observe download completion to switch to local file
        observeDownloadCompletion(for: book)

        guard let url = URL(string: book.audioUrl ?? "") else {
            DebugLogger.error("Invalid audio URL: \(book.audioUrl ?? "")")
            self.error = NSError(
                domain: "AudioPlayerManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"]
            )
            self.isLoading = false
            return
        }

        let playerItem: AVPlayerItem

        // Check if this is a presigned S3 URL (contains authentication in query params)
        // S3 presigned URLs don't need our custom resource loader - play directly
        if isPresignedS3Url(url) {
            DebugLogger.audio("Detected presigned S3 URL - playing directly")
            let asset = AVURLAsset(url: url)
            playerItem = AVPlayerItem(asset: asset)
        } else {
            // Backend API URL - needs auth header via resource loader
            guard let token = authTokenProvider() else {
                DebugLogger.error("AudioPlayerManager: No authentication token")
                self.error = NSError(
                    domain: "AudioPlayerManager",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
                )
                self.isLoading = false
                return
            }

            // Convert http:// to bookvault:// so resource loader can intercept
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                DebugLogger.error("Invalid URL components")
                self.isLoading = false
                return
            }

            if components.scheme == "http" {
                components.scheme = "bookvault"
            } else if components.scheme == "https" {
                components.scheme = "bookvaults"
            }

            guard let customSchemeURL = components.url else {
                DebugLogger.error("Failed to create custom scheme URL")
                self.isLoading = false
                return
            }

            DebugLogger.verbose("Custom scheme URL: \(customSchemeURL.absoluteString)")

            // Create resource loader delegate
            self.resourceLoaderDelegate = AuthenticatedAVAssetResourceLoaderDelegate(authToken: token)

            // Create AVAsset with resource loader
            let asset = AVURLAsset(url: customSchemeURL)
            asset.resourceLoader.setDelegate(
                self.resourceLoaderDelegate,
                queue: DispatchQueue(label: "com.bookvault.resourceloader")
            )

            playerItem = AVPlayerItem(asset: asset)
        }

        // Create or replace player
        if self.player == nil {
            self.player = AVPlayer(playerItem: playerItem)
        } else {
            self.player?.replaceCurrentItem(with: playerItem)
        }

        // Set initial volume
        self.player?.volume = self.volume

        // Mark as streaming (not offline)
        self.isPlayingOffline = false

        // Fetch saved progress before starting playback
        if let savedProgress = try? await self.progressManager.fetchProgress(for: book.id.uuidString) {
            DebugLogger.database("Loaded saved position: \(savedProgress.positionSeconds)s")

            // If book is not completed and has saved position, seek to it
            if !savedProgress.completed, savedProgress.positionSeconds > 0 {
                self.lastSavedPosition = savedProgress.positionSeconds
            }
        }

        // Setup time observer
        self.setupTimeObserver()

        // Setup duration observer and start playback when ready
        self.setupDurationObserver(for: playerItem)
    }

    /// Resume playback

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        startProgressSaveTimer()
    }

    /// Pause playback

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        stopProgressSaveTimer()

        // Save progress immediately when pausing
        if let book = currentBook, currentTime > 0 {
            Task {
                do {
                    try await progressManager.saveProgress(
                        for: book.id.uuidString,
                        positionSeconds: currentTime
                    )
                    lastSavedPosition = currentTime
                    DebugLogger.database("Progress saved on pause: \(currentTime)s")
                } catch {
                    DebugLogger.error("Failed to save progress on pause", error: error)
                }
            }
        }
    }

    /// Toggle play/pause

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Seek to specific time
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime) { [weak self] completed in
            if completed {
                Task { @MainActor in
                    self?.currentTime = time
                    self?.updateNowPlayingInfo()
                }
            }
        }
    }

    /// Skip forward by seconds
    func skipForward(seconds: TimeInterval = 30) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    /// Skip backward by seconds
    func skipBackward(seconds: TimeInterval = 30) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    /// Set playback speed
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    /// Set volume
    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = volume
    }

    // MARK: - Chapter Navigation (Phase 5)

    /// Get the current chapter based on playback position
    /// - Returns: The current chapter, or nil if no chapters or not in any chapter
    func getCurrentChapter() -> Chapter? {
        guard !chapters.isEmpty else { return nil }

        return chapters.first { chapter in
            currentTime >= chapter.startTime && currentTime < chapter.endTime
        }
    }

    /// Skip to a specific chapter
    /// - Parameter chapter: The chapter to skip to
    func skipToChapter(_ chapter: Chapter) {
        seek(to: chapter.startTime)
    }

    /// Update chapters for the current book
    /// - Parameter chapters: Array of chapters to set

    func updateChapters(_ chapters: [Chapter]) {
        self.chapters = chapters

        // Update current chapter immediately
        if let currentChapter = getCurrentChapter() {
            self.currentChapterId = currentChapter.id
        }
    }

    /// Clear chapters (called when stopping playback)

    func clearChapters() {
        self.chapters = []
        self.currentChapterId = nil
    }

    /// Stop playback and cleanup

    func stop() {
        // Save final progress before stopping
        if let book = currentBook, currentTime > 0 {
            Task {
                do {
                    try await progressManager.saveProgress(
                        for: book.id.uuidString,
                        positionSeconds: currentTime
                    )
                    DebugLogger.database("Final progress saved: \(currentTime)s")
                } catch {
                    DebugLogger.error("Failed to save final progress", error: error)
                }
            }
        }

        stopProgressSaveTimer()
        downloadObserver?.cancel() // Phase 7: Cancel download observer
        downloadObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        currentBook = nil
        currentBookCoverImage = nil
        isPlaying = false
        isPlayingOffline = false // Phase 7: Reset offline flag
        currentTime = 0
        duration = 0
        lastSavedPosition = 0
        clearChapters() // Phase 5: Clear chapters
    }

    // MARK: - Private Methods

    private func setupTimeObserver() {
        // Remove existing observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }

        // Add periodic time observer (updates every 0.5 seconds)
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds

                // Update current chapter (Phase 5)
                if let currentChapter = self.getCurrentChapter() {
                    if self.currentChapterId != currentChapter.id {
                        self.currentChapterId = currentChapter.id
                        DebugLogger.audio("Chapter changed: \(currentChapter.title)")
                    }
                }
            }
        }
    }

    private func setupDurationObserver(for playerItem: AVPlayerItem) {
        // Observe status to get duration
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self else { return }

                DebugLogger.verbose("AVPlayerItem status: \(status.rawValue)")

                if status == .readyToPlay {
                    DebugLogger.audio("Duration: \(playerItem.duration.seconds) seconds")
                    self.duration = playerItem.duration.seconds
                    self.isLoading = false

                    // Seek to saved position if available
                    if self.lastSavedPosition > 0 {
                        DebugLogger.audio("Seeking to saved position: \(self.lastSavedPosition)s")
                        let cmTime = CMTime(seconds: self.lastSavedPosition, preferredTimescale: 1000)
                        self.player?.seek(to: cmTime) { [weak self] _ in
                            Task { @MainActor in
                                guard let self else { return }
                                // Start playback after seek completes
                                self.player?.play()

                                // Set playback rate after calling play()
                                if self.playbackRate != 1.0 {
                                    self.player?.rate = self.playbackRate
                                }

                                self.isPlaying = true
                                self.updateNowPlayingInfo()

                                // Start auto-save timer
                                self.startProgressSaveTimer()
                            }
                        }
                    } else {
                        // Start playback now that we're ready
                        DebugLogger.audio("Starting playback...")
                        self.player?.play()

                        // Set playback rate after calling play()
                        if self.playbackRate != 1.0 {
                            self.player?.rate = self.playbackRate
                        }

                        self.isPlaying = true

                        // Update lock screen metadata
                        self.updateNowPlayingInfo()

                        // Start auto-save timer
                        self.startProgressSaveTimer()
                    }

                    DebugLogger.verbose("Player rate: \(self.player?.rate ?? 0)")
                    DebugLogger.verbose("Player timeControlStatus: \(self.player?.timeControlStatus.rawValue ?? -1)")
                } else if status == .failed {
                    DebugLogger.error("AVPlayerItem failed", error: playerItem.error)
                    self.error = playerItem.error
                    self.isLoading = false
                }
            }
            .store(in: &cancellables)
    }

    @objc private func playerDidFinishPlaying() {
        isPlaying = false
        currentTime = 0
        // Could auto-advance to next book in series here
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            // Interruption began (phone call, alarm, etc.)
            DebugLogger.audio("Audio interruption began - pausing playback")
            Task { @MainActor in
                pause()
            }

        case .ended:
            // Interruption ended
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }

            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                DebugLogger.audio("Audio interruption ended - resuming playback")
                // Resume playback
                Task { @MainActor in
                    resume()
                }
            } else {
                DebugLogger.audio("Audio interruption ended - not resuming")
            }

        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged or Bluetooth device disconnected
            DebugLogger.audio("Audio route changed - device unavailable, pausing playback")
            Task { @MainActor in
                pause()
            }

        case .newDeviceAvailable:
            // New audio device connected
            DebugLogger.audio("Audio route changed - new device available")
// Optionally resume playback here if desired

        default:
            DebugLogger.verbose("Audio route changed - reason: \(reason.rawValue)")
        }
    }

    // MARK: - Progress Sync

    private func startProgressSaveTimer() {
        // Ensure we're on the main thread for RunLoop access
        DispatchQueue.main.async { [weak self] in
            // Stop existing timer if any
            self?.progressSaveTimer?.invalidate()

            DebugLogger.database("Starting progress save timer (10s intervals)")

            // Create timer that fires every 10 seconds
            // Must be on main thread to be added to RunLoop.main
            self?.progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.saveProgress()
                }
            }
        }
    }

    private func stopProgressSaveTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.progressSaveTimer?.invalidate()
            self?.progressSaveTimer = nil

            DebugLogger.database("Stopped progress save timer")
        }
    }

    private func saveProgress() async {
        guard let book = currentBook else { return }

        // Only save if position has changed significantly (> 1 second)
        guard abs(currentTime - lastSavedPosition) > 1.0 else { return }

        do {
            try await progressManager.saveProgress(
                for: book.id.uuidString,
                positionSeconds: currentTime
            )
            lastSavedPosition = currentTime

            DebugLogger.database("Auto-saved progress: \(currentTime)s")
        } catch {
            DebugLogger.error("Failed to save progress", error: error)
        }
    }

    // MARK: - Auto-Download & Seamless Switch (Phase 7)

    /// Start downloading the book in background while streaming
    private func startBackgroundDownload(for book: Book) {
        let bookId = book.id.uuidString

        // Don't start if already downloaded or downloading
        if storageManager.isBookDownloaded(bookId: bookId) {
            DebugLogger.download("Book already downloaded, skipping auto-download")
            return
        }

        if downloadManager.isDownloading(bookId: bookId) {
            DebugLogger.download("Book already downloading")
            return
        }

        // Start download in background (non-blocking, errors are logged but don't affect playback)
        Task {
            do {
                try await downloadManager.startDownload(book: book)
                DebugLogger.download("Auto-download started for: \(book.title)")
            } catch DownloadError.wifiRequired {
                DebugLogger.download("Auto-download skipped: WiFi required")
            } catch {
                DebugLogger.error("Auto-download failed to start", error: error)
            }
        }
    }

    /// Observe download completion and switch to local file when ready
    private func observeDownloadCompletion(for book: Book) {
        let bookId = book.id.uuidString

        // Cancel any existing observer
        downloadObserver?.cancel()

        // Observe changes to activeDownloads (requires concrete type for $publisher access)
        guard let concreteManager = concreteDownloadManager else { return }
        downloadObserver = concreteManager.$activeDownloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] downloads in
                guard let self else { return }

                // Check if this book's download just completed
                if let download = downloads[bookId], case .completed = download.state {
                    // Verify we're still playing the same book
                    guard self.currentBook?.id.uuidString == bookId else { return }

                    // Only switch if we're currently streaming (not already offline)
                    guard !self.isPlayingOffline else { return }

                    DebugLogger.audio("Download completed, switching to local file...")
                    Task { @MainActor in
                        await self.switchToLocalFile(book: book)
                    }
                }
            }
    }

    /// Seamlessly switch from streaming to local file playback
    private func switchToLocalFile(book: Book) async {
        let bookId = book.id.uuidString
        let localUrl = storageManager.audioFilePath(for: bookId)

        // Capture current state before switch
        let wasPlaying = isPlaying
        let savedPosition = currentTime

        DebugLogger.audio("Switching to local file at position: \(savedPosition)s, wasPlaying: \(wasPlaying)")

        // Pause current playback
        player?.pause()

        // Verify local file exists
        guard FileManager.default.fileExists(atPath: localUrl.path) else {
            DebugLogger.error("Local file not found during switch, continuing stream")
            if wasPlaying {
                player?.play()
            }
            return
        }

        // Create new player item from local file
        let playerItem = AVPlayerItem(url: localUrl)

        // Replace current item
        player?.replaceCurrentItem(with: playerItem)

        // Mark as playing offline
        isPlayingOffline = true

        // Override lastSavedPosition so setupDurationObserver seeks to correct position
        lastSavedPosition = savedPosition

        // Setup time observer for the new item
        setupTimeObserver()

        // Setup duration observer which will handle readyToPlay and start playback
        setupDurationObserver(for: playerItem)

        DebugLogger.audio("Local file player item configured, waiting for readyToPlay")

        // Cancel the download observer since we've switched
        downloadObserver?.cancel()
        downloadObserver = nil
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        downloadObserver?.cancel()
        downloadObserver = nil
        stopProgressSaveTimer()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - URL Detection Helpers

    /// Check if URL is a presigned S3 URL (contains authentication in query params)
    /// Presigned S3 URLs can be played directly without our custom resource loader
    private func isPresignedS3Url(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Check for S3 host patterns
        let isS3Host = host.contains(".s3.") ||
            host.contains("s3.amazonaws.com") ||
            host.hasSuffix(".amazonaws.com")

        // Check for presigned URL signature parameters
        let hasSignature = url.absoluteString.contains("X-Amz-Signature=") ||
            url.absoluteString.contains("Signature=")

        return isS3Host && hasSignature
    }
}
