//
//  AudioPlayerManager.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 2: Audio Playback (Basic)
//  Phase 3: Background Audio & Lock Screen Controls
//  Phase 4: Progress Sync
//  Phase 5: Chapter Navigation
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer

/// Manages audio playback using AVPlayer
/// Provides playback controls, progress tracking, and state management
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
    @Published var currentChapterId: UUID? = nil

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var resourceLoaderDelegate: AuthenticatedAVAssetResourceLoaderDelegate?
    private var progressSaveTimer: Timer?
    private var progressManager = ProgressManager.shared
    private var lastSavedPosition: TimeInterval = 0

    // MARK: - Computed Properties

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Initialization

    private init() {
        setupAudioSession()
        setupNotifications()
        setupRemoteCommandCenter()
    }

    deinit {
        cleanup()
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
        nowPlayingInfo[MPMediaItemPropertyArtist] = book.authors.map { $0.name }.joined(separator: ", ")
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = book.series?.first?.title ?? "Audiobook"

        // Playback information
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0

        // Cover artwork (load asynchronously)
        Task { @MainActor in
            if let coverImage = await loadCoverImage(from: book.coverUrl) {
                let artwork = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in
                    return coverImage
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
            if let token = await AuthManager.shared.token {
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
    @MainActor
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
            currentBookCoverImage = await loadCoverImage(from: book.coverUrl)
        }

        // Get token and setup player asynchronously
        Task {
            // Ensure we have authentication token
            guard let token = AuthManager.shared.token else {
                DebugLogger.error("AudioPlayerManager: No authentication token")
                self.error = NSError(
                    domain: "AudioPlayerManager",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
                )
                self.isLoading = false
                return
            }

            DebugLogger.audio("Starting playback for \(book.title)")
            DebugLogger.verbose("Audio URL: \(book.audioUrl)")

            // Create URL with custom scheme for resource loader interception
            guard let url = URL(string: book.audioUrl) else {
                DebugLogger.error("Invalid audio URL: \(book.audioUrl)")
                self.error = NSError(
                    domain: "AudioPlayerManager",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"]
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

            let playerItem = AVPlayerItem(asset: asset)

            // Create or replace player
            if self.player == nil {
                self.player = AVPlayer(playerItem: playerItem)
            } else {
                self.player?.replaceCurrentItem(with: playerItem)
            }

            // Set initial volume
            self.player?.volume = self.volume

            // Fetch saved progress before starting playback
            if let savedProgress = try? await self.progressManager.fetchProgress(for: book.id.uuidString) {
                DebugLogger.database("Loaded saved position: \(savedProgress.positionSeconds)s")

                // If book is not completed and has saved position, seek to it
                if !savedProgress.completed && savedProgress.positionSeconds > 0 {
                    self.lastSavedPosition = savedProgress.positionSeconds
                }
            }

            // Setup time observer
            self.setupTimeObserver()

            // Setup duration observer and start playback when ready
            self.setupDurationObserver(for: playerItem)
        }
    }

    /// Resume playback
    @MainActor
    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        startProgressSaveTimer()
    }

    /// Pause playback
    @MainActor
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
    @MainActor
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
                self?.currentTime = time
                self?.updateNowPlayingInfo()
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
    @MainActor
    func updateChapters(_ chapters: [Chapter]) {
        self.chapters = chapters

        // Update current chapter immediately
        if let currentChapter = getCurrentChapter() {
            self.currentChapterId = currentChapter.id
        }
    }

    /// Clear chapters (called when stopping playback)
    @MainActor
    func clearChapters() {
        self.chapters = []
        self.currentChapterId = nil
    }

    /// Stop playback and cleanup
    @MainActor
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
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        currentBook = nil
        currentBookCoverImage = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        lastSavedPosition = 0
        clearChapters()  // Phase 5: Clear chapters
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
            guard let self = self else { return }
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

    private func setupDurationObserver(for playerItem: AVPlayerItem) {
        // Observe status to get duration
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }

                DebugLogger.verbose("AVPlayerItem status: \(status.rawValue)")

                if status == .readyToPlay {
                    DebugLogger.audio("Duration: \(playerItem.duration.seconds) seconds")
                    self.duration = playerItem.duration.seconds
                    self.isLoading = false

                    // Seek to saved position if available
                    if self.lastSavedPosition > 0 {
                        DebugLogger.audio("Seeking to saved position: \(self.lastSavedPosition)s")
                        let cmTime = CMTime(seconds: self.lastSavedPosition, preferredTimescale: 1000)
                        self.player?.seek(to: cmTime) { _ in
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
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
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
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
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
            break
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

    @MainActor
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

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        stopProgressSaveTimer()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}
