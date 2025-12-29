# iOS Phase 7: Offline Downloads - Implementation Plan

**Status**: Ready to implement
**Priority**: Optional (can be deferred post-launch)
**Estimated Complexity**: High
**Last Updated**: December 28, 2025

> **TL;DR**: Enable users to download audiobooks for offline listening with background downloads, storage management, and seamless switching between streaming and local playback.

---

## Overview

Phase 7 adds offline download capability to the iOS app, allowing users to download audiobooks to their device for listening without an internet connection. This is the final optional phase before launch.

**Key Benefits**:

- Listen during flights, commutes, or areas with poor connectivity
- Save cellular data by downloading on WiFi
- Instant playback start (no buffering)
- Background downloading (continue using app while downloading)

---

## Backend API Readiness ✅

The backend already provides complete download support:

### Available Endpoints

1. **`POST /api/downloads/{bookId}`** - Generate pre-signed download URL
   - Returns temporary S3 URL (expires in 1 hour)
   - Includes file size for progress tracking
   - Rate limited to 10 downloads per day

2. **`GET /api/downloads/{bookId}/check`** - Check download eligibility
   - Verifies book exists and user is authorized
   - Returns remaining daily download quota

3. **`GET /api/downloads`** - Get download history
   - Last 50 downloads
   - Daily count for rate limit display

**No backend changes needed** - all APIs are ready to use!

---

## Architecture Design

### Component Overview

```
┌─────────────────────────────────────────────┐
│          DownloadManager (Service)          │
│  - URLSession background downloads          │
│  - Progress tracking & notifications        │
│  - Download queue management                │
│  - Retry logic & error handling             │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│       StorageManager (Service)              │
│  - File system operations (save/delete)     │
│  - Storage size calculation                 │
│  - Cache management & limits                │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│       AudioPlayerManager (Enhanced)         │
│  - Play from URL (streaming) OR             │
│  - Play from local file (offline)           │
│  - Automatic source selection               │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│              UI Components                  │
│  - Download button (Book Detail)            │
│  - Downloads tab (management screen)        │
│  - Download progress indicators             │
│  - Storage settings view                    │
└─────────────────────────────────────────────┘
```

### File Storage Structure

```
<App Documents>/
├── downloads/
│   ├── metadata.json                 # Index of all downloads
│   └── audiobooks/
│       ├── {bookId}.m4a             # Audio file
│       └── {bookId}.jpg             # Cover image (optional)
```

**`metadata.json` structure**:

```json
{
  "version": 1,
  "downloads": [
    {
      "bookId": "uuid",
      "title": "Book Title",
      "author": "Author Name",
      "downloadedAt": "2025-12-28T10:00:00Z",
      "fileSize": 125829120,
      "audioPath": "audiobooks/{bookId}.m4a",
      "coverPath": "audiobooks/{bookId}.jpg"
    }
  ],
  "totalSize": 125829120
}
```

---

## Implementation Tasks

### Task 1: Storage Manager Service

**File**: `ios/BookVault/Services/StorageManager.swift`

**Responsibilities**:

- File system operations (save, delete, check existence)
- Calculate storage usage
- Enforce storage limits
- Manage download metadata index

**Key Methods**:

```swift
class StorageManager {
    static let shared = StorageManager()

    // File paths
    func audioFilePath(for bookId: String) -> URL
    func coverImagePath(for bookId: String) -> URL
    func metadataFilePath() -> URL

    // Storage operations
    func saveAudioFile(data: Data, bookId: String) throws
    func deleteDownload(bookId: String) throws
    func isBookDownloaded(bookId: String) -> Bool

    // Metadata management
    func loadMetadata() -> DownloadMetadata
    func saveMetadata(_ metadata: DownloadMetadata)
    func addDownload(book: Book, fileSize: Int64)
    func removeDownload(bookId: String)

    // Storage info
    func totalDownloadedSize() -> Int64
    func availableSpace() -> Int64
    func canDownload(fileSize: Int64) -> Bool
}
```

**Storage Limits**:

- Default limit: 5 GB (configurable in settings)
- Warn user at 90% capacity
- Prevent downloads if limit would be exceeded

---

### Task 2: Download Manager Service

**File**: `ios/BookVault/Services/DownloadManager.swift`

**Responsibilities**:

- Initiate downloads via URLSession
- Track download progress
- Handle background downloads
- Retry failed downloads
- Rate limit enforcement

**Key Methods**:

```swift
@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    // Download state
    @Published var activeDownloads: [String: DownloadProgress] = [:]
    @Published var downloadHistory: [DownloadHistoryItem] = []

    // Download operations
    func startDownload(bookId: String) async throws
    func cancelDownload(bookId: String)
    func pauseDownload(bookId: String)
    func resumeDownload(bookId: String)

    // Status checks
    func checkEligibility(bookId: String) async throws -> DownloadEligibility
    func isDownloading(bookId: String) -> Bool
    func downloadProgress(bookId: String) -> Double?

    // History
    func fetchDownloadHistory() async throws
}

struct DownloadProgress {
    let bookId: String
    let title: String
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var progress: Double // 0.0 to 1.0
    var state: DownloadState
}

enum DownloadState {
    case waiting, downloading, paused, completed, failed
}

struct DownloadEligibility {
    let canDownload: Bool
    let remainingQuota: Int
    let reason: String?
}
```

**Background Download Support**:

```swift
// Use URLSession background configuration
private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(
        withIdentifier: "com.bookvault.downloads"
    )
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
}()

// Implement URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                   downloadTask: URLSessionDownloadTask,
                   didFinishDownloadingTo location: URL) {
        // Move file to permanent location
        // Update metadata
        // Post notification
    }

    func urlSession(_ session: URLSession,
                   downloadTask: URLSessionDownloadTask,
                   didWriteData bytesWritten: Int64,
                   totalBytesWritten: Int64,
                   totalBytesExpectedToWrite: Int64) {
        // Update progress UI
    }
}
```

---

### Task 3: Audio Player Manager Enhancement

**File**: `ios/BookVault/Services/AudioPlayerManager.swift` (modify existing)

**Changes**:

- Add local file playback support
- Auto-detect if book is downloaded
- Prefer local file over streaming
- Fallback to streaming if local file missing

**Enhanced Methods**:

```swift
// Existing method signature changes
func loadBook(
    _ book: Book,
    audioUrl: String,
    coverUrl: String?,
    startPosition: Double = 0
) {
    // NEW: Check if book is downloaded locally
    if StorageManager.shared.isBookDownloaded(bookId: book.id) {
        let localUrl = StorageManager.shared.audioFilePath(for: book.id)
        loadFromLocalFile(localUrl, book: book, startPosition: startPosition)
    } else {
        loadFromStreamingUrl(audioUrl, book: book, startPosition: startPosition)
    }
}

private func loadFromLocalFile(_ fileUrl: URL, book: Book, startPosition: Double) {
    // Use file:// URL for AVPlayer
    let playerItem = AVPlayerItem(url: fileUrl)
    // ... rest of playback setup
}

private func loadFromStreamingUrl(_ urlString: String, book: Book, startPosition: Double) {
    // Existing streaming logic
}

// Add property to track playback source
@Published var isPlayingOffline: Bool = false
```

---

### Task 4: Book Detail UI Enhancement

**File**: `ios/BookVault/Views/Books/BookDetailView.swift` (modify existing)

**Changes**:

- Add download button to metadata section
- Show download status (not downloaded, downloading, downloaded)
- Display file size before download
- Show download progress during download

**UI Addition**:

```swift
// In metadata section, after other buttons
VStack(spacing: 12) {
    // Existing buttons (Play, Continue Listening, etc.)

    // NEW: Download button
    if let downloadStatus = viewModel.downloadStatus {
        switch downloadStatus {
        case .notDownloaded(let fileSize):
            Button {
                Task {
                    await viewModel.startDownload()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Download (\(formatFileSize(fileSize)))")
                }
            }
            .buttonStyle(.bordered)

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))% downloaded")
                    .font(.caption)
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .font(.caption)
            }

        case .downloaded(let size):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Downloaded (\(formatFileSize(size)))")
                Button {
                    viewModel.deleteDownload()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
```

---

### Task 5: Downloads Management Screen

**File**: `ios/BookVault/Views/Downloads/DownloadsView.swift` (new)

**Purpose**: Central location to manage all downloaded books

**Features**:

- List of downloaded books
- Total storage used
- Delete individual downloads
- Delete all downloads
- Download history
- Storage settings

**UI Structure**:

```swift
struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var storageManager = StorageManager.shared

    var body: some View {
        NavigationView {
            List {
                // Storage summary section
                Section("Storage") {
                    HStack {
                        Text("Total Downloads")
                        Spacer()
                        Text(formatFileSize(storageManager.totalSize))
                    }
                    HStack {
                        Text("Available Space")
                        Spacer()
                        Text(formatFileSize(storageManager.availableSpace))
                    }
                }

                // Active downloads
                if !downloadManager.activeDownloads.isEmpty {
                    Section("Downloading") {
                        ForEach(downloadManager.activeDownloads.values) { download in
                            DownloadProgressRow(download: download)
                        }
                    }
                }

                // Downloaded books
                Section("Downloaded Books") {
                    ForEach(storageManager.downloads) { download in
                        DownloadedBookRow(download: download)
                            .swipeActions {
                                Button(role: .destructive) {
                                    deleteDownload(download.bookId)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }

                // Settings
                Section("Settings") {
                    NavigationLink("Download Settings") {
                        DownloadSettingsView()
                    }
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                if !storageManager.downloads.isEmpty {
                    Button("Delete All") {
                        showDeleteAllConfirmation = true
                    }
                }
            }
        }
    }
}
```

---

### Task 6: Download Settings View

**File**: `ios/BookVault/Views/Downloads/DownloadSettingsView.swift` (new)

**Settings**:

- Download quality (if multiple formats available in future)
- Storage limit
- WiFi-only downloads toggle
- Auto-delete old downloads toggle

**UI**:

```swift
struct DownloadSettingsView: View {
    @AppStorage("downloadOnlyOnWiFi") private var wifiOnly = true
    @AppStorage("downloadStorageLimit") private var storageLimit = 5_000_000_000 // 5 GB
    @AppStorage("autoDeleteOldDownloads") private var autoDelete = false

    var body: some View {
        Form {
            Section("Network") {
                Toggle("Download only on WiFi", isOn: $wifiOnly)
            }

            Section("Storage") {
                Picker("Storage Limit", selection: $storageLimit) {
                    Text("1 GB").tag(1_000_000_000)
                    Text("5 GB").tag(5_000_000_000)
                    Text("10 GB").tag(10_000_000_000)
                    Text("Unlimited").tag(Int.max)
                }

                Toggle("Auto-delete old downloads", isOn: $autoDelete)
                    .disabled(!autoDelete)

                if autoDelete {
                    Text("Downloads not played in 30 days will be deleted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Download Settings")
    }
}
```

---

### Task 7: Add Downloads Tab

**File**: `ios/BookVault/ContentView.swift` (modify existing)

**Changes**:

- Add Downloads tab to main TabView
- Badge showing number of active downloads

**UI Addition**:

```swift
TabView(selection: $selectedTab) {
    // Existing tabs: Library, Browse, Search

    // NEW: Downloads tab
    DownloadsView()
        .tabItem {
            Label("Downloads", systemImage: "arrow.down.circle")
        }
        .badge(downloadManager.activeDownloads.count)
        .tag(Tab.downloads)
}
```

---

### Task 8: Network Reachability Monitor

**File**: `ios/BookVault/Services/NetworkMonitor.swift` (new)

**Purpose**: Detect WiFi vs cellular connection for WiFi-only downloads

**Implementation**:

```swift
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = false
    @Published var isExpensive = false // Cellular
    @Published var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()

    enum ConnectionType {
        case wifi, cellular, ethernet, unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.connectionType = self?.getConnectionType(path) ?? .unknown
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }

    private func getConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }
        return .unknown
    }

    func canDownload() -> Bool {
        guard isConnected else { return false }

        let wifiOnly = UserDefaults.standard.bool(forKey: "downloadOnlyOnWiFi")
        if wifiOnly {
            return connectionType == .wifi
        }
        return true
    }
}
```

---

## Error Handling

### Download Failures

**Common Errors**:

1. Network interruption during download
2. Insufficient storage space
3. Rate limit exceeded (10/day)
4. Pre-signed URL expired (1 hour)
5. File corruption

**Handling Strategy**:

```swift
enum DownloadError: LocalizedError {
    case networkError
    case insufficientStorage
    case rateLimitExceeded(remainingTime: TimeInterval)
    case urlExpired
    case fileCorruption
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection lost. Download paused."
        case .insufficientStorage:
            return "Not enough storage space. Free up space and try again."
        case .rateLimitExceeded(let time):
            return "Daily download limit reached. Try again in \(formatTime(time))."
        case .urlExpired:
            return "Download URL expired. Retrying..."
        case .fileCorruption:
            return "Downloaded file is corrupted. Please try again."
        case .unauthorized:
            return "You don't have permission to download this book."
        }
    }
}

// Automatic retry logic
func handleDownloadFailure(bookId: String, error: Error) {
    if case DownloadError.urlExpired = error {
        // Auto-retry with fresh URL
        Task {
            try await startDownload(bookId: bookId)
        }
    } else {
        // Show error to user, allow manual retry
        showError(error)
    }
}
```

---

## Testing Checklist

### Unit Tests

- [ ] StorageManager file operations
- [ ] Metadata index serialization/deserialization
- [ ] Storage limit calculations
- [ ] DownloadManager progress tracking
- [ ] Network monitor connection detection

### Integration Tests

- [ ] Download → Save → Playback flow
- [ ] Download cancellation
- [ ] Parallel downloads (queue management)
- [ ] Storage limit enforcement
- [ ] Rate limit handling

### Manual Testing

- [ ] Download a book on WiFi
- [ ] Download a book on cellular (with WiFi-only disabled)
- [ ] Play downloaded book offline (airplane mode)
- [ ] Delete a downloaded book
- [ ] Delete all downloads
- [ ] Cancel download in progress
- [ ] App killed during download (background resumption)
- [ ] Storage limit reached scenario
- [ ] Rate limit exceeded scenario
- [ ] Switching between streaming and offline playback
- [ ] Download progress accurate (file size matches)
- [ ] VoiceOver accessibility for download controls

### Edge Cases

- [ ] Multiple books downloading simultaneously
- [ ] Download with poor network (frequent interruptions)
- [ ] Device runs out of storage mid-download
- [ ] Pre-signed URL expires during download
- [ ] Book deleted from backend while downloaded locally
- [ ] File corruption detection and handling
- [ ] App update preserves downloads

---

## Performance Considerations

### Storage Optimization

- Compress cover images (JPEG at 80% quality)
- Don't download cover if already cached
- Implement LRU cache eviction if storage limit hit
- Monitor and log storage usage patterns

### Network Optimization

- Resume partial downloads (use URLSession resumeData)
- Download in chunks (handle interruptions gracefully)
- Throttle parallel downloads (max 2 concurrent)
- Prefetch next book in series (optional future feature)

### Battery Optimization

- Defer downloads until device charging (if user preference)
- Use background URLSession (system manages power)
- Pause downloads during active playback (optional)

---

## Migration Strategy

**Existing Users**: If Phase 7 ships post-launch, ensure:

1. No breaking changes to existing playback
2. Downloads are opt-in feature
3. Settings screen explains storage usage
4. Graceful degradation if download fails

**Future Considerations**:

- Multiple audio quality options (high/medium/low)
- Smart downloads (auto-download next in series)
- Sync downloads across devices (CloudKit)
- Download chapters individually (for very long books)

---

## Success Metrics

**Must Have**:

- [ ] Users can download books for offline playback
- [ ] Background downloads work reliably
- [ ] Storage management prevents device storage issues
- [ ] Offline playback works without network
- [ ] Downloaded books sync progress like streaming books

**Nice to Have**:

- [ ] Download queue persists across app restarts
- [ ] Smart retry logic for failed downloads
- [ ] Download analytics (completion rate, storage usage)
- [ ] Recommendations based on download history

---

## API Usage Reference

### Generate Download URL

```swift
// POST /api/downloads/{bookId}
let response = try await apiClient.generateDownloadUrl(bookId: bookId)
// Returns: { downloadUrl, expiresAt, fileSize }
```

### Check Download Eligibility

```swift
// GET /api/downloads/{bookId}/check
let eligibility = try await apiClient.checkDownloadEligibility(bookId: bookId)
// Returns: { eligible: true, remainingQuota: 7 }
```

### Get Download History

```swift
// GET /api/downloads
let history = try await apiClient.getDownloadHistory()
// Returns: { downloads: [...], dailyCount: 3 }
```

---

## Implementation Order

**Recommended sequence**:

1. **Week 1**: Core Services
   - StorageManager (file operations, metadata)
   - NetworkMonitor (WiFi detection)
   - DownloadManager skeleton (no UI yet)

2. **Week 2**: Download Infrastructure
   - DownloadManager full implementation
   - URLSession background downloads
   - Error handling and retry logic

3. **Week 3**: UI Integration
   - Book Detail download button
   - DownloadsView management screen
   - Download progress indicators
   - Settings screen

4. **Week 4**: AudioPlayer Integration
   - Local file playback
   - Auto-source selection
   - Offline mode indicator

5. **Week 5**: Testing & Polish
   - Unit tests
   - Integration tests
   - Manual testing all scenarios
   - Bug fixes and edge cases

**Total Estimate**: 4-5 weeks (optional, can defer post-launch)

---

## Next Steps

1. Review this plan with stakeholders
2. Decide if Phase 7 ships with v1.0 or post-launch
3. If proceeding: Start with StorageManager implementation
4. If deferring: Archive this plan for future sprint

**Questions? See**: [docs/mobile/implementation-phases.md](../implementation-phases.md) for overall phase dependencies.
