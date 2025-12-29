# iOS Library UX Alignment - Implementation Prompts

**Reference Plan**: [library-ux-alignment-plan.md](library-ux-alignment-plan.md)

Use these prompts when starting each phase in a fresh context. Copy/paste exactly as written.

---

## Phase 1: Backend Verification

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md and verify Phase 1.

Check that these API endpoints exist and are functional:
- GET /api/library
- POST /api/library
- DELETE /api/library/{bookId}
- GET /api/library/check?bookId={id}

Verify they're in the OpenAPI spec at docs/api/openapi.yaml and that the backend implementations exist in app/api/library/.

Report status and mark Phase 1 complete.
```

---

## Phase 2: Create LibraryManager Service

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 2.

Create ios/BookVault/Services/LibraryManager.swift following the spec in the plan:
- fetchLibraryBooks() -> [Book]
- addToLibrary(bookId:)
- removeFromLibrary(bookId:)
- isInLibrary(bookId:) -> Bool
- addSeriesToLibrary(seriesId:)

Use APIClient.shared pattern, include caching strategy, follow existing Swift patterns in the codebase.

After creating the file, run: cd ios && xcodegen generate

Mark Phase 2 complete.
```

---

## Phase 3: Rename BooksListView → CatalogView

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 3.

Rename ios/BookVault/Views/Books/BooksListView.swift to CatalogView.swift:
1. Rename file: BooksListView.swift → CatalogView.swift
2. Rename struct: BooksListView → CatalogView
3. Rename view model: BooksListViewModel → CatalogViewModel
4. Update navigation title: "Library" → "Catalog"
5. Update empty state: "Your library is empty" → "No books in catalog"

Keep all functionality identical (grid, pagination, progress indicators).

After renaming, run: cd ios && xcodegen generate

Mark Phase 3 complete.
```

---

## Phase 4: Create New LibraryView

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 4.

Create ios/BookVault/Views/Library/LibraryView.swift that shows user's personal library:
- Data source: LibraryManager.fetchLibraryBooks()
- Grid layout (reuse BookGridItem from CatalogView)
- Empty state: "Your library is empty" + "Browse the catalog to add books" + [Browse Catalog] button
- Smart pagination: No pagination if < 50 books, paginate if ≥ 50
- Sorted by addedAt (most recent first)
- Pull-to-refresh

After creating the file, run: cd ios && xcodegen generate

Mark Phase 4 complete.
```

---

## Phase 5: Add Library Management to BookDetailView

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 5.

Modify ios/BookVault/Views/Books/BookDetailView.swift to add library management:

1. Add "Add to Library" / "In Library" button below Play button
2. On appear: Check LibraryManager.isInLibrary(bookId)
3. Not in library: Show blue "+ Add to Library" button
4. In library: Show green "✓ In Library" button
5. Add series dialog: If book has series, show dialog with "Add Entire Series" or "Add Just This Book"
6. Remove: Show confirmation action sheet (destructive style)

Follow the exact UI specs in Phase 5 of the plan.

Mark Phase 5 complete.
```

---

## Phase 6: Update ContentView Tab Structure

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 6.

Modify ios/BookVault/ContentView.swift:

1. Update Tab enum: library, catalog, browse, search
2. Update TabView order: Catalog → Browse → Search → Library
3. Tab icons:
   - Catalog: books.vertical.fill
   - Browse: square.grid.2x2
   - Search: magnifyingglass
   - Library: books.vertical
4. Set default tab: .catalog
5. Replace BooksListView with CatalogView, add LibraryView

Follow exact specs in Phase 6.

Mark Phase 6 complete.
```

---

## Phase 7: Update XcodeGen Configuration

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 7.

Run: cd ios && xcodegen generate

Verify the Xcode project includes:
- LibraryManager.swift
- LibraryView.swift
- CatalogView.swift (renamed from BooksListView)

Open ios/BookVault.xcodeproj and confirm all new files are present.

Mark Phase 7 complete.
```

---

## Phase 8: Testing & Validation

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md Phase 8.

Follow the complete test checklist in Phase 8:
1. Library Empty State (3 scenarios)
2. Add to Library (5 scenarios)
3. Remove from Library (4 scenarios)
4. Cross-Platform Sync (4 scenarios)
5. Playback from Library (4 scenarios)
6. Navigation Flows (4 scenarios)

Test on iOS Simulator, document any issues found.

If all tests pass, mark Phase 8 complete and implementation DONE ✅
```

---

## Quick Start (All Phases)

If you want to run all phases in one session:

```
Read docs/mobile/implementation-phases/library-ux-alignment-plan.md

Implement all 8 phases of the iOS Library UX Alignment:
1. Backend Verification
2. Create LibraryManager Service
3. Rename BooksListView → CatalogView
4. Create New LibraryView
5. Add Library Management to BookDetailView
6. Update ContentView Tab Structure
7. Update XcodeGen Configuration
8. Testing & Validation

Follow the plan exactly. Run xcodegen after file changes. Report progress after each phase.
```

---

## Notes

- Always read the full plan before starting: `docs/mobile/implementation-phases/library-ux-alignment-plan.md`
- Run `cd ios && xcodegen generate` after creating/renaming files
- Test incrementally - don't wait until Phase 8
- If stuck, refer back to the detailed plan
- Mark todos as you progress through phases
