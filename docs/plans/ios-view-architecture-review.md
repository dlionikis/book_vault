# iOS View Architecture Review

> **Status**: Review / recommendations
> **Scope**: iOS view layer, state management, navigation, windowing
> **Created**: July 28, 2026
> **Companion**: [ios-mini-player-bottom-bar-plan.md](../archive/completed-plans/ios-mini-player-bottom-bar-plan.md)

---

## 1. Executive summary

The app is **structurally sound and idiomatic for iOS 15-era SwiftUI**, but it targets iOS 17.0 and
builds with Xcode 26. It is not using the modern APIs that its own deployment target already unlocks.
There is no architectural rot — no UIKit escape hatches, no `AnyView` soup, good protocol-based DI,
consistent MVVM where it matters. The gap is **API vintage, not design quality**.

Three findings actually matter. Everything else is optional polish.

| #     | Finding                                                                                | Severity        | Fixes a real bug?              |
| ----- | -------------------------------------------------------------------------------------- | --------------- | ------------------------------ |
| **1** | `@StateObject` holding singletons (38 sites)                                           | **High**        | Yes — latent, see §3.1         |
| **2** | `NavigationView` deprecated; no value-based navigation (10 production sites)           | **Medium-High** | Yes — blocks the mini-bar plan |
| **3** | `ObservableObject`/`@Published` instead of `@Observable` (26 classes, 77 `@Published`) | **Medium**      | No — perf only                 |
| 4     | `SWIFT_VERSION: '5.0'` — Swift 6 concurrency checking off                              | Medium          | Latent data races              |
| 5     | iPad in `TARGETED_DEVICE_FAMILY` but no adaptive layout                                | Low-Medium      | Yes, on iPad                   |
| 6     | Mixed `PreviewProvider` (10 files) and `#Preview` (16 files)                           | Low             | No                             |
| 7     | 4 `ObservableObject`s missing `@MainActor`                                             | Low-Medium      | Latent                         |

---

## 2. What the current architecture is

```
BookVaultApp (@main, WindowGroup)
  └── @UIApplicationDelegateAdaptor(AppDelegate)   ← background URLSession, push
  └── ContentView                                   ← auth gate + TabView + mini player
        ├── 6 online tabs / offline tab swap
        ├── each tab: its own NavigationView { ScrollView { … } }
        └── MiniPlayerView overlay (ZStack, top)
```

**Verified inventory:**

| Metric                                                             | Count         |
| ------------------------------------------------------------------ | ------------- |
| Swift files / total lines                                          | ~60 / 22,682  |
| `@Observable`                                                      | **0**         |
| `ObservableObject` classes                                         | 26            |
| `@Published` properties                                            | 77            |
| `@State` / `@StateObject` / `@ObservedObject`                      | 114 / 36 / 9  |
| `@EnvironmentObject`                                               | 2             |
| **Production** `NavigationView`                                    | **10**        |
| `NavigationStack`                                                  | 2             |
| `navigationDestination` / `NavigationPath` / `NavigationSplitView` | **0 / 0 / 0** |
| `NavigationLink(destination:)` (eager)                             | 25            |
| `.shared` singleton references                                     | ~130          |

> **Correction to a mid-review count**: an initial grep suggested 35 `NavigationView` sites. Most are
> inside `PreviewProvider` blocks. The real production number is **10** — a materially smaller
> migration than it first appeared.

### What is already good

- **Protocol-based DI** (`AudioPlayerManaging`, `AuthManaging`, `StorageManaging`, `NetworkMonitoring`,
  …) with `@MainActor` on the protocols — this is why the test suite can mock services, and it
  satisfies the `APIClientProtocol` hardening invariant in `CLAUDE.md` §3.
- **Generated OpenAPI models** kept in a separate, excluded-from-lint source group.
- **`BrowseConfigurations`** — a configuration-driven generic list/detail pair
  (`BrowseListView` + `BrowseDetailView` reused by Author/Narrator/Category/Series). This is genuinely
  good factoring and the right pattern; it prevented four near-duplicate screens.
- **No `AnyView` erasure, no `UIViewRepresentable` bridging** in the view layer.
- **Consistent MVVM** for the complex screens (`CatalogViewModel`, `LibraryViewModel`,
  `RestoreRequestsViewModel`); simple screens correctly skip the ceremony.

---

## 3. Findings in detail

### 3.1 `@StateObject` holding a singleton — **the real bug**

38 sites do this:

```swift
@StateObject private var themeManager = ThemeManager.shared      // ContentView.swift:27
@StateObject private var authManager  = AuthManager.shared       // BookVaultApp.swift:15
@StateObject private var searchManager = SearchManager.shared    // SearchView.swift:14
```

**Why this is wrong, not just unfashionable.** `@StateObject`'s contract is _"this view owns and
creates this object; keep it alive across body re-evaluations."_ Its autoclosure initializer is
evaluated **exactly once** per view identity, and SwiftUI takes ownership of the result.

Handing it a pre-existing singleton mismatches that contract in two ways:

1. **`.shared` is evaluated on every `body` call** even though the result is discarded after the
   first. For any singleton whose `init` has side effects (`NetworkMonitor` starts an `NWPathMonitor`;
   `SyncManager.startMonitoring()`), this is wasted work at best.
2. **Ownership is a lie.** If a view holding `@StateObject … .shared` is ever destroyed and
   recreated with a _new_ identity, SwiftUI may drop its subscription while the singleton lives on.
   The symptom is the classic "view stops updating until I switch tabs and come back."

`ContentView` mixes both spellings for the same category of object — `@StateObject` for
`themeManager`/`networkMonitor`/`deepLinkManager` but `@ObservedObject` for `audioPlayer` (lines
27–30). There is no principled reason for the split; it is drift.

**Fix (mechanical, no behavior change intended):** singletons a view _observes but does not own_ should
be `@ObservedObject` — or better, injected via `.environmentObject` once at the root. This is worth
doing **independently of any modernization**, because it is correctness, not style.

### 3.2 Navigation — deprecated container, and no value-based routing

`NavigationView` has been soft-deprecated since iOS 16. All 10 production sites are the root of a
tab. Alongside that:

- **`navigationDestination`: 0 uses.** All 25 navigations are `NavigationLink(destination:)`, the
  eager form. Inside a `ScrollView`+`LazyVGrid`, the destination view's `init` runs for **every
  visible cell**, not on tap. `BookDetailView` is 851 lines; `CatalogView` builds one per grid item
  ([CatalogView.swift:102](../../ios/BookVault/Views/Books/CatalogView.swift#L102)). This is real
  scroll-time cost.
- **`NavigationPath`: 0 uses.** No programmatic deep-link routing. The push-notification deep link
  works around this by presenting a **sheet** instead of pushing
  ([ContentView.swift:154](../../ios/BookVault/ContentView.swift#L154)) — a workaround forced by the
  navigation architecture, not a design preference.

**This finding is load-bearing for the mini-player change.** `NavigationView`'s safe-area propagation
into pushed destinations is exactly the risk flagged in the bottom-bar plan's Phase 3. Migrating to
`NavigationStack` de-risks that work rather than competing with it.

### 3.3 `@Observable` — the headline modernization

Zero adoption. `@Observable` (Observation framework) is iOS 17+, which the project **already
requires**, so this is available today at no compatibility cost.

The benefit is not aesthetic. With `ObservableObject`, **any** `@Published` change re-renders **every**
view observing that object. With `@Observable`, SwiftUI tracks per-property reads and re-renders only
views that actually read the changed property.

The payoff is concentrated in one place: `AudioPlayerManager` (1,102 lines) publishes `currentTime`,
which updates several times per second during playback. Today every view observing it re-renders on
every tick — `MiniPlayerView`, `NowPlayingView`, and `BookDetailView`'s player section. Under
`@Observable`, a view reading only `isPlaying` and `currentBook` would not re-render on a
`currentTime` tick at all.

**The DI constraint to respect:** the protocols are declared `protocol AudioPlayerManaging:
ObservableObject`. `@Observable` classes do not conform to `ObservableObject`. So migration must drop
the `ObservableObject` refinement from the protocols and update mocks — the protocol abstraction
itself survives (and must, per the `CLAUDE.md` invariant). **Migrate service-by-service, not
big-bang.**

### 3.4 `SWIFT_VERSION: '5.0'`

Swift 6 language mode is off, so compile-time data-race checking is off. Given the concurrency
surface here — background `URLSession`, `AVPlayer` observers, `NWPathMonitor`, push callbacks — this
is where real races hide. Supporting evidence: **4 `ObservableObject` services lack `@MainActor`**
(`AppIconManager`, `PlaybackSettings`, `ProgressManager`, `ThemeManager`) while 68 `@MainActor`
annotations exist elsewhere. `ThemeManager` and `PlaybackSettings` publish state that drives UI, so
they should be main-actor-isolated.

Intermediate step: set `SWIFT_UPCOMING_FEATURE_*` flags or Swift 5 + strict concurrency = `targeted`
to surface warnings without a hard migration.

### 3.5 iPad: declared but not designed for

`TARGETED_DEVICE_FAMILY: '1,2'` (project.yml:58) ships to iPad, and landscape is enabled. But there
is **no `NavigationSplitView`, no size-class adaptation, and no `.horizontalSizeClass` reads**. On an
11" iPad the `.adaptive(minimum: 150, maximum: 200)` grid works acceptably, but a full-width
`NavigationView` tab layout is a stretched-phone experience.

Also: `UIApplicationSupportsMultipleScenes: false`, so no iPad multi-window/Stage Manager support.

**Decide deliberately:** either invest in `NavigationSplitView` for iPad, or drop to
`TARGETED_DEVICE_FAMILY: '1'` and stop claiming support. Shipping an unconsidered iPad build is the
worst of the three options.

### 3.6 Smaller items

- **Mixed preview styles** — 10 files on legacy `PreviewProvider`, 16 on the `#Preview` macro. The
  legacy ones carry `// periphery:ignore` comments to placate dead-code analysis; the macro needs no
  such workaround. Convert opportunistically.
- **`NavigationView` inside previews** — harmless, but these are what inflated the initial count;
  converting them keeps future audits honest.
- **`BookDetailView` at 851 lines** with 4 nested view structs and their own `@StateObject`s. Not
  urgent, but it is the file most likely to resist change.
- **`.ignoresSafeArea()` in `NowPlayingView`** ([line 34](../../ios/BookVault/Views/Player/NowPlayingView.swift#L34)) — verify against the new bottom bar.

---

## 4. Recommended sequence

Ordered so each step de-risks the next, and so the mini-player feature is not blocked.

### Step 0 — Fix `@StateObject` → `@ObservedObject` on singletons _(do first, standalone PR)_

Mechanical, ~38 one-line edits, no API migration. Fixes latent update bugs and removes repeated
`.shared` evaluation. **Highest value per unit of risk in this entire review.**

### Step 1 — `NavigationView` → `NavigationStack` _(standalone PR, before the mini bar)_

Only 10 production sites. Do this **before** the bottom-bar change so safe-area insets propagate
predictably into pushed destinations — it converts the bottom-bar plan's biggest risk into a
non-issue. Keep `NavigationLink(destination:)` for now; changing containers and routing at once
makes regressions hard to attribute.

### Step 2 — Ship the mini-player bottom bar

Per [ios-mini-player-bottom-bar-plan.md](../archive/completed-plans/ios-mini-player-bottom-bar-plan.md), now on a modern
navigation container. Phase 4 of that plan (the conditional `NavigationStack` migration) becomes
unnecessary — it is absorbed by Step 1.

### Step 3 — `navigationDestination` + `NavigationPath` for value-based routing

Removes eager destination construction in grids, and lets the push-notification deep link **push**
instead of presenting a sheet.

### Step 4 — `@Observable` migration, service by service

Start with **`AudioPlayerManager`** — highest render-churn, clearest win. Per service: `@Observable`
on the class, drop `@Published`, drop `: ObservableObject` from its protocol, `@StateObject`/
`@ObservedObject` → plain `let`/`@State`, `@Bindable` where two-way binding is needed, update mocks.
Run `validate:ios` per service.

### Step 5 — Swift 6 / strict concurrency

Add `@MainActor` to the 4 unannotated services, enable targeted strict-concurrency warnings, then
consider Swift 6 language mode.

### Step 6 — Decide iPad

`NavigationSplitView` + size-class adaptation, **or** drop iPad from the device family.

---

## 5. What I would _not_ change

- **The `BrowseConfigurations` pattern.** Configuration-driven generic list/detail is the right call
  and already prevents four duplicate screens.
- **The protocol-based DI layer.** It must survive the `@Observable` migration (per the `CLAUDE.md`
  hardening invariants); adapt the protocols, do not delete them.
- **MVVM selectively applied.** Not every screen needs a view model, and this codebase correctly
  skips it for simple ones. Resist uniformity for its own sake.
- **`@UIApplicationDelegateAdaptor`.** Still the correct and supported way to get background
  `URLSession` and push callbacks in a SwiftUI lifecycle app.
- **The singleton service layer itself.** Converting ~130 `.shared` references to full environment
  injection is a large, risky refactor with modest payoff. Fixing the _wrapper_ (Step 0) captures most
  of the benefit for a fraction of the risk.

---

## 6. Open questions

1. **iPad**: real support, or drop the device family? This is a product decision that gates Step 6.
2. **Appetite for Steps 3–5?** Steps 0–2 are clearly worth it. Steps 3–5 are healthy modernization
   with no user-visible change beyond smoother playback rendering — reasonable to defer.
3. **Minimum iOS version** — staying at 17.0 keeps `@Observable` available. Raising to 18/26 would
   unlock `tabViewBottomAccessory` and the newer tab-bar behaviors, which would change the
   mini-player design conversation entirely.
