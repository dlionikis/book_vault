//
//  NowPlayingView.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Phase 2: Audio Playback (Basic)
//

import SwiftUI

// MARK: - NowPlayingView

struct NowPlayingView: View {
    @StateObject private var audioPlayer = AudioPlayerManager.shared

    // State for showing speed picker
    @State private var showingSpeedPicker = false

    // Phase 5: State for showing chapter list
    @State private var showingChapterList = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.3),
                        Color.purple.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top spacer for drag indicator
                    Spacer()
                        .frame(height: geometry.size.height * 0.05)

                    if let book = audioPlayer.currentBook {
                        // Cover art - 40% of screen height (increased from 35%)
                        CachedCoverImage(bookId: book.id, coverUrl: book.coverUrl)
                            .frame(height: geometry.size.height * 0.40)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                            .padding(.horizontal, 40)

                        // Book title and author - 12% of screen height
                        VStack(spacing: 4) {
                            Text(book.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal)

                            if !book.authors.isEmpty {
                                Text(book.authors.map(\.name).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                            }
                        }
                        .frame(height: geometry.size.height * 0.12)

                        // Spacer to push controls down
                        Spacer()
                            .frame(height: geometry.size.height * 0.03)

                        // Progress bar and time labels - 10% of screen height
                        VStack(spacing: 8) {
                            // Phase 5: Current chapter indicator (tappable)
                            if let currentChapter = audioPlayer.getCurrentChapter() {
                                Button {
                                    showingChapterList = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(currentChapter.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("Chapter \(currentChapter.index)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 32)
                                .padding(.bottom, 4)
                            }

                            // Chapter-scoped progress bar
                            if let currentChapter = audioPlayer.getCurrentChapter() {
                                ProgressBarView(
                                    currentTime: audioPlayer.currentTime - currentChapter.startTime,
                                    duration: currentChapter.duration,
                                    onSeek: { chapterRelativeTime in
                                        audioPlayer.seek(to: currentChapter.startTime + chapterRelativeTime)
                                    }
                                )
                                .padding(.horizontal, 32)

                                HStack {
                                    Text(formatTime(audioPlayer.currentTime - currentChapter.startTime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatTime(currentChapter.duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 32)
                            } else {
                                // Fallback: Full book progress (no chapters)
                                ProgressBarView(
                                    currentTime: audioPlayer.currentTime,
                                    duration: audioPlayer.duration,
                                    onSeek: { time in
                                        audioPlayer.seek(to: time)
                                    }
                                )
                                .padding(.horizontal, 32)

                                HStack {
                                    Text(formatTime(audioPlayer.currentTime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatTime(audioPlayer.duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 32)
                            }
                        }
                        .frame(height: geometry.size.height * 0.1)

                        // Playback controls - 15% of screen height
                        PlaybackControlsView(
                            isPlaying: audioPlayer.isPlaying,
                            chapters: audioPlayer.chapters,
                            currentChapterId: audioPlayer.currentChapterId,
                            onPlayPause: {
                                audioPlayer.togglePlayPause()
                            },
                            onSkipBackward: {
                                audioPlayer.skipBackward(seconds: 30)
                            },
                            onSkipForward: {
                                audioPlayer.skipForward(seconds: 30)
                            },
                            onPreviousChapter: {
                                // Smart back: restart chapter if >30s in, otherwise go to previous
                                if let currentChapter = audioPlayer.getCurrentChapter() {
                                    let positionInChapter = audioPlayer.currentTime - currentChapter.startTime

                                    // If more than 30 seconds into chapter, restart current chapter
                                    if positionInChapter > 30 {
                                        audioPlayer.seek(to: currentChapter.startTime)
                                    }
                                    // Otherwise, go to previous chapter
                                    else if let currentIndex = audioPlayer.chapters
                                        .firstIndex(where: { $0.id == currentChapter.id }),
                                        currentIndex > 0 {
                                        audioPlayer.skipToChapter(audioPlayer.chapters[currentIndex - 1])
                                    }
                                    // If at first chapter and within first 30s, just go to start
                                    else {
                                        audioPlayer.seek(to: currentChapter.startTime)
                                    }
                                }
                            },
                            onNextChapter: {
                                if let currentChapter = audioPlayer.getCurrentChapter(),
                                   let currentIndex = audioPlayer.chapters
                                   .firstIndex(where: { $0.id == currentChapter.id }),
                                   currentIndex < audioPlayer.chapters.count - 1 {
                                    audioPlayer.skipToChapter(audioPlayer.chapters[currentIndex + 1])
                                }
                            }
                        )
                        .frame(height: geometry.size.height * 0.15)
                        .padding(.horizontal, 32)

                        // Volume and Speed controls - 10% of screen height
                        HStack(spacing: 20) {
                            // Volume control
                            HStack(spacing: 12) {
                                Image(systemName: volumeIcon(for: audioPlayer.volume))
                                    .font(.body)
                                    .frame(width: 24)
                                Slider(
                                    value: Binding(
                                        get: { audioPlayer.volume },
                                        set: { audioPlayer.setVolume($0) }
                                    ),
                                    in: 0 ... 1
                                )
                            }

                            // Playback speed button (compact)
                            Button {
                                showingSpeedPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "speedometer")
                                        .font(.body)
                                    Text(String(format: "%.2gx", audioPlayer.playbackRate))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(minWidth: 32)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(8)
                            }
                            .foregroundStyle(.primary)
                        }
                        .frame(height: geometry.size.height * 0.1)
                        .padding(.horizontal, 32)

                        // Bottom spacer - 8% of screen height
                        Spacer()
                            .frame(height: geometry.size.height * 0.08)
                    } else {
                        // No book loaded
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 80))
                                .foregroundStyle(.secondary)
                            Text("No audiobook selected")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChapterList) {
            ChapterListView(
                chapters: audioPlayer.chapters,
                currentChapterId: audioPlayer.currentChapterId,
                onChapterTap: { chapter in
                    audioPlayer.skipToChapter(chapter)
                    showingChapterList = false
                }
            )
        }
        .sheet(isPresented: $showingSpeedPicker) {
            PlaybackSpeedPicker(
                currentRate: audioPlayer.playbackRate,
                onSelect: { rate in
                    audioPlayer.setPlaybackRate(rate)
                    showingSpeedPicker = false
                }
            )
            .presentationDetents([.height(400)])
        }
    }

    // MARK: - Helper Methods

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func volumeIcon(for volume: Float) -> String {
        if volume == 0 {
            "speaker.fill"
        } else if volume < 0.33 {
            "speaker.wave.1.fill"
        } else if volume < 0.66 {
            "speaker.wave.2.fill"
        } else {
            "speaker.wave.3.fill"
        }
    }
}

// MARK: - ProgressBarView

struct ProgressBarView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var draggedValue: Double = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? draggedValue : currentTime / duration
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)

                // Progress track
                Capsule()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * progress, height: 6)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: max(0, min(geometry.size.width * progress - 10, geometry.size.width - 20)))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        draggedValue = newProgress
                    }
                    .onEnded { value in
                        isDragging = false
                        let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        let newTime = newProgress * duration
                        onSeek(newTime)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - PlaybackControlsView

struct PlaybackControlsView: View {
    let isPlaying: Bool
    let chapters: [Chapter]
    let currentChapterId: UUID?
    let onPlayPause: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void

    var canGoPreviousChapter: Bool {
        guard let currentChapterId,
              let currentIndex = chapters.firstIndex(where: { $0.id == currentChapterId })
        else {
            return false
        }
        return currentIndex > 0
    }

    var canGoNextChapter: Bool {
        guard let currentChapterId,
              let currentIndex = chapters.firstIndex(where: { $0.id == currentChapterId })
        else {
            return false
        }
        return currentIndex < chapters.count - 1
    }

    var body: some View {
        HStack(spacing: 20) {
            // Previous chapter (only show if chapters available)
            if !chapters.isEmpty {
                Button(action: onPreviousChapter) {
                    Label("Previous Chapter", systemImage: "backward.end.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 28))
                        .foregroundStyle(canGoPreviousChapter ? Color.primary : Color.secondary.opacity(0.3))
                }
                .disabled(!canGoPreviousChapter)
                .frame(width: 44, height: 44)
            }

            // Skip backward 30s
            Button(action: onSkipBackward) {
                Image(systemName: "gobackward.30")
                    .font(.system(size: 32))
                    .foregroundStyle(.primary)
            }

            // Play/Pause
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)
            }

            // Skip forward 30s
            Button(action: onSkipForward) {
                Image(systemName: "goforward.30")
                    .font(.system(size: 32))
                    .foregroundStyle(.primary)
            }

            // Next chapter (only show if chapters available)
            if !chapters.isEmpty {
                Button(action: onNextChapter) {
                    Label("Next Chapter", systemImage: "forward.end.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 28))
                        .foregroundStyle(canGoNextChapter ? Color.primary : Color.secondary.opacity(0.3))
                }
                .disabled(!canGoNextChapter)
                .frame(width: 44, height: 44)
            }
        }
    }
}

// MARK: - PlaybackSpeedPicker

struct PlaybackSpeedPicker: View {
    let currentRate: Float
    let onSelect: (Float) -> Void

    // Speed range: 0.5x to 3.0x in 0.05 increments
    private let minSpeed: Float = 0.5
    private let maxSpeed: Float = 3.0
    private let increment: Float = 0.05

    // Quick presets for common speeds
    private let presets: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    @State private var selectedRate: Float

    init(currentRate: Float, onSelect: @escaping (Float) -> Void) {
        self.currentRate = currentRate
        self.onSelect = onSelect
        self._selectedRate = State(initialValue: currentRate)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Current speed display
                VStack(spacing: 4) {
                    Text(String(format: "%.2fx", selectedRate))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Playback Speed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Fine-grained stepper controls
                HStack(spacing: 16) {
                    // Decrease by 0.05
                    Button {
                        adjustSpeed(by: -increment)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(selectedRate > minSpeed ? .blue : .gray.opacity(0.3))
                    }
                    .disabled(selectedRate <= minSpeed)

                    // Slider for continuous adjustment
                    Slider(
                        value: Binding(
                            get: { selectedRate },
                            set: { newValue in
                                // Round to nearest 0.05
                                selectedRate = roundToIncrement(newValue)
                            }
                        ),
                        in: minSpeed ... maxSpeed,
                        step: increment
                    )
                    .tint(.blue)

                    // Increase by 0.05
                    Button {
                        adjustSpeed(by: increment)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(selectedRate < maxSpeed ? .blue : .gray.opacity(0.3))
                    }
                    .disabled(selectedRate >= maxSpeed)
                }
                .padding(.horizontal, 20)

                // Quick preset buttons
                VStack(spacing: 12) {
                    Text("Quick Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 12) {
                        ForEach(presets, id: \.self) { speed in
                            Button {
                                selectedRate = speed
                            } label: {
                                Text(String(format: "%.2gx", speed))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(abs(selectedRate - speed) < 0.01 ? Color.blue : Color.gray.opacity(0.15))
                                    )
                                    .foregroundStyle(abs(selectedRate - speed) < 0.01 ? .white : .primary)
                            }
                        }
                    }
                }

                Spacer()

                // Apply button
                Button {
                    onSelect(selectedRate)
                } label: {
                    Text("Apply")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func adjustSpeed(by amount: Float) {
        let newSpeed = selectedRate + amount
        selectedRate = max(minSpeed, min(maxSpeed, roundToIncrement(newSpeed)))
    }

    private func roundToIncrement(_ value: Float) -> Float {
        (value / increment).rounded() * increment
    }
}

// MARK: - Previews

#Preview("Playing - With Chapters") {
    NowPlayingView()
        .onAppear {
            let manager = AudioPlayerManager.shared
            manager.play(book: .mockStandard)
            manager.updateChapters(Chapter.mockChapters)
            manager.currentTime = 2000 // In Chapter 2
        }
}

#Preview("Playing - No Chapters") {
    NowPlayingView()
        .onAppear {
            let manager = AudioPlayerManager.shared
            manager.play(book: .mockMinimal)
            manager.updateChapters([])
        }
}

#Preview("Paused") {
    NowPlayingView()
        .onAppear {
            let manager = AudioPlayerManager.shared
            manager.play(book: .mockLongTitle)
            manager.updateChapters(Chapter.mockChapters)
            manager.pause()
        }
}

#Preview("No Book Loaded") {
    NowPlayingView()
        .onAppear {
            let manager = AudioPlayerManager.shared
            manager.stop()
        }
}

#Preview("Dark Mode") {
    NowPlayingView()
        .onAppear {
            let manager = AudioPlayerManager.shared
            manager.play(book: .mockStandard)
            manager.updateChapters(Chapter.mockChapters)
        }
        .preferredColorScheme(.dark)
}
