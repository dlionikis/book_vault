# iOS Phase 5: Chapter Navigation - Implementation Plan

**Status**: Ready to implement
**Prerequisites**: Phase 4 (Progress Sync) complete
**Estimated Effort**: 4-6 hours
**Last Updated**: December 28, 2025

---

## Overview

Implement chapter navigation functionality in the iOS app, allowing users to:

- View a list of chapters for the current audiobook
- Skip to any chapter with a single tap
- See which chapter is currently playing
- View chapter metadata (title, start time, duration)

---

## Bug Fix: Chapter Duration Field

**Status**: ✅ Fixed (December 28, 2025)

**Issue**: Web app chapters displayed "NaN" for startTime and duration
**Root Cause**: API endpoint didn't include `duration` field in response
**Fix Applied**:

- Updated `app/api/books/[id]/chapters/route.ts` to include `duration` in all response mappings
- Updated `docs/api/openapi.yaml` to mark `duration` as required field
- Regenerated TypeScript and Swift types with `npm run api:generate`

**Files Modified**:

- `app/api/books/[id]/chapters/route.ts` (lines 54, 126, 147)
- `docs/api/openapi.yaml` (Chapter schema)
- `lib/api-types.ts` (auto-generated)
- `ios/BookVault/Generated/Models/Chapter.swift` (auto-generated)

---

## Technical Architecture

### API Endpoints

**GET /api/books/{id}/chapters**

- Returns chapter list with metadata
- Response format:
  ```json
  {
    "chapters": [
      {
        "id": "uuid",
        "title": "Chapter 1: A Place for Demons",
        "startTime": 0,
        "endTime": 1806.5,
        "duration": 1806.5,
        "index": 0
      }
    ],
    "source": "database" | "extracted" | "unavailable" | "error" | "none"
  }
  ```

### Data Models

**Chapter.swift** (auto-generated from OpenAPI):

```swift
public struct Chapter: Codable, Hashable {
    public var id: UUID
    public var title: String
    public var startTime: Double  // seconds
    public var endTime: Double    // seconds
    public var duration: Double   // seconds
    public var index: Int         // chapter number (0-based)
}
```

### Services

**ChapterManager.swift** (new file):

- Fetches chapters from API
- Caches chapters per book ID
- Handles empty chapter lists gracefully
- Thread-safe with @MainActor annotations

**AudioPlayerManager.swift** (existing, to modify):

- Add `currentChapterId` property
- Add `getCurrentChapter()` method
- Add `skipToChapter(_ chapter: Chapter)` method
- Auto-update current chapter during playback
- Emit chapter change notifications

---

## Implementation Tasks

### 1. Create ChapterManager Service

**File**: `ios/BookVault/Services/ChapterManager.swift`

**Responsibilities**:

- Fetch chapters from `/api/books/{id}/chapters`
- Cache chapters by book ID
- Handle API errors gracefully (silent failures)
- Return empty array if no chapters available

**Key Methods**:

```swift
@MainActor
class ChapterManager: ObservableObject {
    @Published var chapters: [Chapter] = []
    @Published var isLoading: Bool = false

    func fetchChapters(bookId: String) async
    func clearCache()
}
```

**Error Handling**:

- Network errors → Return empty array, don't crash
- 404 Not Found → Book has no chapters (valid state)
- Malformed JSON → Log error, return empty array

---

### 2. Enhance AudioPlayerManager

**File**: `ios/BookVault/Services/AudioPlayerManager.swift`

**Add Properties**:

```swift
@Published var currentChapterId: String? = nil
@Published var chapters: [Chapter] = []
```

**Add Methods**:

```swift
// Get current chapter based on playback position
func getCurrentChapter() -> Chapter? {
    guard !chapters.isEmpty else { return nil }
    return chapters.first { chapter in
        currentTime >= chapter.startTime && currentTime < chapter.endTime
    }
}

// Skip to specific chapter
func skipToChapter(_ chapter: Chapter) {
    seek(to: chapter.startTime)
}
```

**Update Playback Observer**:

- Check current chapter on every time update
- Update `currentChapterId` when chapter changes
- No need for notifications (SwiftUI bindings handle updates)

---

### 3. Create Chapter List UI

**File**: `ios/BookVault/Views/NowPlaying/ChapterListView.swift` (new)

**Design**:

- Sheet presentation (similar to web playback page)
- Scrollable list with current chapter highlighted
- Each row shows:
  - Chapter number badge
  - Chapter title
  - Start time (right-aligned)
  - Duration (right-aligned, smaller text)
  - "Playing" indicator for current chapter

**Layout**:

```
┌─────────────────────────────────────────┐
│  Chapters (12)                      ✕   │ ← Header
├─────────────────────────────────────────┤
│ [1] Chapter 1: Introduction   0:00      │
│                               30:15     │ ← Duration
├─────────────────────────────────────────┤
│ [2] Chapter 2: The Beginning  30:15 ▶   │ ← Current
│                               45:30     │
├─────────────────────────────────────────┤
│ [3] Chapter 3: The Journey    1:15:45   │
│                               52:10     │
└─────────────────────────────────────────┘
```

**Accessibility**:

- VoiceOver labels for each chapter
- Dynamic Type support for text scaling
- Tap targets at least 44pt tall

---

### 4. Integrate with NowPlayingView

**File**: `ios/BookVault/Views/NowPlaying/NowPlayingView.swift`

**Add**:

- "Chapters" button in toolbar (SF Symbol: `list.bullet`)
- Sheet state for chapter list presentation
- Pass `audioPlayerManager.chapters` to ChapterListView
- Handle chapter tap → dismiss sheet, skip to chapter

**Example**:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        if !audioPlayerManager.chapters.isEmpty {
            Button {
                showChapterList = true
            } label: {
                Label("Chapters", systemImage: "list.bullet")
            }
        }
    }
}
.sheet(isPresented: $showChapterList) {
    ChapterListView(
        chapters: audioPlayerManager.chapters,
        currentChapterId: audioPlayerManager.currentChapterId,
        onChapterTap: { chapter in
            audioPlayerManager.skipToChapter(chapter)
            showChapterList = false
        }
    )
}
```

---

### 5. Update BookDetailView

**File**: `ios/BookVault/Views/Books/BookDetailView.swift`

**Add**:

- Fetch chapters when Play button is tapped
- Pass chapters to AudioPlayerManager before starting playback

**Flow**:

1. User taps Play button
2. Fetch chapters in background (non-blocking)
3. Start playback immediately (don't wait for chapters)
4. Update `audioPlayerManager.chapters` when fetch completes
5. Chapters button appears in NowPlayingView when available

---

## Files to Create

1. `ios/BookVault/Services/ChapterManager.swift`
2. `ios/BookVault/Views/NowPlaying/ChapterListView.swift`

---

## Files to Modify

1. `ios/BookVault/Services/AudioPlayerManager.swift`
   - Add `currentChapterId` and `chapters` properties
   - Add `getCurrentChapter()` and `skipToChapter()` methods
   - Update playback observer to track current chapter

2. `ios/BookVault/Views/NowPlaying/NowPlayingView.swift`
   - Add Chapters button in toolbar
   - Add sheet presentation for chapter list

3. `ios/BookVault/Views/Books/BookDetailView.swift`
   - Fetch chapters on Play button tap
   - Pass chapters to AudioPlayerManager

4. `ios/project.yml` (if using XcodeGen)
   - Add new files to Xcode project structure

---

## Testing Strategy

### Unit Tests

**ChapterManager Tests**:

- ✅ Fetch chapters successfully
- ✅ Handle 404 (no chapters) gracefully
- ✅ Handle network errors (return empty array)
- ✅ Cache chapters per book ID
- ✅ Clear cache on logout

**AudioPlayerManager Tests**:

- ✅ getCurrentChapter() returns correct chapter
- ✅ getCurrentChapter() returns nil if no chapters
- ✅ skipToChapter() seeks to correct time
- ✅ currentChapterId updates during playback

### Manual Testing

**Happy Path**:

1. Play audiobook with chapters
2. Open chapter list from Now Playing screen
3. Verify current chapter is highlighted
4. Tap different chapter → playback jumps to that chapter
5. Chapter list dismisses automatically
6. Current chapter indicator updates

**Edge Cases**:

1. **No chapters**: Chapters button should not appear
2. **Single chapter**: List should show one item
3. **Long chapter titles**: Text should truncate with ellipsis
4. **Network error**: Chapter list remains empty (no crash)
5. **Chapter at end of book**: Seeking to last chapter works

**Cross-Platform Sync**:

1. Start playback on iOS
2. Switch to web app
3. Verify chapter progress syncs correctly
4. Switch chapters on web
5. Resume on iOS → should show correct current chapter

---

## Acceptance Criteria

- [ ] User can view chapter list from Now Playing screen
- [ ] Current chapter is highlighted during playback
- [ ] Tapping a chapter skips to that position
- [ ] Chapter list shows title, start time, and duration
- [ ] Books without chapters show no Chapters button
- [ ] Chapter transitions are smooth (no audio glitches)
- [ ] VoiceOver announces chapter names correctly
- [ ] No memory leaks (test with Instruments)

---

## Known Limitations

1. **Chapter Extraction**: Requires FFmpeg on backend
   - Some audiobooks may not have chapter metadata
   - Gracefully degrades to no chapters (not an error)

2. **Chapter Metadata**: Titles depend on audio file tags
   - Some books may have generic titles ("Chapter 1", "Chapter 2")
   - Not a blocker for Phase 5

3. **Performance**: Large chapter lists (50+) untested
   - Consider lazy loading if performance issues arise
   - Most audiobooks have 10-30 chapters

---

## Migration Notes

**No breaking changes**:

- Chapter support is additive (doesn't affect existing functionality)
- Audiobooks without chapters continue to work as before
- No database schema changes required

**Generated Models**:

- `Chapter.swift` already generated from OpenAPI spec
- Includes all required fields: `id`, `title`, `startTime`, `endTime`, `duration`, `index`
- No manual model creation needed

---

## Next Steps After Phase 5

**Phase 6: Search & Browse**

- Search screen with autocomplete
- Browse by author/series/narrator/category
- Requires no Phase 5 dependencies

**Phase 7: User Lists**

- Custom lists (Want to Listen, Favorites)
- Add/remove books from library
- Drag-to-reorder functionality

---

## References

- **API Endpoint**: `app/api/books/[id]/chapters/route.ts`
- **OpenAPI Schema**: `docs/api/openapi.yaml` (Chapter schema, lines 229-257)
- **Web Implementation**: `components/ChapterList.tsx` (reference for UX patterns)
- **Phase Overview**: `docs/mobile/implementation-phases.md` (Phase 5 section)
- **Generated Swift Model**: `ios/BookVault/Generated/Models/Chapter.swift`

---

## Developer Notes

**Time Format**:

- All times in seconds (Double)
- Use `formatTime()` helper for display (HH:MM:SS or MM:SS)

**Thread Safety**:

- All UI updates on main thread (@MainActor)
- API calls on background thread (async/await)

**Caching Strategy**:

- Cache chapters by book ID (in-memory, not persistent)
- Clear cache on logout
- Refetch if book ID changes

**Error Philosophy**:

- Silent failures (don't block playback)
- Log errors for debugging
- Graceful degradation (no chapters = valid state)
