# CarPlay App — Implementation Plan & Task Breakdown

> **Created**: July 27, 2026
> **Reviewed**: July 31, 2026 — every §1 finding re-verified against current code; see §0
> **Status**: Scoped — ready to start (Track A can begin immediately)
> **Priority**: TBD
> **Platform**: iOS only
> **Requirements doc**: [carplay-app-plan.md](carplay-app-plan.md)
> **Deployment target**: iOS 17.0 (`project.yml`) — all CarPlay APIs used here are iOS 14+, so no bump needed.

---

## 0. Review notes (July 31, 2026)

The plan was re-checked against the codebase before starting. **All seven §1.2 findings still
hold** — verified individually:

| Finding                                         | Verified                                                                         |
| ----------------------------------------------- | -------------------------------------------------------------------------------- |
| #1 `UIApplicationSupportsMultipleScenes: false` | ✅ `project.yml:40`                                                              |
| #2 Pure SwiftUI lifecycle, no `UISceneDelegate` | ✅ `BookVaultApp.swift` — `@main`, `WindowGroup`, `UIApplicationDelegateAdaptor` |
| #3 Chapters loaded by views, not the player     | ✅ `play(book:)` never fetches; only `ContentView:247` + `BookDetailView:378` do |
| #4 `isRestoringSession` starts `true`           | ✅ `AuthManager.swift:19`                                                        |
| #5 `getCover(for:)` sync + cache-only           | ✅ `CoverCacheManager.swift:123`                                                 |
| #6 No CarPlay image downsampling helper         | ✅ absent                                                                        |
| #7 Protocol-mocked test infra                   | ✅ `BookVaultTests/Mocks/` (6 mocks)                                             |

Every API the plan builds against exists with the assumed signature:
`fetchLibrarySeriesView(page:limit:)`, `fetchLibraryBooks(forceRefresh:)`,
`isBookDownloaded(bookId:)`, `play(book:)`, `skipToChapter(_:)`, `setPlaybackRate(_:)`.

**Three things changed since the plan was written:**

1. **⚠️ The app is now on Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`** (#144). The plan
   predates this and never mentions concurrency. This is a **material new constraint on every new
   file**: `CarPlaySceneDelegate` runs on the main actor, but the provider/coordinator will be
   crossing isolation boundaries to reach `AudioPlayerManager.shared` (`@MainActor`) and
   `APIClientProtocol` (now `Sendable`). Expect to annotate as you go rather than at the end — the
   A4 experience was that fixing these late is much more expensive than designing for them. Note
   also that a green local build does **not** prove CI green: CI pins an older Xcode, and the
   Swift-6 adoption took five rounds of CI-only failures to settle.

2. **Q6 is resolved.** The plan says the session-persistence bug is open and recommends fixing it
   before ship. It **shipped** (#131, verified on device) and is archived. C1 still needs to handle
   mid-drive logout, but the "spurious logout" risk in §6 is no longer live and should not gate C5.

3. **A UI-test target now exists** (`BookVaultUITests`, 15 flows). A1's phone-regression pass is no
   longer purely manual — `npm run ios:test:ui` covers launch, navigation, and the mini player,
   which is exactly the blast radius of the multi-scene change. Run it as part of A1.

**One judgement call to flag:** A0 (the Apple entitlement request) is a business process, not code.
It gates shipping but nothing in development. Everything below is buildable and testable in the
CarPlay Simulator without it, so the entitlement is deliberately **not** treated as a blocker for
starting.

---

## 1. Codebase Findings (resolves the requirements doc's open questions)

An investigation of `ios/` was done before writing this plan. Every open question in the
requirements doc is now answerable from the code. **Read this section before starting — it
changes the shape of several tasks.**

### 1.1 What already exists (good news, confirmed)

| Capability            | Where                                                                              | Notes                                                                     |
| --------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Playback engine       | `Services/AudioPlayerManager.swift` (singleton)                                    | `play(book:)`, `resume()`, `pause()`, `seek(to:)`, `skipForward/Backward` |
| Remote command center | `AudioPlayerManager.setupRemoteCommandCenter()`                                    | Play/pause/skip/`MPChangePlaybackPositionCommand` already wired           |
| Now Playing info      | `AudioPlayerManager.updateNowPlayingInfo()`                                        | Title/artist/artwork/elapsed/duration/rate, incl. per-chapter metadata    |
| Chapters              | `@Published var chapters`, `skipToChapter(_:)`                                     | Model + seek logic exist                                                  |
| Chapter fetch + cache | `Services/ChapterManager.swift`                                                    | `fetchChapters`, `getCachedChapters`, `hasCachedChapters`                 |
| Background audio      | `Info.plist` `UIBackgroundModes: [audio, …]`                                       | Already declared                                                          |
| Library data          | `Services/LibraryManager.swift`                                                    | `fetchLibraryBooks(forceRefresh:)`, offline-capable cache                 |
| Series data           | `APIClientProtocol.fetchLibrarySeriesView(page:limit:)`                            | Paged; landed in PR #128/#129                                             |
| Cover images          | `Services/CoverCacheManager.swift`                                                 | `getCover(for:) -> UIImage?`, `hasCover(for:)` — sync, memory+disk        |
| Offline playback      | `AudioPlayerManager.playFromLocalFile`, `StorageManager.isBookDownloaded(bookId:)` | Real download feature exists                                              |
| Auth state            | `AuthManager.shared.isAuthenticated`, `isRestoringSession`                         | `@Published`, observable from a scene delegate                            |

**Implication**: this is genuinely "add a scene + template UI over `AudioPlayerManager.shared`."
No playback logic gets rewritten.

### 1.2 What does NOT exist / will bite (the real work)

These are the findings that drive the task list:

1. **`UIApplicationSupportsMultipleScenes` is `false`.** CarPlay requires `true`, and it must be
   set in **`project.yml`** (the `info.properties` block), not by hand-editing `Info.plist` —
   XcodeGen regenerates the plist from `project.yml` on every `xcodegen generate`. Flipping this
   to `true` changes UIKit lifecycle behavior for the _phone_ app too, so it needs a phone-app
   regression pass, not just a CarPlay test.

2. **The app is pure SwiftUI `App` lifecycle** (`BookVaultApp.swift`, `@main struct BookVaultApp: App`)
   with an `@UIApplicationDelegateAdaptor(AppDelegate.self)`. There is **no `UISceneDelegate`** today.
   Adding a CarPlay scene means adding an explicit `UIApplicationSceneManifest` with **two** scene
   configurations (the SwiftUI window scene _and_ the CarPlay scene). Getting the manifest
   half-right is the classic failure mode here: the phone app silently launches to a black screen.
   Budget real time for this task; it is the highest-risk item in the build.

3. **Chapters are loaded by _view_ code, not by the player.** `AudioPlayerManager.play(book:)`
   does **not** fetch chapters. Chapters only get populated because `BookDetailView` and
   `ContentView` call `chapterManager.fetchChapters(...)` → `audioPlayer.updateChapters(...)`.
   **CarPlay never presents those views**, so a book started from CarPlay would have an empty
   `chapters` array and no chapter controls. This is the answer to requirements Q4, and it needs a
   **non-CarPlay refactor** (Task A3) that also fixes the same latent gap for the phone app's
   lock-screen/CarPlay-less remote controls.

4. **`AuthManager` clears state on logout but nothing in a CarPlay scene would react.** There's a
   known `forceLogout()` path plus the open session-persistence bug
   ([ios-audio-session-persistence-plan.md](../archive/completed-plans/ios-audio-session-persistence-plan.md)). The CarPlay
   scene must _observe_ `isAuthenticated` and swap its root template live, mid-drive. Also note
   `isRestoringSession` starts `true` — CarPlay can connect before the keychain restore finishes,
   so "not authenticated yet" ≠ "logged out". Rendering the sign-in message on a cold CarPlay
   launch is a real bug risk if that distinction is missed.

5. **`CoverCacheManager.getCover(for:)` is synchronous and cache-only** — it returns `nil` on a
   miss rather than fetching. CarPlay list rows need a placeholder + async fill, or rows render
   art-less. Covers are pre-warmed for library books (`cacheCoversForBooks`), so the library path
   is mostly warm; the series path is not necessarily.

6. **No `CPListItem`-friendly image sizing exists.** CarPlay requires images at specific point
   sizes for the head unit's scale; passing a full-res `UIImage` wastes memory and can be rejected
   at render. Needs a small downsampling helper.

7. **Test infra is protocol-mocked** (`MockAPIClient`, `APIClientProtocol`, `BookVaultTests/Mocks/`).
   CarPlay template code should follow the same pattern — put logic in a testable
   `CarPlayLibraryProvider`/coordinator that takes protocols, so the template-building logic is
   unit-testable without a head unit. This matches the `APIClientProtocol`-not-`URLSession.shared`
   hardening invariant in `CLAUDE.md`.

### 1.3 Answers to the requirements doc's open questions

| #   | Question                           | Answer                                                                                                                                                                                                                                                                              |
| --- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | Entitlement lead time              | **Unknown/likely not submitted — treat as the critical path.** Track A0 below; do it first, it gates nothing in dev but gates _shipping_.                                                                                                                                           |
| Q2  | Relationship to Series View Toggle | **Resolved — the toggle already landed** (PRs #126–#129, `fetchLibrarySeriesView` exists and is paged). Build CarPlay against the final model now. No sequencing risk remains.                                                                                                      |
| Q3  | Offline/downloaded content         | **A download feature absolutely exists** (`DownloadManager`, `StorageManager.isBookDownloaded`) and `AudioPlayerManager` already prefers local files. v1 gets this **for free** — but should surface a "Downloaded" section, since streaming in a car is the flakiest network case. |
| Q4  | Chapter navigation                 | **Requires the Task A3 refactor** (finding #3). Chapters are not fetched by the player. Degrade gracefully: show chapter controls only when `chapters` is non-empty.                                                                                                                |
| Q5  | Testing                            | CarPlay Simulator (Xcode ▸ I/O ▸ External Displays ▸ CarPlay) for the loop; unit tests for provider/coordinator logic; one real-head-unit pass before ship. `validate:full` still applies.                                                                                          |
| Q6  | Auth/session behavior              | Must be handled in-scene regardless (finding #4). ~~Recommend sequencing after the session-persistence bug fix~~ — **that bug shipped (#131) and is archived**, so no sequencing constraint remains. The sign-in template is still needed either way.                               |

---

## 2. Architecture

### 2.1 Scene topology

```
BookVaultApp (@main, SwiftUI App)
├── WindowGroup ──────────────► ContentView          (phone UI, unchanged)
└── CPTemplateApplicationScene ► CarPlaySceneDelegate (new)
                                      │
                                      ├─ CPInterfaceController (root: setRootTemplate)
                                      │
                                      ├─ Authenticated ──► CPTabBarTemplate
                                      │                     ├── Continue Listening (CPListTemplate)
                                      │                     ├── Library           (CPListTemplate, paged)
                                      │                     ├── Series            (CPListTemplate → books)
                                      │                     └── Downloaded        (CPListTemplate)
                                      │
                                      └─ Logged out ─────► CPInformationTemplate ("Sign in on your phone")

                                CPNowPlayingTemplate (pushed on selection; system-provided UI)
                                      └── binds to AudioPlayerManager.shared via MPNowPlayingInfoCenter
```

Both scenes talk to the **same singletons** (`AudioPlayerManager.shared`, `AuthManager.shared`,
`LibraryManager.shared`). That's what makes phone/CarPlay stay in sync for free — requirement AC4.

### 2.2 New files

```
ios/BookVault/CarPlay/
├── CarPlaySceneDelegate.swift        # CPTemplateApplicationSceneDelegate; lifecycle + auth switching
├── CarPlayCoordinator.swift          # Template stack owner; auth observation; testable
├── CarPlayLibraryProvider.swift      # Data → [CPListItem]; takes protocols; unit-testable
├── CarPlayImageProvider.swift        # Cover fetch + downsample to CarPlay point sizes
└── CarPlayNowPlaying.swift           # CPNowPlayingTemplate config + chapter buttons

ios/BookVaultTests/CarPlay/
├── CarPlayLibraryProviderTests.swift
└── CarPlayCoordinatorTests.swift
```

### 2.3 Key design decisions

- **`CPTabBarTemplate` as root** (not a plain list) — CarPlay caps root tabs at 5, and it gives
  Library / Series / Downloaded / Continue without nesting. Matches the phone app's tab model.
- **Provider takes protocols, not singletons**, so it unit-tests against `MockAPIClient`.
- **Never build playback logic in CarPlay code** — every selection funnels to
  `AudioPlayerManager.shared.play(book:)`. This preserves AC4 sync and the hardening invariants.
- **CarPlay list depth limit**: CarPlay enforces a maximum push depth (5). Series → books → play is
  only 2, so there's headroom.

---

## 3. Phased Task Breakdown

Three tracks. **Track A is the critical path and can start today.** Track B is parallelizable
between two people if desired. Sizes are relative (S/M/L), not calendar estimates.

### Track A — Foundation (must be sequential)

| ID     | Task                              | Size  | Depends | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------ | --------------------------------- | ----- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A0** | Request CarPlay audio entitlement | S     | —       | Submit the request to Apple for `com.apple.developer.carplay-audio`. **Do this first, today.** It's a business-process bottleneck with unpredictable lead time (weeks), and every other task can proceed without it. Track the request ID.                                                                                                                                                                                                                                                                                                                                                                            |
| **A1** | Scene manifest + multi-scene      | **L** | —       | In `project.yml`: set `UIApplicationSupportsMultipleScenes: true`, add a full `UIApplicationSceneManifest` with `UISceneConfigurations` for both `UIWindowSceneSessionRoleApplication` (SwiftUI default) and `CPTemplateApplicationSceneSessionRoleApplication`. Run `xcodegen generate`. **Highest-risk task** — verify the _phone_ app still launches, backgrounds, and handles push deep links before moving on. Run **`npm run ios:test:ui`** (15 XCUITest flows) as part of this task: launch, navigation and mini-player are exactly the blast radius, and that suite did not exist when this plan was written. |
| **A2** | `CarPlaySceneDelegate` skeleton   | M     | A1      | Implement `CPTemplateApplicationSceneDelegate` (`didConnect`/`didDisconnect` interface controller). Ship a hardcoded one-item `CPListTemplate` to prove the scene connects in the CarPlay Simulator. Merge this as a walking skeleton before building real UI.                                                                                                                                                                                                                                                                                                                                                        |
| **A3** | Chapter loading in the player     | M     | —       | **Refactor, not CarPlay code.** Move chapter fetching into `AudioPlayerManager.play(book:)` (or a small `loadChapters(for:)` it calls) using `ChapterManager`, so chapters populate regardless of which UI started playback. Prefer `getCachedChapters` first, then async fetch. Remove/keep the view-level calls as thin pass-throughs. Fixes finding #3 and improves lock-screen chapter behavior on the phone too. **Independently valuable — can merge before any CarPlay work.**                                                                                                                                 |
| **A4** | Entitlement wiring                | S     | A0, A1  | Once Apple approves: add `com.apple.developer.carplay-audio` to `BookVault.entitlements`, update the provisioning profile. Note the existing comment in `project.yml` — entitlements are a committed file, _not_ XcodeGen-generated; don't let `xcodegen` clobber it.                                                                                                                                                                                                                                                                                                                                                 |

### Track B — Templates & Data (parallelizable after A2)

| ID     | Task                        | Size | Depends    | Description                                                                                                                                                                                                                                                                                                                                            |
| ------ | --------------------------- | ---- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **B1** | `CarPlayImageProvider`      | S    | —          | Cover art for list rows: `CoverCacheManager.getCover(for:)` on the hot path, placeholder on miss, async fetch + row refresh. Downsample to CarPlay point sizes for the connected trait collection (finding #5, #6).                                                                                                                                    |
| **B2** | `CarPlayLibraryProvider`    | M    | —          | Maps `LibraryManager.fetchLibraryBooks()` and `fetchLibrarySeriesView(page:limit:)` into `[CPListItem]`. Protocol-injected. Handles empty/error/offline states. Pure logic — **write unit tests here**.                                                                                                                                                |
| **B3** | Library list template       | M    | A2, B1, B2 | `CPListTemplate` for the user's library. Respect the paging that PR #129 introduced — do not over-request; CarPlay lists should page or cap (CarPlay allows large lists but the head unit throttles scrolling).                                                                                                                                        |
| **B4** | Series browse templates     | M    | B3         | Series `CPListTemplate` → drill into `SeriesDetailView`-equivalent book list → select to play. Mirrors the phone hierarchy that landed in #126–#129.                                                                                                                                                                                                   |
| **B5** | Downloaded + Continue tabs  | S    | B3         | Two extra `CPListTemplate`s: downloaded books (`StorageManager.isBookDownloaded`) and continue-listening (progress-sorted, same logic as `ContentView`'s most-recent load). Cheap, high value in a car.                                                                                                                                                |
| **B6** | `CPTabBarTemplate` assembly | S    | B3, B4, B5 | Compose the tabs into the root template. Enforce the 5-tab cap.                                                                                                                                                                                                                                                                                        |
| **B7** | Now Playing template        | M    | A3, B3     | `CPNowPlayingTemplate.shared`: enable `isUpNextButtonEnabled`/album-artist button as appropriate, add chapter prev/next as `CPNowPlayingButton`s **only when `chapters` is non-empty** (Q4 graceful degradation). Verify `updateNowPlayingInfo()` output renders correctly. Playback rate button is a nice-to-have — `setPlaybackRate` already exists. |

### Track C — Auth, Hardening, Ship

| ID     | Task                        | Size | Depends   | Description                                                                                                                                                                                                                                                                                                                 |
| ------ | --------------------------- | ---- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **C1** | Auth-state template swap    | M    | A2, B6    | Observe `AuthManager.shared.$isAuthenticated`. Logged out → `CPInformationTemplate` ("Sign in on your phone to listen"). **Must distinguish `isRestoringSession == true` (show a loading/neutral state) from genuinely logged out** (finding #4). Handle live mid-drive logout by swapping the root template, not crashing. |
| **C2** | Offline / error states      | S    | B2, C1    | `NetworkMonitor` is already present. Offline + nothing downloaded → clear message. Offline + downloads → show the Downloaded tab. Never show an empty unexplained list.                                                                                                                                                     |
| **C3** | Unit tests                  | M    | B2, C1    | Cover `CarPlayLibraryProvider` (mapping, empty, error, paging) and coordinator auth transitions, using existing `MockAPIClient`/`BookVaultTests/Mocks` patterns. Respects the coverage-ratchet invariant.                                                                                                                   |
| **C4** | CarPlay Simulator test pass | M    | all above | Full manual matrix (see §5). This is the primary QA loop.                                                                                                                                                                                                                                                                   |
| **C5** | Real head-unit pass         | S    | C4, A4    | Requires the approved entitlement + a real car/dock. Cannot be faked; schedule it.                                                                                                                                                                                                                                          |
| **C6** | Docs                        | S    | C4        | Update `docs/mobile/architecture.md` with the scene topology, and `docs/STATUS.md`. Note the CarPlay testing loop in `docs/testing.md`.                                                                                                                                                                                     |

### Dependency graph (critical path in bold)

```
A0 ──────────────────────────────────────────────► A4 ──► C5
     (Apple review — wall-clock, not effort)        ▲
                                                    │
**A1 ──► A2** ──┬──► B3 ──┬──► B4 ──┐               │
                │         ├──► B5 ──┼──► B6 ──► C1 ──┴──► C4 ──► C6
     B1 ────────┤         │         │            ▲
     B2 ────────┴─────────┘         │            │
                                    └──► B7      C2, C3
     A3 ──────────────────────────────► B7
```

**Two independent long poles**: Apple's entitlement review (A0) and the A1→A2→B3→B6→C1→C4 chain.
Starting A0 late is the single most likely cause of a slipped ship date.

---

## 4. Recommended Sequencing

1. **Today**: A0 (entitlement request) — unblocks nothing, gates everything at ship time.
2. **Also safe to start now**: A3 (chapter refactor). It's a standalone improvement that merges
   independently of CarPlay and de-risks B7.
3. **First code PR**: A1 + A2 as a walking skeleton — riskiest thing, proven earliest, with a
   deliberate phone-app regression pass.
4. **Then**: B1/B2 in parallel with B3, converging on B6.
5. **Then**: C1/C2 (auth + offline), C3 tests.
6. **Ship gate**: C4, then C5 once A4 lands.

**On the session-persistence bug** (requirements Q6): resolved. It shipped in #131 and was verified
on device, so the "spurious mid-drive logout" scenario this section warned about is no longer live
and does not gate C5. C1 still swaps the root template on a genuine logout, because that path exists
regardless of the bug.

**On Swift 6** (see §0): every new file lands under `SWIFT_STRICT_CONCURRENCY: complete`. Design the
provider/coordinator for isolation up front — decide deliberately what is `@MainActor` and what is
`Sendable` — rather than annotating after the compiler complains.

---

## 5. Test Plan

### Automated (fits the existing gate)

- Unit tests for `CarPlayLibraryProvider` and `CarPlayCoordinator` (C3), protocol-mocked.
- `npm run validate:full` before every PR, per `CLAUDE.md`. CarPlay template code is UIKit-ish and
  won't be exercised by existing suites, hence the provider/coordinator split — it keeps the logic
  in unit-testable objects rather than in the scene delegate.
- Watch the **coverage ratchet**: new files must not drop coverage.

### Manual matrix (CarPlay Simulator — C4)

| Scenario                            | Expected                                                                  |
| ----------------------------------- | ------------------------------------------------------------------------- |
| Cold launch, logged in              | Tab bar with Library populated                                            |
| Cold launch, logged out             | "Sign in on your phone" info template                                     |
| **Cold launch mid session-restore** | Loading/neutral state — **not** a false "signed out" flash (finding #4)   |
| Select book from Library            | Playback starts, Now Playing shows correct title/artist/artwork           |
| Series → book → play                | Correct drill-down, playback starts                                       |
| Chapter controls, chapters present  | Prev/next chapter seek correctly                                          |
| Chapter controls, chapters absent   | Buttons hidden, no crash, playback still works                            |
| Phone + CarPlay both visible        | Play/pause/seek stays in sync both directions (AC4)                       |
| Logout on phone while CarPlay open  | CarPlay swaps to sign-in template, playback stops cleanly                 |
| Airplane mode, has downloads        | Downloaded tab playable                                                   |
| Airplane mode, no downloads         | Clear offline message, no empty mystery list                              |
| Archived book (`archiveStatus`)     | Doesn't hard-fail; ideally not offered or clearly marked                  |
| Disconnect/reconnect CarPlay        | Scene tears down and rebuilds without leaking or duplicating templates    |
| **Phone app regression (post-A1)**  | Launch, background/foreground, push deep link, mini-player all still work |

### Hardware (C5)

One pass on a real head unit or CarPlay dock. Simulator does not reproduce head-unit scroll
throttling, image scaling at real trait collections, or Siri/voice interactions.

---

## 6. Risks

| Risk                                                              | Likelihood         | Impact   | Mitigation                                                                                                       |
| ----------------------------------------------------------------- | ------------------ | -------- | ---------------------------------------------------------------------------------------------------------------- |
| Apple entitlement denied or slow                                  | Medium             | **High** | Submit A0 immediately; the entire build is dev-testable in the Simulator without it, so only shipping is blocked |
| `UIApplicationSupportsMultipleScenes: true` breaks the phone app  | Medium             | High     | A1 includes an explicit phone regression pass; keep A1+A2 a small revertable PR                                  |
| Scene manifest misconfiguration → black screen                    | Medium             | Medium   | Walking-skeleton approach (A2) surfaces it immediately                                                           |
| Chapters empty for CarPlay-initiated playback                     | **Certain, today** | Medium   | A3 refactor; B7 degrades gracefully                                                                              |
| Cover art missing/slow in lists                                   | Medium             | Low      | B1 placeholder + async fill                                                                                      |
| XcodeGen clobbering hand-edited `Info.plist`/entitlements         | Medium             | Medium   | All plist changes go in `project.yml`; entitlements stay a committed file (A4)                                   |
| ~~Session-persistence bug → mid-drive logout~~ — **fixed (#131)** | ~~Medium~~ Low     | High     | C1 still handles logout gracefully; the underlying bug is resolved, so this is no longer a ship gate             |

---

## 7. Acceptance Criteria (refined from the requirements doc)

- [ ] Apple CarPlay audio entitlement obtained; `BookVault.entitlements` and provisioning updated (A0, A4).
- [ ] CarPlay scene launches and shows a browsable tab bar: Library, Series, Downloaded, Continue (A2, B3–B6).
- [ ] Selecting a book starts playback via existing `AudioPlayerManager.shared`, with Now Playing showing correct metadata and artwork (B7).
- [ ] Transport controls work from CarPlay and stay in sync with the phone UI when both are visible (B7, AC4).
- [ ] Chapter navigation works when chapters are available and degrades cleanly when they aren't (A3, B7).
- [ ] Logged-out state shows a clear sign-in message; session-restore does **not** flash a false logged-out state (C1).
- [ ] Offline behavior is explicit: downloads playable, clear message when nothing is available (C2).
- [ ] **Phone app has no regression** from the multi-scene change (A1).
- [ ] Unit tests cover provider + coordinator logic; `npm run validate:full` passes; coverage ratchet holds (C3).
- [ ] Manual CarPlay Simulator matrix passes (C4); one real head-unit pass (C5).
- [ ] `docs/mobile/architecture.md` and `docs/STATUS.md` updated (C6).

---

## 8. Out of Scope (v1, unchanged)

- Search from CarPlay (`CPSearchTemplate`) — deferred despite `SearchManager` existing.
- Adding/removing books or series to/from library from CarPlay.
- Download/offline _management_ from CarPlay (playback of existing downloads **is** in scope).
- Account settings / login form inside CarPlay (impossible by design — no text entry while driving).
- Siri intents / `INPlayMediaIntent` voice control — natural v2.
- CarPlay `CPListItem` playback-progress indicators — nice-to-have, not v1.
