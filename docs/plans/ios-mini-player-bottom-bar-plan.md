# iOS Mini Player → Bottom Bar Plan

> **Status**: In progress (started July 30, 2026)
> **Scope**: iOS app only (no API, DB, or web changes)
> **Created**: July 28, 2026 · **Revised** July 30, 2026 after Plan A landed
> **Prerequisites landed**: A5 `NavigationStack` migration (#135) · XCUITest harness (#137, #138)

---

## 0. Revisions since this plan was written

Plan A (#133–#136) and the UI-test work (#137–#138) changed four of this plan's premises:

1. **Phase 4 is deleted.** The conditional `NavigationView` → `NavigationStack` migration happened in
   A5 (#135). `NavigationView` is now **absent from the codebase**, so the plan's single biggest risk —
   deprecated containers dropping the safe-area inset — is gone. Phase 3's audit still matters, but it
   now verifies a modern container rather than probing a deprecated one's edge cases.
2. **There is now an XCUITest suite** (#137, #138) — 6 passing flows. §5's "if the project's E2E suite
   drives the UI" is no longer hypothetical: see §5a.
3. ~~**A likely cause of a known bug is in this plan's blast radius.**~~ — **tested and disproved
   (July 30, 2026).** The theory was that the overlay's full-screen `Spacer()` inside the `ZStack` was
   swallowing touches app-wide. Measured on the simulator: with the overlay present, a book cell reports
   `hittable == false`; with the overlay **entirely removed**, it is _still_ `hittable == false`. So the
   mini player is **not** the cause, and **this change will not unblock U3/U5.** Treat those as
   independent work. Details and the next lead are in
   [ios-ui-testing-plan.md](ios-ui-testing-plan.md) §6b.

4. **Open question 2 is now partly answered.** `loadMostRecentlyPlayedBook()` is suppressed under
   `--uitesting` (#137), but in shipping builds it still populates `currentBook` at launch, so the bar
   **will** appear on cold start for any user with playback history. Still worth an explicit decision.

Also confirmed against the current code: `MiniPlayerView` is unchanged apart from the two
`accessibilityIdentifier` calls added in #137, so Phase 1's steps all still apply.

---

## 1. Goal

Move the "Now Playing" mini player from a floating overlay at the **top** of the screen to a
**persistent bar at the bottom**, positioned **below the tab bar**, and make the usable content
area of every screen end at the **top edge of that bar** so nothing is ever occluded.

### Current behavior

`ContentView` renders a `ZStack(alignment: .top)` containing the `TabView`, with `MiniPlayerView`
floated on top inside a `VStack { MiniPlayerView; Spacer() }`
([ContentView.swift:66-144](../../ios/BookVault/ContentView.swift#L66-L144)).

`MiniPlayerView` is a 68pt-tall, 70%-width, right-aligned rounded card with a shadow
([MiniPlayerView.swift:13-87](../../ios/BookVault/Components/MiniPlayerView.swift#L13-L87)).
The 70%/right-aligned geometry exists specifically to dodge the leading-edge navigation title and
back button — a constraint that **disappears** once it moves to the bottom.

### Target behavior

```
┌─────────────────────────────┐
│  Nav bar / title            │
├─────────────────────────────┤
│                             │
│   Scrollable content        │  ← content may scroll under the
│   (full width, ends at      │    bars, but its *insets* end at
│    top of mini bar)         │    the top of the mini bar
│                             │
├─────────────────────────────┤
│  [Tabs]  ← floating tab bar │
├─────────────────────────────┤
│  ▓ Cover  Title    ⏸  ▓     │  ← mini player, full width
└─────────────────────────────┘
      ↑ home indicator / safe area below
```

---

## 2. Key decision: ordering vs. the tab bar

The request is explicit: the mini bar sits **below** the floating navigation (tab) bar. This is the
inverse of the Apple Music / Podcasts convention (mini player _above_ the tab bar), so it is worth
stating plainly as a deliberate choice rather than assuming the platform default.

**This is achievable but constrains the implementation.** SwiftUI gives no supported way to inject a
view _beneath_ a `TabView`'s own tab bar. Two viable strategies:

### Strategy A — Outer `safeAreaInset` (recommended)

Wrap the whole `TabView` in a container whose bottom safe-area inset is the mini bar. The system tab
bar then lays out _above_ the inset, and the mini bar occupies the strip below it.

```swift
TabView(selection: $selectedTab) { … }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        if audioPlayer.currentBook != nil {
            MiniPlayerBar()
        }
    }
```

- **Pro**: One insertion point. `safeAreaInset` on the `TabView` reduces the safe area for _every_
  tab and every pushed destination inside it, so content insets are handled by the framework — no
  per-screen padding to maintain.
- **Pro**: Works on the iOS 17.0 deployment target (`project.yml:33`); `safeAreaInset` is iOS 15+.
- **Con**: The tab bar sits higher than users expect, and the mini bar must own the bottom safe-area
  region (home indicator) itself.

### Strategy B — Fully custom bottom stack

Replace the system tab bar with a custom one so both bars are ordinary views in a `VStack`.

- **Pro**: Total ordering control.
- **Con**: Loses free tab-bar behaviors (blur material, scroll-edge effects, accessibility, tab
  reordering, VoiceOver grouping). Large rewrite of `ContentView`'s 8-tab structure and the
  online/offline tab-swap logic (`handleNetworkChange`). **Not recommended for this change.**

> ⚠️ **Explicitly out of scope**: `tabViewBottomAccessory` (iOS 26) places the accessory _above_ the
> tab bar and requires raising the deployment target from 17.0. It also implements the opposite of
> the requested ordering. Noted only so it is not mistaken for the right tool.

**Decision: Strategy A.** Confirm the ordering preference before building (see §8).

---

## 3. Requirements

### 3.1 Functional

| ID  | Requirement                                                                                                                                                         |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | When `AudioPlayerManager.shared.currentBook != nil`, a mini player bar is pinned to the bottom of the window, below the tab bar, on every tab.                      |
| F2  | When `currentBook == nil`, the bar is absent and content extends to the tab bar as it does today.                                                                   |
| F3  | The bar shows cover art, title, author, and a play/pause toggle — parity with today's content.                                                                      |
| F4  | Tapping the bar (outside the play/pause hit area) presents `NowPlayingView` as a sheet, unchanged.                                                                  |
| F5  | Tapping play/pause toggles playback **without** presenting the sheet.                                                                                               |
| F6  | The bar persists across tab switches and across navigation pushes within a tab.                                                                                     |
| F7  | The bar appears/disappears with an animated transition when playback starts/stops.                                                                                  |
| F8  | The bar is **not** shown over the login screen, the session-restore loading state, or any full-screen sheet (`NowPlayingView`, `BookDetailLoader` deep-link sheet). |

### 3.2 Layout / no-occlusion (the core of this change)

| ID  | Requirement                                                                                                                                                                                                                                                                                   |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1  | **The usable content area of every screen ends at the top edge of the mini bar.** No screen's content is clipped, hidden, or unreachable behind it.                                                                                                                                           |
| L2  | Scrollable content can scroll _under_ the bars visually, but its **content inset** must stop above the mini bar, so the last row is fully scrollable into view.                                                                                                                               |
| L3  | Bottom-pinned UI in any screen (buttons, toolbars, "Load More" affordances) sits above the mini bar.                                                                                                                                                                                          |
| L4  | When the bar is absent, no phantom bottom gap remains.                                                                                                                                                                                                                                        |
| L5  | The bar spans the full window width and reserves the bottom safe area (home indicator) beneath its content, so no content draws into the indicator region.                                                                                                                                    |
| L6  | Layout is correct on notched, Dynamic Island, and home-button devices, and in both orientations if landscape is supported.                                                                                                                                                                    |
| L7  | The keyboard must not push the mini bar up over content or leave it stranded mid-screen — existing `.ignoresSafeArea(.keyboard)` at [ContentView.swift:145](../../ios/BookVault/ContentView.swift#L145) needs re-verification against the new bottom placement, most visibly on `SearchView`. |

### 3.3 Visual

| ID  | Requirement                                                                                                                                                    |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V1  | Full-width bar with a top hairline divider — replacing the current 70%-width right-aligned rounded card, whose geometry only existed to dodge nav-bar buttons. |
| V2  | Background uses a system material so content scrolling beneath reads as layered, consistent with the tab bar's own material.                                   |
| V3  | Correct in light and dark mode (honoring `ThemeManager.selectedTheme`).                                                                                        |
| V4  | Bar content height stays ~56–68pt, _plus_ the bottom safe-area inset.                                                                                          |
| V5  | Optional: a thin progress line along the bar's top edge. **Deferred** — not in this change.                                                                    |

### 3.4 Accessibility

| ID  | Requirement                                                                                                                                                                                                                                             |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1  | The bar is one combined accessibility element labeled "Now playing: {title}", with the play/pause button as a separate, separately-labeled control (today's `.accessibilityElement(children: .combine)` collapses the button into the card — fix this). |
| A2  | Play/pause keeps a ≥44×44pt hit target.                                                                                                                                                                                                                 |
| A3  | Bar height grows with Dynamic Type up to the accessibility sizes without clipping title/author; content inset must track the actual height, not a hardcoded constant.                                                                                   |
| A4  | VoiceOver focus order: content → tab bar → mini player.                                                                                                                                                                                                 |
| A5  | The appear/disappear transition respects Reduce Motion.                                                                                                                                                                                                 |

---

## 4. Implementation plan

### Phase 1 — Rebuild `MiniPlayerView` as a bottom bar

**File**: [ios/BookVault/Components/MiniPlayerView.swift](../../ios/BookVault/Components/MiniPlayerView.swift)

1. Delete the `GeometryReader` and the `frame(width: geometry.size.width * 0.70)` /
   `.frame(maxWidth: .infinity, alignment: .trailing)` pair — obsolete at the bottom (V1).
2. Delete the fixed `.frame(height: 68)`; let the bar size to its content so Dynamic Type works (A3).
3. Replace the `RoundedRectangle` + shadow background with a full-width material background plus a
   top `Divider`.
4. Restructure so the row content is padded but the background extends into the bottom safe area:
   apply the material to the container and let the safe-area inset region be filled by it (L5, V4).
5. Split accessibility: `.accessibilityElement(children: .contain)` on the bar, an
   `.accessibilityLabel`/`.accessibilityAddTraits(.isButton)` on the tappable region, and leave the
   play/pause `Button` as its own element (A1).
6. Keep the `NowPlayingView` sheet on the tappable region (F4) and confirm the nested play/pause
   `Button` does not also fire the outer action (F5) — nested buttons in SwiftUI need
   `.buttonStyle(.plain)` on both plus care that the outer is not a `Button` wrapping the inner.
   **Prefer** restructuring: outer `.onTapGesture` / `contentShape` instead of nested `Button`s.
7. Update the four `#Preview` blocks — they currently wrap in `VStack { Spacer(); MiniPlayerView() }`
   which already previews it bottom-anchored, so mostly they just need width assertions.

### Phase 2 — Reposition in `ContentView`

**File**: [ios/BookVault/ContentView.swift](../../ios/BookVault/ContentView.swift)

1. Remove the `ZStack(alignment: .top)` wrapper and the `VStack { MiniPlayerView(); Spacer() }`
   overlay block (lines 66, 135–143).
2. Attach `.safeAreaInset(edge: .bottom, spacing: 0)` to the `TabView`, rendering `MiniPlayerView()`
   when `audioPlayer.currentBook != nil` (F1, F2, L1, L2).
3. Move the `.transition` / `.animation` modifiers onto the inset content, gated on Reduce Motion (F7, A5).
4. Keep `.ignoresSafeArea(.keyboard)` on the outer view, then re-verify L7 — with a bottom inset this
   modifier's effect changes materially and may need to move onto the inset content instead.
5. Confirm the inset does **not** apply to the `authManager.isAuthenticated == false` branch or the
   `isRestoringSession` branch (F8) — it is attached to the `TabView` only, so this should hold by
   construction; verify.

### Phase 3 — Audit every screen for occlusion (L1–L4)

`safeAreaInset` on the `TabView` should propagate automatically, and since A5 (#135) every tab root is
a `NavigationStack` rather than a deprecated `NavigationView` — so propagation into pushed destinations
is now expected to work rather than being the plan's main risk. Still verify each screen, because
"expected to work" is not "verified":

| Screen                                                                                               | What to verify                                                                                                          |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `CatalogView`                                                                                        | Last grid row fully scrollable; "load more" `ProgressView` reachable; Books/Series toggle unaffected                    |
| `LibraryView`                                                                                        | Same as Catalog; empty-state centering still looks centered (`.padding(.top, 60/100)` was tuned against the old layout) |
| `SearchView`                                                                                         | Results list bottom; **keyboard interaction with the bar (L7)**                                                         |
| `BrowseView` + `AuthorDetailView` / `NarratorDetailView` / `CategoryDetailView` / `SeriesDetailView` | Pushed destinations inherit the inset                                                                                   |
| `BookDetailView`                                                                                     | Bottom action buttons not occluded; it presents its own `NowPlayingView` sheet                                          |
| `DownloadsView`                                                                                      | List bottom; per-row progress affordances                                                                               |
| `RestoreRequestsView`                                                                                | Only tab already in a `NavigationStack` — good control case                                                             |
| `SettingsView`                                                                                       | `Form` bottom section reachable                                                                                         |
| `OfflineModeView`                                                                                    | Its `.padding(.bottom, 20)` may now double up                                                                           |

Where a screen has bottom-pinned chrome of its own, ensure it composes with the inset rather than
adding its own hardcoded padding — **no hardcoded mini-bar height anywhere** (A3).

### Phase 4 — ~~Migrate `NavigationView` → `NavigationStack`~~ **(done in A5, #135)**

No longer part of this plan. `NavigationView` is absent from the codebase, and every tab root plus
pushed destination is a `NavigationStack`.

---

## 5. Testing

### Manual matrix

| Dimension      | Cases                                                        |
| -------------- | ------------------------------------------------------------ |
| Playback state | no book loaded / loaded-paused / playing                     |
| Tab            | all 6 online tabs + offline tab                              |
| Depth          | tab root and ≥1 pushed destination                           |
| Device         | notched, Dynamic Island, home-button (SE)                    |
| Appearance     | light, dark, system-following via `ThemeManager`             |
| Dynamic Type   | default, XXL, accessibility-XL                               |
| Keyboard       | `SearchView` focused, both with and without a loaded book    |
| Motion         | Reduce Motion on/off                                         |
| Network        | online tabs and the offline tab swap (`handleNetworkChange`) |

**Critical check for every combination**: scroll to the absolute bottom of the content and confirm
the final element clears the mini bar's top edge (L1/L2).

### Automated

- Extend the existing iOS unit tests for any extracted height/inset helper. Note that
  `AudioPlayerManagerRealTests.swift` already references the mini player path — check it does not
  assert on layout.
- SwiftUI layout is not directly unit-testable here; if the project's E2E suite drives the UI, add a
  case asserting a bottom-most list row is hittable while a book is loaded.
- Run the full gate: **`npm run validate:full`** (per `CLAUDE.md` §2 — `npm test` alone is not
  sufficient). This change is iOS-only, so `npm run validate:ios` is the fast inner loop, but
  `validate:full` gates the PR.
- No `openapi.yaml` change → no `api:generate:swift`, no contract-test impact.

---

## 5a. Automated verification (new — the suite did not exist when this plan was written)

An XCUITest suite now exists (#137, #138) with 6 passing flows.

### Do not expect this change to unblock the deferred UI tests

The hypothesis that the mini-player overlay caused the `hittable == false` blocker was **tested and
disproved** (see §0.3): removing the overlay entirely changed nothing. The 7 deferred tests on
`ios-uitests-u3-u5-wip` stay deferred, and three of them would have been this plan's regression net:

| Deferred test                                    | Requirement it would have covered |
| ------------------------------------------------ | --------------------------------- |
| `testStartingPlaybackShowsMiniPlayer`            | F1                                |
| `testTappingMiniPlayerOpensFullPlayer`           | F4                                |
| `testMiniPlayerPlayPauseIsSeparatelyAddressable` | F5, A1                            |

**Consequence: F1/F4/F5/A1 and all of L1–L7 must be verified manually** for this change, per §5's
matrix. That is the same position A5 was in, and it is worth stating plainly rather than implying the
suite covers this work.

### What the existing suite still gives us

The 6 passing flows are a regression net for _not breaking what works_: login renders, catalog loads,
the visible tabs are reachable, and — directly relevant here —
`testMiniPlayerIsHiddenBeforePlayback` asserts the bar is absent before playback, which is **F2**.
Run `npm run ios:test:ui` before and after.

### Worth adding once the hit-test bug is fixed

Not now, since these need the same taps that are currently blocked:

- With a book loaded, scroll a tab to the bottom and assert the last cell is hittable — a direct
  encoding of L1/L2.
- Assert the mini bar and tab bar frames do not overlap.

> **Note on `.accessibilityElement(children: .combine)`** — A1 requires play/pause be a separate
> element, and #137 found the combine modifier collapses it into the parent. Phase 1 step 5 fixes it,
> but with `testMiniPlayerPlayPauseIsSeparatelyAddressable` deferred, **verify by VoiceOver manually.**

---

## 6. Risks

| Risk                                                                               | Impact                                   | Mitigation                                                                                   |
| ---------------------------------------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------- |
| ~~`NavigationView` drops the safe-area inset~~ — **resolved by A5 (#135)**         | —                                        | `NavigationView` no longer exists; every container is a `NavigationStack`                    |
| Nested `Button` (play/pause inside the bar's tappable region) makes taps ambiguous | F5 breaks; sheet opens on every pause    | Restructure to `contentShape` + `onTapGesture` instead of nested `Button`s                   |
| Tab bar sitting above the mini bar reads as unfamiliar                             | UX regression vs. Apple Music convention | Confirm ordering with the user first (§8); Strategy A is reversible to above-tab-bar cheaply |
| Keyboard + bottom inset + `.ignoresSafeArea(.keyboard)` interaction                | Bar strands mid-screen over `SearchView` | Explicit L7 test case                                                                        |
| Empty-state paddings tuned against the old top overlay                             | Slightly off-center empty states         | Re-eyeball `LibraryView`/`CatalogView`/`SearchView` empty states                             |

---

## 7. Out of scope

- Swipe-to-dismiss the mini bar
- Progress line on the bar (V5, deferred)
- Skip / seek controls in the bar
- `NowPlayingView` redesign
- CarPlay (see the separate `carplay-*` plans)
- Raising the iOS deployment target from 17.0
- Any web, API, or database change

---

## 8. Open questions

1. ~~**Ordering**~~ — **settled**: below the tab bar, as originally requested. Strategy A implements
   this and is cheaply reversible to above-the-tab-bar if it reads wrong in practice.
2. **Swipe to dismiss** — **still open, and now more visible.** There is no way to clear `currentBook`
   from the UI, and `loadMostRecentlyPlayedBook()` populates it at launch, so any user with playback
   history sees the bar on cold start before pressing play. A full-width bottom bar is more prominent
   than the old 70% top card, so "permanently present with no dismissal" is a more noticeable choice
   than it was. Out of scope to build here (§7), but worth deciding.
3. **Height** — keep ~68pt content height, or tighten to ~56pt now that it is full width?
4. **Tab bar material** — should the tab bar become opaque so the two stacked bars read as one unit?
