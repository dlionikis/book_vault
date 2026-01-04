# Background Downloads Implementation Plan

**Created**: January 4, 2026
**Status**: Ready for Implementation
**Priority**: Post-launch enhancement

> **TL;DR**: Convert DownloadManager from foreground-only URLSession to background URLSession, enabling downloads to continue when the app is backgrounded or terminated. Implementation split into 4 independent phases.

---

## Problem Statement

Currently, audiobook downloads use `URLSessionConfiguration.default` (foreground session), which means:

- Downloads cancel when navigating away from BookDetailView
- Downloads cancel when app is backgrounded
- Downloads cancel when app is terminated
- Large audiobooks (100MB-1GB+) require users to keep the app open

This creates a poor user experience, especially on slow connections.

---

## Solution: Background URLSession

Apple's `URLSessionConfiguration.background(withIdentifier:)` hands downloads off to the system daemon (`nsurlsessiond`), which:

- Continues downloads when app is backgrounded
- Continues downloads when app is terminated
- Automatically handles network changes and retries
- Relaunches the app when downloads complete

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Current Architecture (Foreground)                              │
├─────────────────────────────────────────────────────────────────┤
│  BookDetailView → DownloadManager → URLSession.default          │
│                                           ↓                     │
│                               Download runs in-process          │
│                               (cancelled on background)         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  New Architecture (Background)                                  │
├─────────────────────────────────────────────────────────────────┤
│  BookDetailView → DownloadManager → URLSession.background       │
│                          ↓                    ↓                 │
│                   AppDelegate ←───── nsurlsessiond (daemon)     │
│                          ↓                                      │
│              handleEventsForBackgroundURLSession                │
│                          ↓                                      │
│              Reconnect session, process completions             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: AppDelegate Setup & Session Configuration

**Goal**: Add AppDelegate to SwiftUI app and configure background URLSession

**Files to Modify**:

- `ios/BookVault/BookVaultApp.swift`
- `ios/BookVault/Services/DownloadManager.swift`

**Files to Create**:

- `ios/BookVault/AppDelegate.swift`

**Changes**:

1. **Create AppDelegate.swift**:

```swift
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Store completion handler for later
        DownloadManager.shared.handleBackgroundSessionEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}
```

2. **Update BookVaultApp.swift**:

```swift
@main
struct BookVaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ... rest unchanged
}
```

3. **Update DownloadManager.setupDownloadSession()**:

```swift
private func setupDownloadSession() {
    let config = URLSessionConfiguration.background(
        withIdentifier: sessionIdentifier
    )
    config.isDiscretionary = false  // Start immediately, don't defer
    config.sessionSendsLaunchEvents = true  // Relaunch app on completion
    config.allowsCellularAccess = true  // WiFi-only checked separately
    config.timeoutIntervalForResource = 3600
    config.waitsForConnectivity = true

    downloadSession = URLSession(
        configuration: config,
        delegate: self,
        delegateQueue: nil
    )
}
```

4. **Add background completion handler storage to DownloadManager**:

```swift
private var backgroundCompletionHandler: (() -> Void)?

func handleBackgroundSessionEvents(
    identifier: String,
    completionHandler: @escaping () -> Void
) {
    guard identifier == sessionIdentifier else {
        completionHandler()
        return
    }
    backgroundCompletionHandler = completionHandler
    // Recreate session if needed (reconnects to daemon)
    _ = downloadSession
}
```

5. **Implement urlSessionDidFinishEvents**:

```swift
nonisolated func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
) {
    Task { @MainActor in
        self.backgroundCompletionHandler?()
        self.backgroundCompletionHandler = nil
    }
}
```

**Verification**:

- [ ] App builds without errors
- [ ] Existing foreground downloads still work
- [ ] Download starts and completes when app stays in foreground
- [ ] No crashes on app launch

**Estimated Changes**: ~80 lines added/modified

---

### Phase 2: Background Download Continuity

**Goal**: Downloads continue when app is backgrounded or terminated

**Files to Modify**:

- `ios/BookVault/Services/DownloadManager.swift`

**Changes**:

1. **Persist pending downloads for session reconnection**:

```swift
private let pendingDownloadsKey = "com.bookvault.pendingDownloads"

// Save pending download info when starting
private func savePendingDownloadInfo(bookId: String, book: Book) {
    var pending = loadPendingDownloadInfo()
    pending[bookId] = PendingDownloadInfo(
        bookId: bookId,
        bookTitle: book.title,
        bookAuthor: book.author,
        totalBytes: 0,
        startedAt: Date()
    )
    savePendingDownloadInfo(pending)
}

// Load on app launch to restore UI state
func restorePendingDownloads() {
    let pending = loadPendingDownloadInfo()
    for (bookId, info) in pending {
        // Create placeholder ActiveDownload for UI
        activeDownloads[bookId] = ActiveDownload(
            id: bookId,
            book: Book.placeholder(id: bookId, title: info.bookTitle),
            bytesDownloaded: 0,
            totalBytes: info.totalBytes,
            state: .downloading(progress: 0),
            task: nil
        )
    }

    // Query session for actual task status
    downloadSession.getAllTasks { tasks in
        Task { @MainActor in
            self.reconcileTasksWithPendingDownloads(tasks)
        }
    }
}
```

2. **Add PendingDownloadInfo struct** (Codable for UserDefaults):

```swift
struct PendingDownloadInfo: Codable {
    let bookId: String
    let bookTitle: String
    let bookAuthor: String
    var totalBytes: Int64
    let startedAt: Date
}
```

3. **Handle session reconnection on app launch**:

```swift
init(...) {
    // ... existing init code ...

    // Restore any in-progress downloads from previous session
    Task { @MainActor in
        self.restorePendingDownloads()
    }
}
```

4. **Clean up pending info on completion/cancellation**:

```swift
private func handleDownloadComplete(bookId: String, savedPath: URL) async {
    // ... existing code ...
    removePendingDownloadInfo(bookId: bookId)
}

func cancelDownload(bookId: String) {
    // ... existing code ...
    removePendingDownloadInfo(bookId: bookId)
}
```

**Verification**:

- [ ] Start download, background app, wait 30+ seconds
- [ ] Return to app - download should have progressed or completed
- [ ] Start download, force-quit app (swipe up)
- [ ] Relaunch app - UI should cleanly show no active downloads (force-quit cancels all tasks per iOS design)
- [ ] Check DownloadsView shows correct state after relaunch

**Estimated Changes**: ~120 lines added/modified

---

### Phase 3: Progress Tracking & UI Updates

**Goal**: UI correctly reflects download state across app lifecycle

**Files to Modify**:

- `ios/BookVault/Services/DownloadManager.swift`
- `ios/BookVault/Views/Books/BookDetailView.swift` (DownloadButton)
- `ios/BookVault/Views/Downloads/DownloadsView.swift`

**Changes**:

1. **Store last known progress in UserDefaults**:

```swift
private func updateProgress(bookId: String, bytesWritten: Int64, totalBytes: Int64) {
    // ... existing code ...

    // Persist progress for UI restoration
    updatePendingDownloadProgress(bookId: bookId, bytesWritten: bytesWritten, totalBytes: totalBytes)
}
```

2. **Add "background in progress" UI state**:

```swift
enum DownloadState: Equatable {
    case notDownloaded
    case waiting
    case downloading(progress: Double)
    case backgroundDownloading(lastProgress: Double)  // NEW: App was backgrounded
    case paused(progress: Double)
    case completed
    case failed(error: String)
}
```

3. **Update DownloadButton to show background state**:

```swift
case let .backgroundDownloading(lastProgress):
    VStack(spacing: 4) {
        ProgressView(value: lastProgress)
            .progressViewStyle(.linear)
        Text("Downloading in background...")
            .font(.caption)
            .foregroundColor(.secondary)
        Text("\(Int(lastProgress * 100))% when last checked")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
```

4. **Query background session tasks on foreground return**:

```swift
// In DownloadManager or via NotificationCenter
func applicationWillEnterForeground() {
    downloadSession.getAllTasks { tasks in
        Task { @MainActor in
            self.updateUIFromBackgroundTasks(tasks)
        }
    }
}
```

5. **Register for app lifecycle notifications**:

```swift
private func setupNotifications() {
    NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.applicationWillEnterForeground()
    }
}
```

**Verification**:

- [ ] Start download, see progress bar updating
- [ ] Background app, wait 10 seconds, return
- [ ] Progress bar should show updated progress (or completion)
- [ ] "Downloading in background" message shows when appropriate
- [ ] DownloadsView reflects accurate state

**Estimated Changes**: ~100 lines added/modified

---

### Phase 4: Testing & Edge Cases

**Goal**: Comprehensive testing and edge case handling

**Files to Modify**:

- `ios/BookVault/Services/DownloadManager.swift`
- `ios/BookVaultTests/Services/DownloadManagerTests.swift`

**Files to Create**:

- `ios/BookVaultTests/Services/BackgroundDownloadTests.swift`

**Changes**:

1. **Handle edge cases**:

```swift
// Network change during background download
nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
) {
    // ... existing code ...

    // Check for resumable errors
    if let nsError = error as NSError?,
       nsError.code == NSURLErrorNetworkConnectionLost,
       let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
        Task { @MainActor in
            self.handleResumableError(bookId: bookId, resumeData: resumeData)
        }
        return
    }
}

private func handleResumableError(bookId: String, resumeData: Data) {
    // Store resume data for retry
    saveResumeData(bookId: bookId, data: resumeData)
    activeDownloads[bookId]?.state = .paused(progress: activeDownloads[bookId]?.progress ?? 0)
}
```

2. **Add retry with resume data**:

```swift
func retryDownload(bookId: String) async throws {
    if let resumeData = loadResumeData(bookId: bookId) {
        let task = downloadSession.downloadTask(withResumeData: resumeData)
        task.taskDescription = bookId
        downloadTasks[bookId] = task
        task.resume()
        clearResumeData(bookId: bookId)
    } else if let book = pendingBooks[bookId] {
        try await startDownload(book: book)
    }
}
```

3. **Handle multiple downloads completing while backgrounded**:

```swift
nonisolated func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
) {
    // This is called AFTER all downloads complete
    // Safe to call completion handler now
    Task { @MainActor in
        // Process any queued completions
        self.processQueuedCompletions()

        // Tell iOS we're done updating UI
        self.backgroundCompletionHandler?()
        self.backgroundCompletionHandler = nil
    }
}
```

4. **Add unit tests for background scenarios**:

```swift
// BackgroundDownloadTests.swift

func testSessionIdentifierIsUnique() async {
    // Verify identifier follows Apple guidelines
    XCTAssertTrue(manager.sessionIdentifier.contains("com.bookvault"))
}

func testPendingDownloadsPersistence() async {
    // Start download, save pending info
    // Create new manager instance
    // Verify pending downloads restored
}

func testResumeDataHandling() async {
    // Simulate network error with resume data
    // Verify resume data saved
    // Retry and verify resume data used
}

func testBackgroundCompletionHandlerCalled() async {
    // Simulate background completion
    // Verify handler called exactly once
}
```

5. **Update existing tests for background session**:

```swift
// Mock background session for tests
let testConfig = URLSessionConfiguration.ephemeral  // Not background for tests
let testSession = URLSession(configuration: testConfig, delegate: nil, delegateQueue: nil)
let manager = DownloadManager(
    apiClient: mockAPI,
    storageManager: mockStorage,
    networkMonitor: mockNetwork,
    session: testSession  // Use test session, not background
)
```

**Verification**:

- [ ] All existing tests pass
- [ ] New background-specific tests pass
- [ ] Download survives app backgrounding (home button, switch apps)
- [ ] Download survives system-initiated termination (memory pressure)
- [ ] Force-quit cancels downloads and UI cleans up on relaunch (expected iOS behavior)
- [ ] Download survives network change (WiFi → cellular)
- [ ] Multiple concurrent downloads complete correctly
- [ ] Resume data works after network failure
- [ ] No memory leaks (profile with Instruments)

**Estimated Changes**: ~200 lines added/modified

---

## Summary

| Phase     | Description                  | Files  | Lines    |
| --------- | ---------------------------- | ------ | -------- |
| 1         | AppDelegate + Session Config | 3      | ~80      |
| 2         | Background Continuity        | 1      | ~120     |
| 3         | Progress Tracking & UI       | 3      | ~100     |
| 4         | Testing & Edge Cases         | 3      | ~200     |
| **Total** |                              | **10** | **~500** |

---

## Context for Each Phase

When starting a new session for any phase, provide this context:

### Phase 1 Context

```
We're implementing background downloads for the BookVault iOS app.

Current state: Downloads use URLSessionConfiguration.default (foreground-only)
and cancel when the app is backgrounded.

This phase: Add AppDelegate with handleEventsForBackgroundURLSession and convert
DownloadManager to use URLSessionConfiguration.background.

Key files:
- ios/BookVault/BookVaultApp.swift (add @UIApplicationDelegateAdaptor)
- ios/BookVault/AppDelegate.swift (create new)
- ios/BookVault/Services/DownloadManager.swift (change session config)

See docs/roadmap/background-downloads.md Phase 1 for detailed implementation.
```

### Phase 2 Context

```
We're implementing background downloads for the BookVault iOS app.

Phase 1 is complete: AppDelegate and background URLSession are configured.

This phase: Persist pending download info so downloads survive app termination
and UI can be restored on relaunch.

Key files:
- ios/BookVault/Services/DownloadManager.swift

See docs/roadmap/background-downloads.md Phase 2 for detailed implementation.
```

### Phase 3 Context

```
We're implementing background downloads for the BookVault iOS app.

Phases 1-2 complete: Background session configured, downloads persist.

This phase: Update UI to show correct state when app returns to foreground,
add "backgroundDownloading" state, register for lifecycle notifications.

Key files:
- ios/BookVault/Services/DownloadManager.swift
- ios/BookVault/Views/Books/BookDetailView.swift (DownloadButton)
- ios/BookVault/Views/Downloads/DownloadsView.swift

See docs/roadmap/background-downloads.md Phase 3 for detailed implementation.
```

### Phase 4 Context

```
We're implementing background downloads for the BookVault iOS app.

Phases 1-3 complete: Background downloads work, UI updates correctly.

This phase: Handle edge cases (resume data, network changes), add comprehensive
tests for background download scenarios.

Key files:
- ios/BookVault/Services/DownloadManager.swift
- ios/BookVaultTests/Services/DownloadManagerTests.swift
- ios/BookVaultTests/Services/BackgroundDownloadTests.swift (create new)

See docs/roadmap/background-downloads.md Phase 4 for detailed implementation.
```

---

## Testing Checklist (Real Device Required)

Background sessions don't work reliably in the simulator. Test on a real device:

- [ ] **Basic**: Start download → stays in foreground → completes
- [ ] **Background**: Start download → background app → return → download progressed/completed
- [ ] **Termination**: Start download → force quit app → relaunch → download completed
- [ ] **Network loss**: Start download → airplane mode → restore network → download resumes
- [ ] **Multiple**: Start 3 downloads → background app → all complete
- [ ] **Cancel**: Start download → cancel → no zombie tasks
- [ ] **Storage**: Start download → insufficient space → appropriate error

---

## Rollback Plan

If issues arise, revert to foreground session:

```swift
// In setupDownloadSession()
let config = URLSessionConfiguration.default  // Revert from .background
```

The foreground implementation will continue to work; users just won't have background download support.

---

## References

- [Apple: Downloading Files in the Background](https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background)
- [SwiftLee: URLSession Background Pitfalls](https://www.avanderlee.com/swift/urlsession-common-pitfalls-with-background-download-upload-tasks/)
- [William Boles: Keep Downloading with Background Session](https://williamboles.com/keep-downloading-with-a-background-session/)
