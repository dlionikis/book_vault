# iOS-Specific Features

**Last Updated**: December 25, 2025

> **TL;DR**: Background audio, lock screen controls, interruption handling, and future CarPlay support.

---

## Background Audio Mode

### Configuration (Info.plist)

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>

<key>NSAppleMusicUsageDescription</key>
<string>Book Vault needs access to control audio playback</string>
```

### AVAudioSession Setup

```swift
func setupAudioSession() {
    let session = AVAudioSession.sharedInstance()

    do {
        // Set category for background playback
        try session.setCategory(
            .playback,
            mode: .spokenAudio,  // Optimized for audiobooks
            options: [.allowAirPlay, .allowBluetooth]
        )

        // Activate session
        try session.setActive(true)

        // Handle route changes (headphones disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )

        // Handle interruptions (phone calls, alarms)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

    } catch {
        print("Failed to set up audio session: \(error)")
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
        // Headphones disconnected - pause playback
        pause()
    default:
        break
    }
}

@objc private func handleInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
        return
    }

    switch type {
    case .began:
        // Interruption began (phone call, alarm) - pause
        pause()

    case .ended:
        // Interruption ended
        if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Resume playback
                resume()
            }
        }

    @unknown default:
        break
    }
}
```

---

## Lock Screen Controls (MPNowPlayingInfoCenter)

### Setup Now Playing Info

```swift
func setupNowPlaying() {
    guard let book = currentBook else { return }

    var nowPlayingInfo = [String: Any]()

    // Basic metadata
    nowPlayingInfo[MPMediaItemPropertyTitle] = book.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = book.authors.map(\.name).joined(separator: ", ")
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = book.series.first?.title

    // Playback info
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0

    // Cover artwork (async load)
    Task {
        if let artwork = await loadArtwork(from: book.coverUrl) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
}

private func loadArtwork(from urlString: String) async -> MPMediaItemArtwork? {
    guard let url = URL(string: urlString),
          let data = try? Data(contentsOf: url),
          let image = UIImage(data: data) else {
        return nil
    }

    return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}

// Update playback info when time changes
func updateNowPlayingTime() {
    guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
        return
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
}
```

---

## Remote Command Center

### Setup Remote Commands

```swift
func setupRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()

    // Play command
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
        self?.resume()
        return .success
    }

    // Pause command
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
        self?.pause()
        return .success
    }

    // Toggle play/pause (AirPods, Bluetooth)
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
        self?.togglePlayPause()
        return .success
    }

    // Skip forward (15 seconds for audiobooks)
    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [15]
    commandCenter.skipForwardCommand.addTarget { [weak self] event in
        guard let event = event as? MPSkipIntervalCommandEvent else {
            return .commandFailed
        }
        self?.skip(seconds: event.interval)
        return .success
    }

    // Skip backward (15 seconds for audiobooks)
    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [15]
    commandCenter.skipBackwardCommand.addTarget { [weak self] event in
        guard let event = event as? MPSkipIntervalCommandEvent else {
            return .commandFailed
        }
        self?.skip(seconds: -event.interval)
        return .success
    }

    // Change playback position (scrubbing)
    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
        guard let event = event as? MPChangePlaybackPositionCommandEvent else {
            return .commandFailed
        }
        self?.seek(to: event.positionTime)
        return .success
    }

    // Disable unused commands
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.seekForwardCommand.isEnabled = false
    commandCenter.seekBackwardCommand.isEnabled = false
}

func togglePlayPause() {
    if isPlaying {
        pause()
    } else {
        resume()
    }
}

func skip(seconds: TimeInterval) {
    let newTime = max(0, min(duration, currentTime + seconds))
    seek(to: newTime)
}

func seek(to time: TimeInterval) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.seek(to: cmTime) { [weak self] finished in
        if finished {
            self?.currentTime = time
            self?.updateNowPlayingTime()
        }
    }
}
```

---

## Time Observer for Progress Updates

```swift
func setupTimeObserver() {
    // Update every 0.5 seconds
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)

    timeObserver = player?.addPeriodicTimeObserver(
        forInterval: interval,
        queue: .main
    ) { [weak self] time in
        guard let self = self else { return }

        self.currentTime = time.seconds

        // Update duration when available
        if let duration = self.player?.currentItem?.duration.seconds,
           duration.isFinite {
            self.duration = duration
        }

        // Update lock screen time
        self.updateNowPlayingTime()

        // Auto-save progress every 10 seconds
        if Int(self.currentTime) % 10 == 0 {
            Task {
                try? await self.saveProgress()
            }
        }

        // Mark as completed when finished
        if self.currentTime >= self.duration - 1 {
            self.markAsCompleted()
        }
    }
}

func saveProgress() async throws {
    guard let bookId = currentBook?.id else { return }

    try await apiClient.updateProgress(
        bookId: bookId,
        position: currentTime,
        completed: currentTime >= duration - 1
    )
}
```

---

## Chapter Support

### Chapter Seeking

```swift
func skipToChapter(_ chapter: Chapter) {
    let cmTime = CMTime(seconds: chapter.startTime, preferredTimescale: 600)
    player?.seek(to: cmTime) { [weak self] finished in
        if finished {
            self?.currentTime = chapter.startTime
            self?.updateNowPlayingTime()
        }
    }
}

func getCurrentChapter() -> Chapter? {
    return chapters.first { chapter in
        currentTime >= chapter.startTime && currentTime < chapter.endTime
    }
}
```

### Chapter Change Notifications

```swift
func observeChapterChanges() {
    // Monitor time observer for chapter boundaries
    var lastChapterId: String?

    timeObserver = player?.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 1, preferredTimescale: 600),
        queue: .main
    ) { [weak self] time in
        guard let self = self,
              let currentChapter = self.getCurrentChapter() else {
            return
        }

        if currentChapter.id != lastChapterId {
            lastChapterId = currentChapter.id
            self.onChapterChange?(currentChapter)
        }
    }
}
```

---

## CarPlay Support (Future)

### CarPlay Audio App Template

**Info.plist**:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneConfigurationName</key>
                <string>CarPlay Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

**CarPlay Scene Delegate**:

```swift
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let rootTemplate = buildRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true)
    }

    private func buildRootTemplate() -> CPListTemplate {
        // Continue Listening
        let continueSection = CPListSection(items: buildContinueListeningItems())

        // My Library
        let libraryItem = CPListItem(
            text: "My Library",
            detailText: nil,
            image: UIImage(systemName: "book.fill")
        )
        libraryItem.handler = { [weak self] item, completion in
            self?.showLibrary()
            completion()
        }

        let quickAccessSection = CPListSection(items: [libraryItem])

        return CPListTemplate(
            title: "Book Vault",
            sections: [continueSection, quickAccessSection]
        )
    }

    private func buildContinueListeningItems() -> [CPListItem] {
        // Fetch from API
        // Create CPListItem for each book
        return []
    }

    private func showLibrary() {
        // Build library template
    }
}
```

---

## AirPlay Support

### Enable AirPlay

```swift
func setupAudioSession() {
    let session = AVAudioSession.sharedInstance()

    try? session.setCategory(
        .playback,
        mode: .spokenAudio,
        options: [.allowAirPlay]  // Enable AirPlay
    )
}
```

### AirPlay Route Picker (SwiftUI)

```swift
import AVKit

struct NowPlayingView: View {
    var body: some View {
        VStack {
            // ... playback controls

            // AirPlay button
            AVRoutePickerView()
                .frame(width: 44, height: 44)
        }
    }
}
```

---

## Sleep Timer

### Sleep Timer Implementation

```swift
class SleepTimerService: ObservableObject {
    @Published var isActive = false
    @Published var remainingSeconds: Int = 0

    private var timer: Timer?
    private var audioPlayerService: AudioPlayerService

    init(audioPlayerService: AudioPlayerService) {
        self.audioPlayerService = audioPlayerService
    }

    func start(minutes: Int) {
        remainingSeconds = minutes * 60
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.remainingSeconds -= 1

            if self.remainingSeconds <= 0 {
                self.stop()
                self.audioPlayerService.pause()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
    }

    func addTime(minutes: Int) {
        remainingSeconds += minutes * 60
    }
}
```

**UI**:

```swift
struct SleepTimerView: View {
    @StateObject private var sleepTimer: SleepTimerService

    var body: some View {
        VStack {
            if sleepTimer.isActive {
                Text("Sleep timer: \(formattedTime)")
                    .font(.headline)

                HStack {
                    Button("+5 min") {
                        sleepTimer.addTime(minutes: 5)
                    }

                    Button("Cancel") {
                        sleepTimer.stop()
                    }
                }
            } else {
                Text("Set sleep timer")
                    .font(.headline)

                HStack {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) min") {
                            sleepTimer.start(minutes: minutes)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var formattedTime: String {
        let minutes = sleepTimer.remainingSeconds / 60
        let seconds = sleepTimer.remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

---

## Bookmarks (Future)

### Bookmark Model

```swift
struct Bookmark: Codable, Identifiable {
    let id: String
    let bookId: String
    let userId: String
    let positionSeconds: Double
    let note: String?
    let chapterId: String?
    let createdAt: String
}
```

### Bookmark Service

```swift
class BookmarkService {
    private let apiClient: APIClient

    func createBookmark(
        bookId: String,
        position: Double,
        note: String?,
        chapterId: String?
    ) async throws -> Bookmark {
        let url = URL(string: "\(apiClient.baseURL)/api/bookmarks")!
        let request = CreateBookmarkRequest(
            bookId: bookId,
            positionSeconds: position,
            note: note,
            chapterId: chapterId
        )

        return try await apiClient.authenticatedRequest(
            url: url,
            method: "POST",
            body: request
        )
    }

    func getBookmarks(bookId: String) async throws -> [Bookmark] {
        let url = URL(string: "\(apiClient.baseURL)/api/bookmarks?bookId=\(bookId)")!
        let response: BookmarkListResponse = try await apiClient.authenticatedRequest(url: url)
        return response.bookmarks
    }
}
```

---

## Widgets (Future)

### Continue Listening Widget

```swift
import WidgetKit
import SwiftUI

struct ContinueListeningWidget: Widget {
    let kind: String = "ContinueListeningWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ContinueListeningEntryView(entry: entry)
        }
        .configurationDisplayName("Continue Listening")
        .description("Quick access to your current audiobook")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ContinueListeningEntry: TimelineEntry {
    let date: Date
    let book: Book?
    let progress: UserProgress?
}

struct ContinueListeningEntryView: View {
    var entry: ContinueListeningEntry

    var body: some View {
        if let book = entry.book, let progress = entry.progress {
            VStack(alignment: .leading) {
                AsyncImage(url: URL(string: book.coverUrl))
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)

                Text(book.title)
                    .font(.caption)
                    .lineLimit(2)

                ProgressView(value: progress.positionSeconds, total: Double(book.runtimeMinutes * 60))
                    .progressViewStyle(.linear)

                Text("\(Int(progress.positionSeconds / 60)) / \(book.runtimeMinutes) min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        } else {
            Text("No current audiobook")
                .padding()
        }
    }
}
```

---

## Siri Shortcuts (Future)

### Donate Shortcuts

```swift
import Intents

func donatePlayBookIntent(book: Book) {
    let intent = PlayBookIntent()
    intent.bookTitle = book.title
    intent.bookId = book.id

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.donate { error in
        if let error = error {
            print("Failed to donate intent: \(error)")
        }
    }
}
```

**User can then say**: "Hey Siri, play [book title] in Book Vault"

---

## Best Practices

1. **Always setup AVAudioSession** before playback
2. **Handle interruptions gracefully** (phone calls, alarms)
3. **Update Now Playing info** whenever playback state changes
4. **Use MPNowPlayingInfoCenter** for lock screen controls
5. **Implement proper route change handling** (headphones disconnect)
6. **Test on real device** (background audio doesn't work in Simulator)
7. **Use .spokenAudio mode** for audiobooks (optimized for voice)
8. **Respect system audio settings** (volume, silent mode)
9. **Clean up observers** when deallocating player
10. **Test with different iOS versions** (16+)
