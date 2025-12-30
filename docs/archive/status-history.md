# Status History

**Purpose**: Historical record of completed work. For current status, see [STATUS.md](../STATUS.md).

---

## iOS Development Timeline (December 2025)

### Phase 8: Offline Mode Support (Dec 29)

- LibraryCacheManager service persists library to disk
- OfflineProgressStore for local progress storage
- SyncManager for automatic background sync
- Network-aware UI (dynamic tab visibility)

### Phase 7: Offline Downloads (Dec 29)

- Background downloads with progress tracking
- Local storage management
- Download queue and settings

### Phase 6: Search & Browse (Dec 28)

- SearchManager with caching (5-min TTL)
- Browse by Author, Series, Narrator, Category
- Alphabetical section headers
- Pull-to-refresh on all views

### Phase 5: Chapter Navigation (Dec 28)

- ChapterManager service
- ChapterListView with current chapter highlighting
- Skip to chapter functionality

### Phase 4: Progress Sync (Dec 28)

- Auto-save every 10 seconds
- Cross-platform sync (iOS ↔ web)
- Continue Listening carousel

### Phase 3/3.5: Background Audio + Mini Player (Dec 27)

- Lock screen controls
- MPNowPlayingInfoCenter integration
- Persistent mini player bar

### Phases 1-2: Auth & Playback (Dec 26-27)

- JWT authentication
- AVPlayer streaming
- Basic playback controls

---

## Backend/API Work (December 2025)

### Entity Detail Endpoints DRY Refactor (Dec 28)

- Created `handleEntityDetailWithBooks()` helper
- Reduced 4 endpoints from ~80 lines each to ~17 lines
- Added 21 unit tests

### Dual Authentication (Dec 26)

- All endpoints support session cookies (web) + JWT Bearer tokens (mobile)
- Backward compatible

### OpenAPI Drift Prevention (Dec 26)

- CI validates spec, checks stale types, runs contract tests
- Pre-commit hooks auto-regenerate types

---

## Web App Work (December 2025)

### PR #12: Media Session API (Dec 23)

- Lock screen controls for mobile web
- HTTPS development server

### PR #11: Progress Tracking (Dec 23)

- Auto-save positions
- Continue listening carousel

### PR #7-8: Playback & Dark Mode (Dec 23)

- Chapter navigation
- Theme toggle with persistence
