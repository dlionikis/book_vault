# Phase 8 Manual Testing Checklist

**Date**: December 29, 2025
**Tester**: **\*\***\_**\*\***
**Platform**: iOS Simulator (iPhone 17 Pro, iOS 26.2)
**Backend**: http://localhost:3000

---

## Pre-Test Setup

- [ ] Backend running: `npm run dev` (should be on http://localhost:3000)
- [ ] Database running: `docker-compose up -d`
- [ ] iOS app built and installed in simulator
- [ ] Test user logged in: `test@example.com` / `password123`

---

## 1. Library Empty State (3 tests)

### 1.1 Empty State Display

- [x] Navigate to Library tab (rightmost tab)
- [x] Verify empty state message appears: "Your library is empty"
- [x] Verify subtext: "Browse the catalog to add books"
- [x] Verify "Browse Catalog" button is visible and styled correctly

### 1.2 Browse Catalog Button Action

- [x] Tap "Browse Catalog" button
- [x] **Expected**: App switches to Catalog tab
- [x] **Expected**: Catalog shows grid of all books

### 1.3 Return to Empty Library

- [x] From Catalog, tap Library tab again
- [x] **Expected**: Empty state still displays correctly

---

## 2. Add to Library (5 tests)

### 2.1 Navigate to Book Detail from Catalog

- [ ] Go to Catalog tab
- [ ] Tap on any book
- [ ] **Expected**: BookDetailView opens with book info

### 2.2 Add to Library Button Visible

- [ ] In BookDetailView, scroll to see action buttons
- [ ] **Expected**: Blue "+ Add to Library" button below Play button
- [ ] **Expected**: Button is properly styled and tappable

### 2.3 Add Book to Library

- [ ] Tap "+ Add to Library" button
- [ ] **Expected**: Button animates or shows loading state
- [ ] **Expected**: Success feedback (toast/alert or button color change)
- [ ] **Expected**: Button changes to green "✓ In Library"

### 2.4 Verify Book in Library Tab

- [ ] Navigate to Library tab
- [ ] **Expected**: Book appears in library grid
- [ ] **Expected**: Book is at top (most recently added first)
- [ ] **Expected**: Book cover, title, author visible

### 2.5 Series Add Dialog (if applicable)

- [ ] Find a book that's part of a series (e.g., "A Conjuring of Light")
- [ ] Remove from library first if needed
- [ ] Tap "+ Add to Library"
- [ ] **Expected**: Dialog appears with options:
  - "Add Entire Series"
  - "Add Just This Book"
  - "Cancel"
- [ ] Test both options to verify they work

---

## 3. Remove from Library (4 tests)

### 3.1 In Library Button State

- [ ] Open a book that IS in your library
- [ ] **Expected**: Green "✓ In Library" button visible (not "+ Add to Library")

### 3.2 Remove Confirmation Dialog

- [x] Tap "✓ In Library" button
- [x] **Expected**: Action sheet/alert appears with:
  - "Remove from Library" (destructive/red style)
  - "Cancel"

### 3.3 Cancel Removal

- [x] Tap "Cancel" in the dialog
- [x] **Expected**: Dialog dismisses, book stays in library
- [x] **Expected**: Button still shows "✓ In Library"

### 3.4 Confirm Removal

- [x] Tap "✓ In Library" again
- [x] Tap "Remove from Library"
- [x] **Expected**: Book removed, button changes to "+ Add to Library"
- [x] Navigate to Library tab
- [x] **Expected**: Book no longer appears in library

---

## 4. Cross-Platform Sync (4 tests)

### 4.1 Add on iOS → Verify on Web

- [x] On iOS: Add a book to library
- [x] On Web: Open http://localhost:3000/library in browser
- [x] Login with same credentials
- [x] **Expected**: Book appears in web library
- [x] **Expected**: "Added" timestamp matches

### 4.2 Add on Web → Verify on iOS

- [x] On Web: Navigate to catalog, add a different book
- [x] On iOS: Pull-to-refresh Library tab
- [x] **Expected**: Newly added book appears in iOS library
- [x] **Expected**: Sorted correctly (most recent first)

### 4.3 Remove on iOS → Verify on Web

- [x] On iOS: Remove a book from library
- [x] On Web: Refresh /library page
- [x] **Expected**: Book removed from web library

### 4.4 Remove on Web → Verify on iOS

- [x] On Web: Remove a book from library
- [x] On iOS: Pull-to-refresh Library tab
- [x] **Expected**: Book removed from iOS library

---

## 5. Playback from Library (4 tests)

### 5.1 Play Book from Library

- [ ] Tap a book in Library tab
- [ ] Tap "Play" button
- [ ] **Expected**: Navigation to playback page
- [ ] **Expected**: Audio starts playing within 1-2 seconds

### 5.2 Mini Player Appears

- [x] While audio playing, tap back button
- [x] **Expected**: Mini player appears at bottom of screen
- [x] **Expected**: Shows current book cover, title, play/pause

### 5.3 Progress Saves

- [x] Play book for 30+ seconds
- [x] Close app completely (swipe up from app switcher)
- [x] Reopen app
- [x] Navigate to Library tab
- [x] **Expected**: Progress bar shows on book card
- [x] Open book detail
- [x] **Expected**: Last position is preserved

### 5.4 Progress Persists Across Navigation

- [x] Play book from library
- [x] Navigate to Catalog tab, then Browse, then Search
- [x] Return to Library tab
- [x] **Expected**: Progress bar accurate on all book cards

---

## 6. Navigation Flows (4 tests)

### 6.1 Library → BookDetail → Play → Now Playing

- [x] Start at Library tab
- [x] Tap book → BookDetailView opens
- [x] Tap Play → Playback page opens
- [x] **Expected**: Smooth transitions, no crashes
- [x] **Expected**: Back button works at each level

### 6.2 Catalog → BookDetail → Add → Library

- [x] Start at Catalog tab
- [x] Tap book → BookDetailView
- [x] Tap "+ Add to Library"
- [x] Navigate to Library tab
- [x] **Expected**: Book immediately visible (no refresh needed)

### 6.3 Search → BookDetail → Add → Library

- [x] Go to Search tab
- [x] Search for a book (e.g., "Conjuring")
- [x] Tap result → BookDetailView
- [x] Add to library
- [x] Go to Library tab
- [x] **Expected**: Book appears in library

### 6.4 Browse → Author → BookDetail → Add

- [x] Go to Browse tab
- [x] Tap an author
- [x] Tap a book by that author
- [x] Add to library
- [x] Navigate to Library tab
- [x] **Expected**: Book appears in library

---

## 7. Edge Cases & Error Handling (Bonus)

### 7.1 Network Error Handling

- [ ] Turn off WiFi/network
- [ ] Try to add book to library
- [ ] **Expected**: Clear error message
- [ ] Turn network back on
- [ ] Retry → should work
      I'll do this at a later time. can't easily test this in simulation mode.

### 7.2 Duplicate Add

- [x] Try to add same book twice
- [x] **Expected**: Button already shows "✓ In Library"
- [x] **Expected**: No duplicate entries in library

### 7.3 Large Library (if > 50 books)

- [ ] Add 50+ books to library
- [ ] **Expected**: Pagination works correctly
- [ ] **Expected**: Scroll performance is smooth
      I'll test this at a later time. when doing load testing. can't do this eaisly now.

### 7.4 Empty Library After Removing All

- [x] Remove all books from library
- [x] **Expected**: Empty state reappears
- [x] **Expected**: "Browse Catalog" button works

---

## 8. UI/UX Quality Checks

### 8.1 Tab Bar Icons & Labels

- [x] Verify all 4 tabs visible: Catalog, Browse, Search, Library
- [x] Verify icons match plan:
  - Catalog: books.vertical.fill
  - Browse: square.grid.2x2
  - Search: magnifyingglass
  - Library: books.vertical
- [x] Verify selected tab is highlighted

### 8.2 Dark Mode

- [ ] Enable dark mode in simulator (Settings → Display)
- [ ] Test all flows above in dark mode
- [ ] **Expected**: All text readable, colors appropriate

### 8.3 Accessibility

- [ ] Enable VoiceOver
- [ ] Navigate through Library tab
- [ ] **Expected**: All elements properly labeled
- [ ] **Expected**: Actions announced correctly
      I'll test accessibility at a later timee

---

## Test Results Summary

**Total Tests**: 24 core + 8 edge cases = 32 tests
**Passed**: \_**\_
**Failed**: \_\_**
**Blocked**: \_\_\_\_

---

## Issues Found

### Critical Issues

_List any critical bugs that prevent core functionality_

### Minor Issues

_List any UI glitches, typos, or minor bugs_

### Suggestions

_Any UX improvements or enhancements to consider_

---

## Sign-Off

- [ ] All core tests (1-6) passed
- [ ] Cross-platform sync verified
- [ ] No critical issues blocking release
- [ ] Phase 8 can be marked COMPLETE ✅

**Tested By**: **\*\***\_**\*\***
**Date**: **\*\***\_**\*\***
**Sign-Off**: **\*\***\_**\*\*** (mark complete or list blockers)
