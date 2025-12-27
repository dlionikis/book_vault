//
//  AudioPlayerManager.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 2: Audio Playback (Basic)
//

import Foundation
import AVFoundation
import Combine

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

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Initialization

    private init() {
        setupAudioSession()
        setupNotifications()
    }

    deinit {
        cleanup()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
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

        // Get token and setup player asynchronously
        Task { @MainActor in
            // Ensure we have authentication token
            guard let token = AuthManager.shared.token else {
                self.error = NSError(
                    domain: "AudioPlayerManager",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
                )
                self.isLoading = false
                return
            }

            // Create URL request with authentication
            guard let url = URL(string: book.audioUrl) else {
                self.error = NSError(
                    domain: "AudioPlayerManager",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"]
                )
                self.isLoading = false
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            // Create AVAsset with headers
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]])
            let playerItem = AVPlayerItem(asset: asset)

            // Create or replace player
            if self.player == nil {
                self.player = AVPlayer(playerItem: playerItem)
            } else {
                self.player?.replaceCurrentItem(with: playerItem)
            }

            // Set initial playback rate and volume
            self.player?.rate = self.playbackRate
            self.player?.volume = self.volume

            // Setup time observer
            self.setupTimeObserver()

            // Setup duration observer
            self.setupDurationObserver(for: playerItem)

            // Start playing
            self.player?.play()
            self.isPlaying = true
            self.isLoading = false
        }
    }

    /// Resume playback
    func resume() {
        player?.play()
        isPlaying = true
    }

    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
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
                self?.currentTime = time
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
    }

    /// Set volume
    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = volume
    }

    /// Stop playback and cleanup
    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        currentBook = nil
        isPlaying = false
        currentTime = 0
        duration = 0
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
            self?.currentTime = time.seconds
        }
    }

    private func setupDurationObserver(for playerItem: AVPlayerItem) {
        // Observe status to get duration
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.duration = playerItem.duration.seconds
                    self?.isLoading = false
                } else if status == .failed {
                    self?.error = playerItem.error
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)
    }

    @objc private func playerDidFinishPlaying() {
        isPlaying = false
        currentTime = 0
        // Could auto-advance to next book in series here
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}
