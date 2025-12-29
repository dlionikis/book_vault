# iOS Library UX Alignment - Implementation Plan

**Status**: Planning (awaiting approval)
**Created**: December 29, 2025
**Priority**: HIGH - Critical UX inconsistency between web and iOS

---

## Problem Statement

### Current State (iOS)

The iOS app has a **critical UX inconsistency** with the web app:

- **"Library" tab**: Shows **ALL books in catalog** (should show user's personal library)
- **No library management**: Cannot add/remove books from library
- **Direct playback**: Users play directly from full catalog (not from their library)

### Expected State (Web App Pattern)

The web app follows a proper library pattern:

1. **Browse catalog** at `/` (home page)
2. **Add books to "My Library"** via `AddToLibraryButton`
3. **View library** at `/library` page (only shows added books)
4. **Play from library** (books you've chosen to add)

### User Impact

- **Confusing**: "Library" tab shows all books, not user's library
- **No curation**: Cannot build a personal library of books to read
- **Poor UX**: Must browse full catalog to find books to play

---

## Proposed Solution

### High-Level Design

Restructure iOS app to match web pattern:

```
┌─────────────────────────────────────────────────┐
│  Before (Current)           │  After (Proposed) │
├─────────────────────────────┼───────────────────┤
│  Library: All books         │  Library: My Books│
│  Browse: Metadata browse    │  Catalog: All books│
│  Search: Keyword search     │  Browse: Metadata │
│                             │  Search: Keyword  │
└─────────────────────────────┴───────────────────┘
```

### New Tab Structure

**4 Tabs** (adding "Catalog"):

```
┌─ Catalog    (books.vertical.fill) - All available books
├─ Browse     (square.grid.2x2) - Browse by author/series/etc
├─ Search     (magnifyingglass) - Keyword search
└─ Library    (books.vertical) - User's personal library
```

---

## Implementation Plan

### Phase 1: Backend Verification ✅

**Goal**: Confirm library API endpoints are ready for iOS

**Endpoints to verify**:

- ✅ `GET /api/library` - Get user's library books
- ✅ `POST /api/library` - Add book to library
- ✅ `DELETE /api/library/{bookId}` - Remove from library
- ✅ `GET /api/library/check?bookId={id}` - Check if book in library

**Status**: Already implemented and tested in OpenAPI spec

---

### Phase 2: Create LibraryManager Service

**File**: `ios/BookVault/Services/LibraryManager.swift`

**Purpose**: Centralized API client for library operations

**Responsibilities**:

```swift
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    // Fetch user's library books
    func fetchLibraryBooks() async throws -> [Book]

    // Add book to library
    func addToLibrary(bookId: String) async throws

    // Remove book from library
    func removeFromLibrary(bookId: String) async throws

    // Check if book is in library
    func isInLibrary(bookId: String) async throws -> Bool

    // Optional: Add entire series
    func addSeriesToLibrary(seriesId: String) async throws
}
```

**Caching Strategy**:

- Cache library book list in memory
- Invalidate on add/remove operations
- Refresh on pull-to-refresh

**Estimated effort**: 2 hours

---

### Phase 3: Rename BooksListView → CatalogView

**Current**: `BooksListView` (shows all books, labeled "Library")

**New**: `CatalogView` (shows all books, labeled "Catalog")

**Changes**:

1. Rename file: `BooksListView.swift` → `CatalogView.swift`
2. Rename struct: `BooksListView` → `CatalogView`
3. Rename view model: `BooksListViewModel` → `CatalogViewModel`
4. Update navigation title: `.navigationTitle("Library")` → `.navigationTitle("Catalog")`
5. Update empty state text: "Your library is empty" → "No books in catalog"
6. Keep all existing functionality (grid, pagination, progress indicators)

**No API changes needed**: Still calls `GET /api/books` (all books)

**Estimated effort**: 30 minutes

---

### Phase 4: Create New LibraryView

**File**: `ios/BookVault/Views/Library/LibraryView.swift`

**Purpose**: Show only books user has added to library

**Data Source**: `GET /api/library` (returns `LibraryBook[]`)

**UI Design** (similar to CatalogView):

```
┌────────────────────────────────────────┐
│  Library                     [Logout]  │ ← Navigation bar
├────────────────────────────────────────┤
│                                        │
│  [Empty State]                         │ ← If no books in library
│   📚 "Your library is empty"           │
│   "Browse the catalog to add books"    │
│   [Browse Catalog] button              │
│                                        │
│  OR                                    │
│                                        │
│  ┌──────┐  ┌──────┐  ┌──────┐         │ ← Grid of library books
│  │ Book │  │ Book │  │ Book │         │   (same as CatalogView)
│  │ Cover│  │ Cover│  │ Cover│         │
│  │──────│  │──────│  │──────│         │
│  │Title │  │Title │  │Title │         │
│  │Author│  │Author│  │Author│         │
│  │12h 3m│  │8h 45m│  │5h 30m│         │
│  │━━━━━ │  │━━━━━ │  │━━━━━ │         │ ← Progress bars
│  │[✓]   │  │      │  │      │         │ ← Completion badge
│  └──────┘  └──────┘  └──────┘         │
│                                        │
└────────────────────────────────────────┘
```

**Features**:

- Grid layout (reuse `BookGridItem` from CatalogView)
- Progress indicators (already in `BookGridItem`)
- Pull-to-refresh
- Empty state with "Browse Catalog" button
- Tap book → `BookDetailView`

**Key Differences from CatalogView**:

1. Data source: `LibraryManager.fetchLibraryBooks()` vs `APIClient.fetchBooks()`
2. Empty state: Suggests browsing catalog to add books
3. Smart pagination: No pagination for < 50 books, paginate if ≥ 50 books
4. Sorted by `addedAt` (most recently added first)

**Estimated effort**: 2 hours

---

### Phase 5: Add Library Management to BookDetailView

**File**: `ios/BookVault/Views/Books/BookDetailView.swift`

**Add**: "Add to Library" / "Remove from Library" button

**UI Location**: Below "Play" button, above book metadata

**Button States**:

```swift
┌─────────────────────────────────────┐
│  [▶ Play]                           │ ← Existing play button
├─────────────────────────────────────┤
│  [+ Add to Library]                 │ ← New: Not in library
│  OR                                 │
│  [✓ In Library]                     │ ← New: Already in library
└─────────────────────────────────────┘
```

**Behavior**:

1. **On appear**: Check `LibraryManager.isInLibrary(bookId)`
2. **Not in library**: Show blue "+ Add to Library" button
3. **In library**: Show green "✓ In Library" button
4. **Tap when not in library**: Call `LibraryManager.addToLibrary(bookId)`
5. **Tap when in library**: Show action sheet:
   ```
   ┌─────────────────────────────────┐
   │  Remove from Library?           │
   ├─────────────────────────────────┤
   │  [Remove from Library]          │ ← Destructive style
   │  [Cancel]                       │
   └─────────────────────────────────┘
   ```

**Series Enhancement** (included in v1):

- If book is part of series, show dialog when adding:

  ```
  ┌─────────────────────────────────┐
  │  Add to Library                 │
  ├─────────────────────────────────┤
  │  This book is part of a series. │
  │  What would you like to add?    │
  ├─────────────────────────────────┤
  │  [Add Entire Series]            │
  │  [Add Just This Book]           │
  │  [Cancel]                       │
  └─────────────────────────────────┘
  ```

- When removing, only show option to remove individual book (not entire series)

**Estimated effort**: 1.5 hours

---

### Phase 6: Update ContentView Tab Structure

**File**: `ios/BookVault/ContentView.swift`

**Changes**:

1. **Update Tab enum**:

   ```swift
   enum Tab {
       case library  // User's library
       case catalog  // All books (renamed from library)
       case browse   // Metadata browse
       case search   // Keyword search
   }
   ```

2. **Update TabView**:

   ```swift
   TabView(selection: $selectedTab) {
       CatalogView()  // RENAMED: All books (was BooksListView)
           .tabItem { Label("Catalog", systemImage: "books.vertical.fill") }
           .tag(Tab.catalog)

       BrowseView()  // UNCHANGED
           .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
           .tag(Tab.browse)

       SearchView()  // UNCHANGED
           .tabItem { Label("Search", systemImage: "magnifyingglass") }
           .tag(Tab.search)

       LibraryView()  // NEW: User's personal library
           .tabItem { Label("Library", systemImage: "books.vertical") }
           .tag(Tab.library)
   }
   ```

3. **Set default tab**:
   ```swift
   @State private var selectedTab: Tab = .catalog  // Start on Catalog tab
   ```

**Tab Order Rationale**:

1. **Catalog** (discovery first) - Browse all available books
2. **Browse** (filtered discovery) - By author/series/narrator
3. **Search** (specific lookup) - Find specific books
4. **Library** (rightmost) - User's curated books (rightmost like "Library" in Apple Music)

**Estimated effort**: 30 minutes

---

### Phase 7: Update XcodeGen Configuration

**File**: `ios/project.yml`

**Reason**: New files added (LibraryManager, LibraryView)

**Action**: Run `cd ios && xcodegen generate`

**Estimated effort**: 5 minutes

---

### Phase 8: Testing & Validation

**Test Scenarios**:

1. **Library Empty State**:
   - [ ] New user: Library tab shows empty state
   - [ ] Empty state has "Browse Catalog" button
   - [ ] Tapping button navigates to Catalog tab

2. **Add to Library**:
   - [ ] Browse catalog, open book detail
   - [ ] See "Add to Library" button
   - [ ] Tap button → success feedback
   - [ ] Button changes to "In Library"
   - [ ] Navigate to Library tab → book appears

3. **Remove from Library**:
   - [ ] Open book in library
   - [ ] See "In Library" button
   - [ ] Tap button → confirmation dialog
   - [ ] Tap "Remove" → book removed
   - [ ] Library tab updates (book disappears)

4. **Cross-Platform Sync**:
   - [ ] Add book on iOS → appears in web library
   - [ ] Add book on web → appears in iOS library
   - [ ] Remove book on iOS → removed from web
   - [ ] Remove book on web → removed from iOS

5. **Playback from Library**:
   - [ ] Play book from Library tab
   - [ ] Mini player appears
   - [ ] Progress saves correctly
   - [ ] Navigate away and back → progress persists

6. **Navigation Flows**:
   - [ ] Library → BookDetail → Play → Now Playing
   - [ ] Catalog → BookDetail → Add to Library → Library tab
   - [ ] Search → BookDetail → Add to Library → Library tab
   - [ ] Browse → AuthorDetail → BookDetail → Add to Library

**Estimated effort**: 2 hours

---

## Implementation Summary

### Files to Create (2 new files)

1. `ios/BookVault/Services/LibraryManager.swift` (new service)
2. `ios/BookVault/Views/Library/LibraryView.swift` (new view)

### Files to Rename (1 file)

1. `ios/BookVault/Views/Books/BooksListView.swift` → `CatalogView.swift`

### Files to Modify (2 files)

1. `ios/BookVault/Views/Books/BookDetailView.swift` (add library button)
2. `ios/BookVault/ContentView.swift` (update tabs)

### Total Estimated Effort

- **Development**: 8.5 hours
- **Testing**: 2 hours
- **Total**: ~10.5 hours (1-2 days)

---

## API Endpoints Used

All endpoints already exist in backend:

| Endpoint                         | Method | Purpose                    |
| -------------------------------- | ------ | -------------------------- |
| `/api/library`                   | GET    | Fetch user's library books |
| `/api/library`                   | POST   | Add book to library        |
| `/api/library/{bookId}`          | DELETE | Remove book from library   |
| `/api/library/check?bookId={id}` | GET    | Check if book in library   |
| `/api/books`                     | GET    | Fetch all books (catalog)  |

**Backend changes needed**: ❌ None - all APIs already implemented

---

## Design Decisions ✅ APPROVED

1. **Tab Order**: `Catalog → Browse → Search → Library` ✅
   - Discovery first, library rightmost (Apple Music pattern)

2. **Tab Icons**: ✅
   - Catalog: `books.vertical.fill`
   - Browse: `square.grid.2x2`
   - Search: `magnifyingglass`
   - Library: `books.vertical`

3. **Empty Library State**: Simple empty state with "Browse Catalog" button ✅
   - Message: "Your library is empty"
   - Subtext: "Browse the catalog to add books"
   - Button: "Browse Catalog" (navigates to Catalog tab)
   - No "Continue Listening" carousel in empty state

4. **Series Add Feature**: Include in Phase 5 ✅
   - Show dialog: "Add Entire Series" or "Add Just This Book"
   - Only on add (not on remove)

5. **Pagination**: Smart pagination ✅
   - Load all if < 50 books (most users)
   - Paginate if ≥ 50 books (power users)

---

## Success Criteria

- [ ] iOS app matches web UX pattern (catalog → library → play)
- [ ] Users can add books to library from catalog/search/browse
- [ ] Library tab shows only user's books (not all books)
- [ ] Empty library state guides users to catalog
- [ ] Library changes sync across web and iOS
- [ ] All existing features still work (playback, progress, chapters)

---

## Next Steps

1. **Review this plan** - Get approval on design decisions
2. **Resolve open questions** - Decide on tab order, icons, features
3. **Begin implementation** - Start with Phase 1 (verification)
4. **Incremental testing** - Test after each phase
5. **Final validation** - Full test suite in Phase 8

---

**Questions? Concerns? Let's discuss before proceeding!**
