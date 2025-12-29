# Phase 8: Offline Mode Support - Implementation Plan

## Overview

Add comprehensive offline support so users can browse their cached library, play downloaded audiobooks, and have playback progress synced when back online.

## Current State Analysis

### Existing Infrastructure

- **NetworkMonitor**: Already tracks `isConnected`, `connectionType`, `isExpensive`
- **StorageManager**: Persists download metadata to `~/Documents/downloads/metadata.json`
- **LibraryManager**: Has in-memory cache (5 min TTL) but no disk persistence
- **ProgressManager**: No caching - always hits API, fails when offline

### Gap Analysis

1. Library books not cached to disk - can't view library offline
2. Playback progress not saved locally - lost if offline
3. No progress sync queue for when connectivity returns
4. UI doesn't adapt to offline state - shows errors instead of cached content
5. All tabs visible offline (Catalog/Browse/Search don't work without network)

---

## Implementation Plan

### Step 1: LibraryCacheManager (New Service)

**File**: `ios/BookVault/Services/LibraryCacheManager.swift`

**Purpose**: Persist user's library books to disk for offline access

**Storage Location**: `~/Documents/cache/library.json`

**Data Structure**:

```swift
struct LibraryCache: Codable {
    var version: Int = 1
    var books: [Book]
    var lastSyncDate: Date
    var userId: String  // Tied to user to avoid cross-account issues
}
```

**Key Methods**:

- `saveLibrary(books: [Book])` - Write to disk after API fetch
- `loadLibrary() -> [Book]?` - Read from disk
- `clearCache()` - Called on logout
- `isCacheValid() -> Bool` - Check if cache exists for current user

**Integration Points**:

- LibraryManager calls `saveLibrary()` after successful API fetch
- LibraryManager calls `loadLibrary()` when offline
- AuthManager calls `clearCache()` on logout

---

### Step 2: OfflineProgressStore (New Service)

**File**: `ios/BookVault/Services/OfflineProgressStore.swift`

**Purpose**: Save playback progress locally with sync queue

**Storage Location**: `~/Documents/cache/progress.json`

**Data Structure**:

```swift
struct LocalProgress: Codable {
    let bookId: String
    var positionSeconds: Double
    var completed: Bool
    var lastPlayed: Date
    var needsSync: Bool  // True if not yet synced to server
}

struct ProgressCache: Codable {
    var version: Int = 1
    var progress: [String: LocalProgress]  // bookId -> progress
    var userId: String
}
```

**Key Methods**:

- `saveProgress(bookId: String, position: Double)` - Save locally immediately
- `getProgress(bookId: String) -> LocalProgress?` - Read local progress
- `getPendingSync() -> [LocalProgress]` - Get all unsynced entries
- `markSynced(bookId: String)` - Called after successful API sync
- `clearCache()` - Called on logout

**Sync Strategy**: Latest timestamp wins

- When syncing, compare local `lastPlayed` with server `lastPlayed`
- Push local if newer, pull server if newer

---

### Step 3: Update NetworkMonitor

**File**: `ios/BookVault/Services/NetworkMonitor.swift`

**Changes**:

- Add `@Published var isOnline: Bool` (alias for clarity)
- The existing `isConnected` already works, but `isOnline` is more semantic

**Minimal change** - just add computed property:

```swift
var isOnline: Bool { isConnected }
```

---

### Step 4: Update ContentView for Offline Mode

**File**: `ios/BookVault/ContentView.swift`

**Changes**:

1. Add `@StateObject private var networkMonitor = NetworkMonitor.shared`

2. Conditional tab display based on `networkMonitor.isConnected`:

**Online Mode** (6 tabs):

```
[Catalog] [Browse] [Search] [Library] [Downloads] [Settings]
```

**Offline Mode** (4 tabs):

```
[Offline] [Library] [Downloads] [Settings]
```

3. Create new `OfflineModeView` for the "Offline" tab that explains:
   - "You're offline"
   - "Your cached library and downloads are available"
   - "Connect to browse the catalog or search"

4. When switching from offline to online, restore full tab set

**Tab Enum Update**:

```swift
enum Tab {
    case catalog
    case browse
    case search
    case library
    case downloads
    case settings
    case offline  // NEW - shown only when offline
}
```

---

### Step 5: Update LibraryManager

**File**: `ios/BookVault/Services/LibraryManager.swift`

**Changes**:

1. Add dependency on `LibraryCacheManager`

2. Update `fetchLibraryBooks()`:

```swift
func fetchLibraryBooks(forceRefresh: Bool = false) async throws -> [Book] {
    // Check network
    if !NetworkMonitor.shared.isConnected {
        // Return cached data if available
        if let cached = libraryCacheManager.loadLibrary() {
            return cached
        }
        throw LibraryError.offlineNoCache
    }

    // Online: fetch from API
    let books = try await apiClient.fetchLibrary().books

    // Save to disk cache
    libraryCacheManager.saveLibrary(books: books)

    return books
}
```

3. Add new error type:

```swift
enum LibraryError: LocalizedError {
    case offlineNoCache

    var errorDescription: String? {
        switch self {
        case .offlineNoCache:
            return "You're offline and no cached library is available. Connect to the internet to load your library."
        }
    }
}
```

---

### Step 6: Update ProgressManager

**File**: `ios/BookVault/Services/ProgressManager.swift`

**Changes**:

1. Add dependency on `OfflineProgressStore`

2. Update `saveProgress()`:

```swift
func saveProgress(for bookId: String, positionSeconds: Double) async throws {
    // Always save locally first
    offlineProgressStore.saveProgress(bookId: bookId, position: positionSeconds)

    // Try to sync to server if online
    if NetworkMonitor.shared.isConnected {
        do {
            let response = try await apiClient.updateProgress(...)
            offlineProgressStore.markSynced(bookId: bookId)
        } catch {
            // Keep local, will sync later
            DebugLogger.error("Progress sync failed, will retry", error: error)
        }
    }
}
```

3. Update `fetchProgress()`:

```swift
func fetchProgress(for bookId: String) async throws -> UserProgress {
    // If online, fetch from server and merge
    if NetworkMonitor.shared.isConnected {
        let serverProgress = try await apiClient.fetchProgress(bookId: bookId)
        let localProgress = offlineProgressStore.getProgress(bookId: bookId)

        // Return whichever is newer
        if let local = localProgress,
           local.lastPlayed > serverProgress.lastPlayed {
            return UserProgress(from: local)
        }
        return serverProgress
    }

    // Offline: return local only
    if let local = offlineProgressStore.getProgress(bookId: bookId) {
        return UserProgress(from: local)
    }

    // No progress exists
    return UserProgress(positionSeconds: 0, completed: false, lastPlayed: nil)
}
```

---

### Step 7: SyncManager (New Service)

**File**: `ios/BookVault/Services/SyncManager.swift`

**Purpose**: Background sync when connectivity returns

**Key Methods**:

- `syncPendingProgress()` - Push all unsynced progress to server
- `startMonitoring()` - Observe NetworkMonitor, sync when online

**Implementation**:

```swift
@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    private var cancellables = Set<AnyCancellable>()

    func startMonitoring() {
        NetworkMonitor.shared.$isConnected
            .filter { $0 }  // Only when becomes connected
            .sink { [weak self] _ in
                Task {
                    await self?.syncPendingProgress()
                }
            }
            .store(in: &cancellables)
    }

    func syncPendingProgress() async {
        let pending = OfflineProgressStore.shared.getPendingSync()
        for progress in pending {
            do {
                try await ProgressManager.shared.saveProgress(
                    for: progress.bookId,
                    positionSeconds: progress.positionSeconds
                )
            } catch {
                DebugLogger.error("Failed to sync progress for \(progress.bookId)", error: error)
            }
        }
    }
}
```

**Initialization**: Call `SyncManager.shared.startMonitoring()` from `BookVaultApp.swift`

---

### Step 8: OfflineModeView (New View)

**File**: `ios/BookVault/Views/OfflineModeView.swift`

**Purpose**: Informational view shown in the "Offline" tab

**Content**:

- Icon: `wifi.slash`
- Title: "You're Offline"
- Message: "Catalog, Browse, and Search require an internet connection."
- Suggestions: "Your Library and Downloads are available offline."
- Optional: Button to go to Library tab

---

### Step 9: Update LibraryView for Offline State

**File**: `ios/BookVault/Views/Library/LibraryView.swift`

**Changes**:

- When loading fails due to `LibraryError.offlineNoCache`, show friendly message
- When showing cached data offline, show subtle "Cached" indicator
- Disable pull-to-refresh when offline (or show message that refresh requires connection)

---

### Step 10: Cache Cleanup on Logout

**File**: `ios/BookVault/Services/AuthManager.swift`

**Changes to `clearSession()`**:

```swift
private func clearSession() {
    // Existing keychain cleanup...

    // Clear caches tied to user
    LibraryCacheManager.shared.clearCache()
    OfflineProgressStore.shared.clearCache()
}
```

---

## File Changes Summary

| File                                  | Action     | Description                             |
| ------------------------------------- | ---------- | --------------------------------------- |
| `Services/LibraryCacheManager.swift`  | **CREATE** | Disk persistence for library books      |
| `Services/OfflineProgressStore.swift` | **CREATE** | Local progress storage with sync queue  |
| `Services/SyncManager.swift`          | **CREATE** | Background sync on connectivity return  |
| `Views/OfflineModeView.swift`         | **CREATE** | Offline tab placeholder view            |
| `ContentView.swift`                   | **MODIFY** | Conditional tabs based on network state |
| `Services/NetworkMonitor.swift`       | **MODIFY** | Add `isOnline` computed property        |
| `Services/LibraryManager.swift`       | **MODIFY** | Use cache when offline                  |
| `Services/ProgressManager.swift`      | **MODIFY** | Local-first progress with sync          |
| `Services/AuthManager.swift`          | **MODIFY** | Clear caches on logout                  |
| `Views/Library/LibraryView.swift`     | **MODIFY** | Handle offline state gracefully         |
| `BookVaultApp.swift`                  | **MODIFY** | Initialize SyncManager monitoring       |

---

## Testing Checklist

### Offline Library

- [ ] Open app online, view library → cache populated
- [ ] Go offline → library still shows cached books
- [ ] Kill app offline, relaunch → cached library loads
- [ ] Logout → cache cleared
- [ ] Login as different user → previous user's cache not shown

### Offline Progress

- [ ] Play book offline → progress saved locally
- [ ] Kill app, relaunch offline → progress restored
- [ ] Come back online → progress syncs to server
- [ ] Play on another device → sync resolves to latest

### Tab Bar Behavior

- [ ] Online → All 6 tabs visible
- [ ] Go offline → Catalog/Browse/Search replaced with Offline tab
- [ ] Come back online → Full tabs restored
- [ ] Selected tab preserved when possible

### Edge Cases

- [ ] First launch ever while offline → shows "no cache" message
- [ ] Token expires while offline → graceful handling
- [ ] Large library (100+ books) → cache performance OK

---

## Implementation Order

1. **LibraryCacheManager** - Foundation for offline library
2. **OfflineProgressStore** - Foundation for offline playback
3. **NetworkMonitor update** - Minor change
4. **ContentView tabs** - Visible user impact
5. **OfflineModeView** - New offline tab content
6. **LibraryManager integration** - Use cache when offline
7. **ProgressManager integration** - Local-first saving
8. **SyncManager** - Background sync
9. **LibraryView updates** - Polish offline UX
10. **AuthManager cleanup** - Security (clear on logout)
