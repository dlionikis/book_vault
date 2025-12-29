# iOS Phase 6: Search & Browse - Implementation Plan

**Status**: Planning
**Estimated Duration**: 6-8 hours
**Dependencies**: Phases 1-5 (Auth, Playback, Background Audio, Progress Sync, Chapter Navigation)
**Last Updated**: December 28, 2025

---

## Overview

Phase 6 adds comprehensive search and browse functionality to the iOS app, allowing users to discover books by searching or browsing by author, series, narrator, and category. This phase focuses on discovery features that complement the existing library and playback capabilities.

---

## Objectives

1. **Search**: Full-text search across books, authors, narrators, series
2. **Browse Authors**: List all authors with book counts, view author detail with all books
3. **Browse Series**: List all series with book counts, view series detail with ordered books
4. **Browse Narrators**: List all narrators with book counts, view narrator detail with all books
5. **Browse Categories**: List all categories with book counts, view category detail with all books
6. **Search Suggestions**: Real-time search suggestions as user types (autocomplete)

---

## API Endpoints (All Already Implemented)

### Search

**GET /api/search**

- Query params: `q` (required), `page`, `limit`
- Returns: `{ query, books[], pagination }`
- Full-text search across title, description, author names, narrator names, series titles

**GET /api/search/suggestions**

- Query params: `q` (required)
- Returns: `{ query, books[], authors[] }`
- Fast autocomplete suggestions (top 5 books + top 5 authors)

### Browse Lists

**GET /api/browse/authors**

- Query params: `page`, `limit`
- Returns: `{ authors: AuthorWithBookCount[], total }`
- Sorted alphabetically by name

**GET /api/browse/series**

- Query params: `page`, `limit`
- Returns: `{ series: SeriesWithBookCount[], total }`
- Sorted alphabetically by title

**GET /api/browse/narrators**

- Query params: `page`, `limit`
- Returns: `{ narrators: NarratorWithBookCount[], total }`
- Sorted alphabetically by name

**GET /api/browse/categories**

- Query params: `page`, `limit`
- Returns: `{ categories: CategoryWithBookCount[], total }`
- Sorted alphabetically by name

### Detail Pages

**GET /api/authors/{id}**

- Returns: `{ author: Author, books: Book[] }`
- Books ordered by title

**GET /api/series/{id}**

- Returns: `{ series: Series, books: Book[] }`
- Books ordered by sequence number in series

**GET /api/narrators/{id}**

- Returns: `{ narrator: Narrator, books: Book[] }`
- Books ordered by title

**GET /api/categories/{id}**

- Returns: `{ category: Category, books: Book[] }`
- Books ordered by title

---

## Implementation Tasks

### 1. SearchManager Service

**File**: `ios/BookVault/Services/SearchManager.swift` (NEW)

**Purpose**: Centralized search and browse API client with caching

**Features**:

- Full-text search with pagination
- Search suggestions (autocomplete)
- In-memory caching of recent searches
- Debouncing for suggestions (300ms delay)
- Thread-safe with `@MainActor`

**Key Methods**:

```swift
// Search
func search(query: String, page: Int) async throws -> SearchAll200Response
func getSearchSuggestions(query: String) async throws -> GetSearchSuggestions200Response
func clearSearchCache()

// Browse lists
func fetchAuthors(page: Int, limit: Int) async throws -> ListAuthors200Response
func fetchSeries(page: Int, limit: Int) async throws -> ListSeries200Response
func fetchNarrators(page: Int, limit: Int) async throws -> ListNarrators200Response
func fetchCategories(page: Int, limit: Int) async throws -> ListCategories200Response

// Detail pages
func fetchAuthorDetail(id: String) async throws -> GetAuthor200Response
func fetchSeriesDetail(id: String) async throws -> GetSeries200Response
func fetchNarratorDetail(id: String) async throws -> GetNarrator200Response
func fetchCategoryDetail(id: String) async throws -> GetCategory200Response
```

**Caching Strategy**:

- Cache search results by query + page (in-memory, 5 minutes TTL)
- Cache browse lists by type + page (in-memory, 10 minutes TTL)
- Cache detail pages by ID (in-memory, 10 minutes TTL)
- Clear cache on logout or memory warning

---

### 2. SearchView (Main Search Screen)

**File**: `ios/BookVault/Views/Search/SearchView.swift` (NEW)

**Design**:

```
┌─────────────────────────────────┐
│  🔍 [Search audiobooks...]      │ ← Search bar
├─────────────────────────────────┤
│  Recent Searches (empty state)  │ ← Show before typing
│  • The Expanse                  │
│  • Brandon Sanderson            │
├─────────────────────────────────┤
│  Suggestions (while typing)     │ ← Show after 1+ chars
│  📚 The Way of Kings             │
│  📚 The Name of the Wind         │
│  👤 Brandon Sanderson            │
│  👤 Patrick Rothfuss             │
├─────────────────────────────────┤
│  Search Results (after submit)  │ ← Show after tap search
│  [BookCard] The Way of Kings    │
│  [BookCard] Words of Radiance   │
│  ...                             │
│  [Load More]                    │
└─────────────────────────────────┘
```

**States**:

1. **Empty**: Show recent searches or browse shortcuts
2. **Typing**: Show search suggestions (autocomplete)
3. **Results**: Show paginated search results
4. **Loading**: Show spinner
5. **Error**: Show error message
6. **No Results**: Show "No books found for '{query}'"

**Features**:

- Search bar with clear button
- Real-time suggestions (debounced 300ms)
- Tap suggestion → navigate to book/author detail
- Submit search → show full results with pagination
- Infinite scroll for results (load more on scroll)
- Pull-to-refresh to clear and restart
- Cancel button to exit search

**SwiftUI State**:

```swift
@State private var searchText = ""
@State private var suggestions: GetSearchSuggestions200Response?
@State private var searchResults: SearchAll200Response?
@State private var isLoading = false
@State private var currentPage = 1
@State private var hasMoreResults = false
```

---

### 3. BrowseView (Main Browse Screen)

**File**: `ios/BookVault/Views/Browse/BrowseView.swift` (NEW)

**Design**:

```
┌─────────────────────────────────┐
│  Browse                         │ ← Navigation title
├─────────────────────────────────┤
│  📖 Authors          (142) →    │ ← Browse category tile
│  📚 Series           (38) →     │
│  🎙️ Narrators        (87) →     │
│  🏷️ Categories       (24) →     │
└─────────────────────────────────┘
```

**Features**:

- Four browse categories as large taps targets
- Book count shown for each category
- Tapping a category navigates to list view
- Simple, clean design with SF Symbols icons

**SwiftUI Implementation**:

```swift
struct BrowseCategoryRow {
    let title: String
    let icon: String
    let count: Int
    let destination: AnyView
}
```

---

### 4. AuthorListView

**File**: `ios/BookVault/Views/Browse/AuthorListView.swift` (NEW)

**Design**:

```
┌─────────────────────────────────┐
│  Authors                        │ ← Navigation title
├─────────────────────────────────┤
│  A                              │ ← Section header
│  👤 Andy Weir          (2 books)│
│  👤 Arthur C. Clarke   (5 books)│
│                                 │
│  B                              │
│  👤 Brandon Sanderson (12 books)│
│  ...                            │
└─────────────────────────────────┘
```

**Features**:

- Alphabetically sorted by name
- Section headers for first letter (A, B, C, ...)
- Book count shown for each author
- Infinite scroll (pagination)
- Pull-to-refresh
- Search bar to filter authors (local filter)
- Tapping author → AuthorDetailView

**SwiftUI State**:

```swift
@State private var authors: [AuthorWithBookCount] = []
@State private var currentPage = 1
@State private var isLoading = false
@State private var hasMorePages = false
```

---

### 5. AuthorDetailView

**File**: `ios/BookVault/Views/Browse/AuthorDetailView.swift` (NEW)

**Design**:

```
┌─────────────────────────────────┐
│  ← Brandon Sanderson            │ ← Navigation bar
├─────────────────────────────────┤
│  👤 Brandon Sanderson           │ ← Large author name
│  12 books                       │ ← Book count
├─────────────────────────────────┤
│  Books                          │ ← Section header
│  [BookCard] The Way of Kings    │
│  [BookCard] Words of Radiance   │
│  [BookCard] Oathbringer         │
│  ...                            │
└─────────────────────────────────┘
```

**Features**:

- Author name as title
- Book count subtitle
- Grid or list of books (reuse BooksGridView/BooksListView)
- Books sorted by title
- Tapping book → BookDetailView

---

### 6. SeriesListView

**File**: `ios/BookVault/Views/Browse/SeriesListView.swift` (NEW)

**Design**: Same as AuthorListView but for series

- Alphabetically sorted by title
- Section headers for first letter
- Book count shown for each series
- Infinite scroll + pull-to-refresh

---

### 7. SeriesDetailView

**File**: `ios/BookVault/Views/Browse/SeriesDetailView.swift` (NEW)

**Design**:

```
┌─────────────────────────────────┐
│  ← The Stormlight Archive       │ ← Navigation bar
├─────────────────────────────────┤
│  📚 The Stormlight Archive      │ ← Large series title
│  4 books                        │ ← Book count
├─────────────────────────────────┤
│  Books in Series Order          │ ← Section header
│  [BookCard] 1. The Way of Kings │ ← Show sequence number
│  [BookCard] 2. Words of Radiance│
│  [BookCard] 3. Oathbringer      │
│  [BookCard] 4. Rhythm of War    │
└─────────────────────────────────┘
```

**Features**:

- Series title as title
- Book count subtitle
- Books sorted by sequence number (NOT alphabetically)
- Show sequence number on each book card
- "Add Series to Library" button (optional)

---

### 8. NarratorListView & NarratorDetailView

**Files**:

- `ios/BookVault/Views/Browse/NarratorListView.swift` (NEW)
- `ios/BookVault/Views/Browse/NarratorDetailView.swift` (NEW)

**Design**: Same pattern as AuthorListView/AuthorDetailView

- List view: Alphabetically sorted with section headers
- Detail view: Show all books narrated by this narrator

---

### 9. CategoryListView & CategoryDetailView

**Files**:

- `ios/BookVault/Views/Browse/CategoryListView.swift` (NEW)
- `ios/BookVault/Views/Browse/CategoryDetailView.swift` (NEW)

**Design**: Same pattern as AuthorListView/AuthorDetailView

- List view: Alphabetically sorted with section headers
- Detail view: Show all books in this category

---

### 10. Navigation Integration

**File**: `ios/BookVault/Views/ContentView.swift` (MODIFIED)

**Changes**:

- Add new tab for "Browse" (icon: `square.grid.2x2`)
- Add new tab for "Search" (icon: `magnifyingglass`)

**Updated TabView**:

```swift
TabView(selection: $selectedTab) {
    BooksListView()
        .tabItem { Label("Library", systemImage: "books.vertical") }
        .tag(Tab.library)

    BrowseView()  // NEW
        .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
        .tag(Tab.browse)

    SearchView()  // NEW
        .tabItem { Label("Search", systemImage: "magnifyingglass") }
        .tag(Tab.search)

    // ... other tabs
}
```

---

## SwiftUI Component Reuse

**Reuse existing components** to minimize duplication:

1. **BookCard** (`Views/Books/BookCard.swift`)
   - Use for all book displays in search/browse results
   - Shows cover, title, author, progress indicators

2. **BooksListView** pattern
   - Pagination logic
   - Pull-to-refresh
   - Infinite scroll
   - Empty states

3. **Loading/Error States**
   - Reuse from existing views
   - Consistent error handling

---

## Accessibility

All new views must include:

1. **VoiceOver Labels**:
   - Search bar: "Search audiobooks"
   - Browse categories: "Browse authors, 142 authors"
   - Author rows: "Brandon Sanderson, 12 books"
   - Book counts: "12 books by this author"

2. **VoiceOver Hints**:
   - "Tap to search"
   - "Tap to view books by this author"
   - "Tap to view books in this series"

3. **Dynamic Type**:
   - All text scales with system text size settings
   - Minimum line height for readability

4. **Tap Targets**:
   - Minimum 44pt tall for all interactive elements
   - Sufficient spacing between rows

5. **Color Contrast**:
   - Meet WCAG AA standards (4.5:1 for text)
   - Test in light and dark mode

---

## Performance Considerations

1. **Debouncing**:
   - Search suggestions debounced by 300ms
   - Prevents excessive API calls while typing

2. **Pagination**:
   - Load 20 items per page (default)
   - Infinite scroll with "Load More" trigger
   - Only load next page when user scrolls to bottom

3. **Caching**:
   - Cache search results for 5 minutes
   - Cache browse lists for 10 minutes
   - Cache detail pages for 10 minutes
   - Clear cache on logout or memory warning

4. **Image Loading**:
   - Reuse existing `AsyncImage` with caching
   - Lazy load images as they appear in scroll view

5. **List Virtualization**:
   - SwiftUI `List` automatically virtualizes rows
   - Only visible rows are rendered

---

## Error Handling

**Network Errors**:

```swift
do {
    let results = try await searchManager.search(query: query, page: page)
    self.searchResults = results
} catch {
    // Show error alert
    self.errorMessage = "Failed to load search results. Please try again."
    self.showError = true
}
```

**Empty States**:

- "No results found for '{query}'"
- "No authors found"
- "No books in this series yet"

**Graceful Degradation**:

- Search unavailable → show cached results or empty state
- Network error → show retry button
- Timeout → show timeout message with retry

---

## Testing Checklist

### Manual Testing

**Search**:

- [ ] Type query → suggestions appear after 300ms
- [ ] Tap suggestion → navigate to book/author
- [ ] Submit search → show full results
- [ ] Scroll results → load more pages
- [ ] Empty search → show "No results"
- [ ] Network error → show error message

**Browse Authors**:

- [ ] List loads with alphabetical sections
- [ ] Scroll to bottom → load more authors
- [ ] Tap author → show author detail
- [ ] Author detail shows all books
- [ ] Tap book → navigate to book detail

**Browse Series**:

- [ ] List loads with alphabetical sections
- [ ] Tap series → show series detail
- [ ] Series detail shows books in order
- [ ] Sequence numbers displayed correctly

**Browse Narrators**:

- [ ] Same pattern as authors

**Browse Categories**:

- [ ] Same pattern as authors

**Edge Cases**:

- [ ] Author with 100+ books → pagination works
- [ ] Series with non-numeric sequences (1.5, Prequel)
- [ ] Search query with special characters
- [ ] Very long book/author/series names → truncate properly

**Performance**:

- [ ] Search suggestions respond within 500ms
- [ ] Scroll performance is smooth (60fps)
- [ ] Image loading doesn't block UI
- [ ] Memory usage is acceptable (< 100MB for lists)

**Accessibility**:

- [ ] VoiceOver announces all elements correctly
- [ ] Dynamic Type scales text properly
- [ ] Tap targets are at least 44pt tall
- [ ] Color contrast meets WCAG AA

---

## Acceptance Criteria

- ✅ User can search for books by title, author, narrator, series
- ✅ Search suggestions appear as user types (autocomplete)
- ✅ User can browse authors alphabetically with book counts
- ✅ User can browse series alphabetically with book counts
- ✅ User can browse narrators alphabetically with book counts
- ✅ User can browse categories alphabetically with book counts
- ✅ Tapping author/series/narrator/category shows detail page with all books
- ✅ Series detail page shows books in sequence order
- ✅ All lists support pagination (infinite scroll)
- ✅ Pull-to-refresh works on all list views
- ✅ Search results are relevant and fast (< 1 second)
- ✅ Empty states are clear and helpful
- ✅ Error states show retry options
- ✅ VoiceOver announces all elements correctly
- ✅ Dark mode works properly
- ✅ No memory leaks (tested with Instruments)

---

## Files to Create (10)

1. `ios/BookVault/Services/SearchManager.swift` - Search/browse API client
2. `ios/BookVault/Views/Search/SearchView.swift` - Main search screen
3. `ios/BookVault/Views/Browse/BrowseView.swift` - Main browse screen
4. `ios/BookVault/Views/Browse/AuthorListView.swift` - Author list
5. `ios/BookVault/Views/Browse/AuthorDetailView.swift` - Author detail
6. `ios/BookVault/Views/Browse/SeriesListView.swift` - Series list
7. `ios/BookVault/Views/Browse/SeriesDetailView.swift` - Series detail
8. `ios/BookVault/Views/Browse/NarratorListView.swift` - Narrator list
9. `ios/BookVault/Views/Browse/NarratorDetailView.swift` - Narrator detail
10. `ios/BookVault/Views/Browse/CategoryListView.swift` - Category list
11. `ios/BookVault/Views/Browse/CategoryDetailView.swift` - Category detail

---

## Files to Modify (1)

1. `ios/BookVault/Views/ContentView.swift` - Add Browse and Search tabs

---

## Dependencies

**Swift Models** (already generated):

- ✅ `SearchAll200Response`
- ✅ `GetSearchSuggestions200Response`
- ✅ `ListAuthors200Response` / `AuthorWithBookCount`
- ✅ `ListSeries200Response` / `SeriesWithBookCount`
- ✅ `ListNarrators200Response` / `NarratorWithBookCount`
- ✅ `ListCategories200Response` / `CategoryWithBookCount`
- ✅ `GetAuthor200Response`
- ✅ `GetSeries200Response`
- ✅ `GetNarrator200Response`
- ✅ `GetCategory200Response`
- ✅ `Book`, `Author`, `SeriesInfo`, `Narrator`, `Category`

**Backend APIs** (all implemented):

- ✅ `/api/search` (with pagination)
- ✅ `/api/search/suggestions`
- ✅ `/api/browse/authors`
- ✅ `/api/browse/series`
- ✅ `/api/browse/narrators`
- ✅ `/api/browse/categories`
- ✅ `/api/authors/{id}`
- ✅ `/api/series/{id}`
- ✅ `/api/narrators/{id}`
- ✅ `/api/categories/{id}`

---

## Known Limitations

1. **Search Scope**: Full-text search across all metadata
   - May return too many results for generic queries
   - No advanced filters (runtime, release date, etc.)
   - Consider adding filters in future phase

2. **Browse Pagination**: 20 items per page
   - May be slow for authors with 100+ books
   - Consider virtualized lists for very large datasets

3. **Offline Support**: Search/browse requires network
   - Phase 8 (Offline Downloads) will add offline browse
   - Downloaded books will be searchable offline

4. **Category Hierarchy**: Flat category list
   - Backend supports hierarchical categories (ladders)
   - iOS shows flat list for simplicity
   - Consider hierarchical navigation in future

---

## Next Steps After Phase 6

**Phase 7: User Lists**

- Custom lists (Want to Listen, Favorites)
- Add/remove books from library
- Drag-to-reorder functionality
- List management UI

**Phase 8: Offline Downloads** (Optional)

- Download books for offline listening
- Cache metadata and chapters
- Background download support
- Storage management UI

---

## Git Commit Message (Suggested)

```
feat(ios): Phase 6 - Search & Browse complete

Implements comprehensive search and browse functionality:
- SearchManager service with caching and debouncing
- SearchView with autocomplete suggestions
- BrowseView with four browse categories
- Author/Series/Narrator/Category list and detail views
- Alphabetical sorting with section headers
- Pagination and infinite scroll
- Pull-to-refresh support
- Accessibility (VoiceOver, Dynamic Type)

New files (11):
- ios/BookVault/Services/SearchManager.swift
- ios/BookVault/Views/Search/SearchView.swift
- ios/BookVault/Views/Browse/BrowseView.swift
- ios/BookVault/Views/Browse/AuthorListView.swift
- ios/BookVault/Views/Browse/AuthorDetailView.swift
- ios/BookVault/Views/Browse/SeriesListView.swift
- ios/BookVault/Views/Browse/SeriesDetailView.swift
- ios/BookVault/Views/Browse/NarratorListView.swift
- ios/BookVault/Views/Browse/NarratorDetailView.swift
- ios/BookVault/Views/Browse/CategoryListView.swift
- ios/BookVault/Views/Browse/CategoryDetailView.swift

Modified files (1):
- ios/BookVault/Views/ContentView.swift (added tabs)

Testing: Manual testing checklist created, ready for device testing

🤖 Generated with Claude Code

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

**Phase 6 Status**: 📋 Planning Complete - Ready for Implementation

**Estimated Implementation Time**: 6-8 hours
**Estimated Testing Time**: 2-3 hours
**Total Phase 6**: 8-11 hours

---

**Created By**: Claude Sonnet 4.5
**Date**: December 28, 2025
**Session**: iOS Phase 6 Planning
