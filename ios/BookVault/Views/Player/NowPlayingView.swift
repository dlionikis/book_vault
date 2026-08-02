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
    /// The book whose detail page is already on screen beneath this sheet, if
    /// any. Tapping the title then just dismisses rather than routing to a
    /// duplicate of the page the user is already on. `nil` from the mini
    /// player, which can be presented over anything.
    var presentedFromBookId: UUID?

    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var sleepTimer = SleepTimerManager.shared
    @ObservedObject private var playbackSettings = PlaybackSettings.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared

    @Environment(\.dismiss) private var dismiss

    // State for showing speed picker
    @State private var showingSpeedPicker = false

    // Phase 5: State for showing chapter list
    @State private var showingChapterList = false

    // Sleep timer picker + the 1Hz tick that refreshes the countdown label.
    @State private var showingSleepTimerPicker = false
    @State private var countdownTick = Date()

    /// Display concern only. If this stalls the label goes stale, but the
    /// actual pause is driven by the audio observer in AudioPlayerManager and
    /// is unaffected.
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                        // Cover art - 35% of screen height.
                        CachedCoverImage(bookId: book.id, coverUrl: book.coverUrl)
                            .frame(height: geometry.size.height * 0.42)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                            .padding(.horizontal, 40)

                        // Book title and author - 12% of screen height
                        VStack(spacing: 4) {
                            Button {
                                openBookDetail(book)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(book.title)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                            .foregroundStyle(.primary)
                            // Same propagation caveat as the sleep button
                            // below: without .combine this inherits
                            // nowPlaying.root and can't be queried by tests.
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(book.title)
                            .accessibilityHint("Opens the book details page")

                            if !book.authors.isEmpty {
                                Text(book.authors.map(\.name).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, 16)

                        // Flexible, so everything from the chapter row down sits
                        // against the bottom of the sheet and the slack collects
                        // here instead of pooling under the controls.
                        //
                        // This replaced a fixed-percentage budget that had drifted
                        // to 103% and only survived because Spacer compressed;
                        // removing a row then left a visible hole at the bottom.
                        Spacer(minLength: geometry.size.height * 0.02)

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
                                        // Keeps a longer chapter title off the
                                        // index badge.
                                        Spacer(minLength: 8)
                                        Text("Chapter \(currentChapter.index)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .layoutPriority(1)
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

                                timeRow(
                                    leading: formatTime(audioPlayer.currentTime - currentChapter.startTime),
                                    trailing: formatTime(currentChapter.duration)
                                )
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

                                timeRow(
                                    leading: formatTime(audioPlayer.currentTime),
                                    trailing: formatTime(audioPlayer.duration)
                                )
                            }
                        }

                        // Playback controls
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

                        // Sleep timer (left) and playback speed (right) - 6% of
                        // screen height. The volume slider that used to occupy
                        // its own row was removed: AVPlayer.volume is app-local
                        // gain multiplied against system volume, so dragging it
                        // down silently capped max loudness in a way the
                        // hardware buttons couldn't undo.
                        HStack {
                            Button {
                                showingSleepTimerPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: sleepTimer.isArmed ? "moon.zzz.fill" : "moon.zzz")
                                        .font(.body)
                                    Text(sleepButtonLabel)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        // Without this the pill resizes as the
                                        // countdown ticks.
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(sleepTimer.isArmed ? 0.30 : 0.15))
                                .cornerRadius(8)
                            }
                            .foregroundStyle(.primary)
                            // Establish this as its own accessibility element
                            // before labelling it; without .combine the button
                            // inherits the container's identifier
                            // (nowPlaying.root) and can't be queried in tests.
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            // NOTE: this identifier does not survive to the
                            // accessibility tree — the root container's
                            // `A11y.NowPlaying.root` propagates to every
                            // descendant, so all buttons here report
                            // `nowPlaying.root`. UI tests must match on the
                            // label below instead. Kept for intent.
                            .accessibilityIdentifier(A11y.NowPlaying.sleepTimer)
                            .accessibilityLabel(sleepAccessibilityLabel)

                            Spacer()

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
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Playback speed, \(String(format: "%.2g", audioPlayer.playbackRate)) times")
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                        // Fixed bottom margin only. The slack lives in the
                        // flexible spacer above the chapter row, so this block
                        // stays anchored to the bottom of the sheet.
                        Spacer()
                            .frame(height: geometry.size.height * 0.04)
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
        .accessibilityIdentifier(A11y.NowPlaying.root)
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
        .sheet(isPresented: $showingSleepTimerPicker) {
            SleepTimerPicker(
                currentState: sleepTimer.state,
                hasChapters: !audioPlayer.chapters.isEmpty,
                lastUsedDuration: playbackSettings.lastSleepTimerDuration,
                currentTime: audioPlayer.currentTime,
                onSelectDuration: { duration in
                    sleepTimer.arm(.duration(duration))
                    showingSleepTimerPicker = false
                },
                onSelectEndOfChapter: {
                    sleepTimer.armEndOfChapter(chapter: audioPlayer.getCurrentChapter())
                    showingSleepTimerPicker = false
                },
                onCancel: {
                    // Goes through the player so an in-progress fade is undone.
                    audioPlayer.cancelSleepTimer()
                    showingSleepTimerPicker = false
                },
                onExtend: {
                    audioPlayer.extendSleepTimer(by: 15 * 60)
                }
            )
            .presentationDetents([.height(480)])
        }
        .onReceive(countdownTimer) { countdownTick = $0 }
    }

    // MARK: - Navigation

    /// Tapping the title leaves this sheet and shows the book's detail page.
    ///
    /// Routed through DeepLinkManager rather than a NavigationLink because this
    /// view is presented modally with no navigation stack of its own, and the
    /// destination has to appear above whatever tab the user was on.
    ///
    /// The two steps cannot be reversed or merged: ContentView presents the
    /// destination as a sheet, and SwiftUI ignores the second presentation
    /// while this one is still on screen. Setting the link on the next runloop
    /// tick lets the dismissal commit first.
    private func openBookDetail(_ book: Book) {
        dismiss()

        // Already looking at this book underneath — dismissing is the whole job.
        guard book.id != presentedFromBookId else { return }

        let id = book.id.uuidString
        DispatchQueue.main.async {
            deepLinkManager.openBook(id: id)
        }
    }

    // MARK: - Sleep Timer

    private var sleepButtonLabel: String {
        SleepTimerManager.countdownText(
            for: sleepTimer.state,
            now: countdownTick,
            currentTime: audioPlayer.currentTime
        ) ?? "Sleep"
    }

    /// Spelled out because VoiceOver reading "12:45" as digits is unhelpful.
    private var sleepAccessibilityLabel: String {
        guard sleepTimer.isArmed else { return "Sleep timer, off" }

        if case .endOfChapter? = sleepTimer.mode {
            return "Sleep timer, pausing at end of chapter"
        }

        guard let text = SleepTimerManager.countdownText(
            for: sleepTimer.state,
            now: countdownTick,
            currentTime: audioPlayer.currentTime
        ) else {
            return "Sleep timer, on"
        }

        let parts = text.split(separator: ":").compactMap { Int($0) }
        let spoken: String
        switch parts.count {
        case 3:
            spoken = "\(parts[0]) hours \(parts[1]) minutes \(parts[2]) seconds"
        case 2:
            spoken = "\(parts[0]) minutes \(parts[1]) seconds"
        default:
            spoken = text
        }
        return "Sleep timer, \(spoken) remaining"
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

    /// Whole-book remaining time, shown centred under the scrubber between the
    /// two chapter-scoped timestamps.
    ///
    /// Deliberately *not* rate-adjusted: it sits between two raw clock values,
    /// and a rate-adjusted number would jump whenever the speed changed.
    /// Phrased "8h 12m left" rather than "8:12:00" so it doesn't read as a
    /// third timestamp alongside its neighbours.
    /// Elapsed (left), whole-book remaining (centre), total (right).
    ///
    /// The outer columns share one width via `maxWidth: .infinity` rather than
    /// being separated by `Spacer()`s, so the centre label is genuinely centred
    /// on the screen instead of merely sitting between two gaps — with spacers
    /// it drifts as the two outer strings change width.
    private func timeRow(leading: String, trailing: String) -> some View {
        HStack(spacing: 8) {
            Text(leading)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            remainingInBookLabel
                .fixedSize(horizontal: true, vertical: false)

            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var remainingInBookLabel: some View {
        if let remaining = remainingInBook {
            Text(Self.formatRemaining(remaining))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                // Spells out what's counting down. VoiceOver reads this
                // between two chapter timestamps, where a bare "8h 12m left"
                // doesn't say *what* is left.
                .accessibilityLabel(Self.formatRemainingSpoken(remaining))
        }
    }

    /// `nil` while duration is still unknown (the observer fills it in on
    /// readyToPlay) so the row doesn't flash a bogus "0m left".
    private var remainingInBook: TimeInterval? {
        let remaining = audioPlayer.duration - audioPlayer.currentTime
        guard audioPlayer.duration > 0, remaining >= 0 else { return nil }
        return remaining
    }

    /// Rounds up so a book never reads "0m left" while audio is still playing.
    static func formatRemaining(_ timeInterval: TimeInterval) -> String {
        let (hours, minutes) = remainingParts(timeInterval)

        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }

    /// VoiceOver reading of the same value: "h"/"m" are read as letters, and
    /// the on-screen text doesn't say what is being counted down.
    static func formatRemainingSpoken(_ timeInterval: TimeInterval) -> String {
        let (hours, minutes) = remainingParts(timeInterval)
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"

        if hours > 0 {
            return "\(hourText) \(minuteText) left in the book"
        }
        return "\(minuteText) left in the book"
    }

    /// Rounds up, so a book still playing never reads "0m left".
    private static func remainingParts(_ timeInterval: TimeInterval) -> (hours: Int, minutes: Int) {
        let totalMinutes = Int((timeInterval / 60).rounded(.up))
        return (totalMinutes / 60, totalMinutes % 60)
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
    let onPlayPause: @MainActor () -> Void
    let onSkipBackward: @MainActor () -> Void
    let onSkipForward: @MainActor () -> Void
    let onPreviousChapter: @MainActor () -> Void
    let onNextChapter: @MainActor () -> Void

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

// MARK: - Previews

#Preview("Screenshot") {
    NowPlayingView()
        .onAppear {
            let manager = AudioPlayerManager.shared
            manager.play(book: .mockScreenshot)
            manager.updateChapters(Chapter.mockChapters)
            manager.currentTime = 2000
        }
}

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
