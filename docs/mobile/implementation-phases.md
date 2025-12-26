# iOS Implementation Phases

**Last Updated**: December 25, 2025

> **TL;DR**: 8 phased rollout with clear acceptance criteria and stop points for each phase.

---

## Phase 1: Authentication & Browsing

**Objective**: Users can log in and browse their audiobook library

**Key Tasks**:

- Swift project setup with SwiftUI
- API client with URLSession (JWT token management)
- Login screen with credential validation
- Home screen with book grid (fetch from `/api/books`)
- Book detail screen with metadata
- Navigation structure (TabView + NavigationStack)

**Acceptance Criteria**:

- User can log in with existing web credentials
- User can browse books with cover images
- User can view book details (title, author, narrator, description)
- App handles network errors gracefully

**Stop Point**: Commit code, test on device, clear context

---

## Phase 2: Audio Playback (Basic)

**Objective**: Users can stream and play audiobooks

**Key Tasks**:

- AVPlayer integration with remote URL streaming
- Playback controls (play, pause, seek)
- Playback speed control (0.5x - 2.5x)
- Volume control
- Now Playing screen UI
- Progress bar with time display

**Acceptance Criteria**:

- User can start playback from book detail
- User can control playback (play/pause/seek)
- User can adjust playback speed
- Audio streams without buffering issues
- Playback position updates in real-time

**Stop Point**: Test audio streaming, verify seek performance

---

## Phase 3: Background Audio & Lock Screen

**Objective**: Audio continues when app is backgrounded

**Key Tasks**:

- Background audio mode configuration (Info.plist)
- AVAudioSession setup for background playback
- Lock screen controls (MPNowPlayingInfoCenter)
- Remote command center (play/pause/skip from lock screen)
- Interruption handling (phone calls, alarms)
- Route change handling (headphones disconnect)

**Acceptance Criteria**:

- Audio continues when screen locks
- Lock screen shows cover art, title, author
- Lock screen controls work (play, pause, skip)
- Audio pauses on interruption, resumes after
- Audio handles headphone disconnect properly

**Stop Point**: Test background audio, verify interruption handling

---

## Phase 4: Progress Sync

**Objective**: Playback position syncs with backend

**Key Tasks**:

- Integrate with `/api/progress` endpoints
- Auto-save position every 10 seconds
- Load saved position on playback start
- Mark book as completed when finished
- Continue listening section on home screen
- Progress indicators on book cards

**Acceptance Criteria**:

- Position saves automatically during playback
- Position resumes correctly on app restart
- Books marked as completed sync to backend
- Continue listening section shows recent books
- Progress syncs between web and mobile

**Stop Point**: Test sync behavior, verify cross-platform consistency

---

## Phase 5: Chapter Navigation

**Objective**: Users can navigate by chapter

**Key Tasks**:

- Fetch chapters from `/api/books/:id/chapters`
- Chapter list UI in Now Playing screen
- Skip to chapter functionality
- Current chapter highlighting
- Chapter metadata display (title, duration)

**Acceptance Criteria**:

- User can view chapter list
- User can skip to any chapter
- Current chapter is highlighted during playback
- Chapter transitions are smooth

**Stop Point**: Test chapter navigation, verify timing accuracy

---

## Phase 6: Search & Browse

**Objective**: Users can search and browse by author/series/narrator

**Key Tasks**:

- Search screen with `/api/search` integration
- Browse by authors (`/api/browse/authors`)
- Browse by series (`/api/browse/series`)
- Browse by narrators (`/api/browse/narrators`)
- Browse by categories (`/api/browse/categories`)
- Author/Series/Narrator detail screens

**Acceptance Criteria**:

- User can search across books, authors, narrators
- User can browse by author/series/narrator/category
- Search results are relevant and fast
- Detail screens show all related books

**Stop Point**: Test search performance, verify filtering

---

## Phase 7: User Lists

**Objective**: Users can create and manage custom lists

**Key Tasks**:

- My Library screen (show user's added books)
- Add/remove books from library
- Custom lists UI (Want to Listen, Favorites)
- Create/edit/delete lists
- Drag-to-reorder books in lists
- Sync with `/api/library/*` endpoints

**Acceptance Criteria**:

- User can add/remove books from library
- User can create custom lists
- User can reorder books in lists
- Lists sync between web and mobile

**Stop Point**: Test list management, verify sync

---

## Phase 8: Offline Downloads (Optional)

**Objective**: Users can download books for offline listening

**Key Tasks**:

- Download manager (URLSession background downloads)
- Local storage management (file system)
- Download progress UI
- Offline playback mode (local files)
- Storage limit management
- Delete downloaded books

**Acceptance Criteria**:

- User can download books for offline use
- Downloads work in background
- Offline playback works without network
- Storage usage is visible and manageable

**Stop Point**: Test offline mode, verify storage limits

---

## Phase Dependencies

```
Phase 1 (Auth & Browse)
    ↓
Phase 2 (Basic Playback)
    ↓
Phase 3 (Background Audio)  ← Must complete before Phase 4
    ↓
Phase 4 (Progress Sync)
    ↓
Phase 5 (Chapters)  ← Independent of Phase 6/7
    ↓
Phase 6 (Search)    ← Independent of Phase 7
    ↓
Phase 7 (Lists)
    ↓
Phase 8 (Offline)   ← Optional, can be deferred
```

**Critical Path**: Phases 1-4 must be completed in order
**Parallel Work**: Phases 5-7 can be developed independently after Phase 4
**Optional**: Phase 8 can be added post-launch

---

## Testing Checklist (Per Phase)

**Manual Testing**:

- [ ] Test on real device (not just Simulator)
- [ ] Test with poor network conditions
- [ ] Test edge cases (empty states, errors)
- [ ] Test with different iOS versions (16+)
- [ ] Test accessibility (VoiceOver, Dynamic Type)

**Code Quality**:

- [ ] Unit tests written for new services
- [ ] SwiftUI previews working
- [ ] No compiler warnings
- [ ] Code follows Swift style guide
- [ ] Memory leaks checked with Instruments

**Documentation**:

- [ ] Update CHANGELOG.md with changes
- [ ] Update API integration docs if endpoints changed
- [ ] Add code comments for complex logic
- [ ] Update README with new features
