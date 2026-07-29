# iOS Modernization — Sequencing Decision

> **Status**: Recommendation
> **Created**: July 28, 2026
> **Companions**: [ios-view-architecture-review.md](ios-view-architecture-review.md) ·
> [ios-mini-player-bottom-bar-plan.md](ios-mini-player-bottom-bar-plan.md)

---

## 1. The measurement that decides this

Rather than estimate the Swift 6 blast radius, I compiled the app under Swift 6 with complete
strict-concurrency checking:

```bash
xcodebuild -project BookVault.xcodeproj -scheme BookVault -sdk iphonesimulator \
  -configuration Debug SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete build
```

**Result: 4 errors. Zero concurrency warnings. All 4 errors are in generator-owned files.**

```
Generated/Models/GetCategory200Response.swift:15         static property 'levelRule' …
Generated/Models/GetDownloadHistory200Response.swift:15  static property 'dailyCountRule' …
Generated/Models/GetLibrary200Response.swift:15          static property 'totalRule' …
Generated/Models/GetProgress200Response.swift:15         static property 'positionSecondsRule' …
```

All four are the same single issue:

> `static property 'X' is not concurrency-safe because non-'Sendable' type 'NumericRule<…>' may have
shared mutable state`

**Your hand-written code — all ~22,000 lines of it, including `AudioPlayerManager`,
`DownloadManager`, `APIClient`, and every view — is already Swift 6 clean.** The 68 existing
`@MainActor` annotations and the protocol-based DI did their job.

This inverts the recommendation I gave in the review, where I ranked Swift 6 as a medium-severity
item with unbounded scope. It is neither. **It is a one-line fix in a template.**

---

## 2. Answering your question directly

> Should the Swift 6 upgrade be part of this, or its own plan? Or upgrade + fixes in one plan, and
> mini-player rework as a follow-up?

**Your instinct is right: fixes + upgrade in one plan, mini-player as a follow-up.** Two plans, not
three. Swift 6 is now small enough that a separate plan would be more overhead than the work itself.

The reason to keep the mini player separate isn't size — it's **attribution**. Plan A is
all invisible-by-design refactoring: if the test suite is green and the app looks identical, it
worked. Plan B deliberately changes layout on every screen. Bundling them means any layout oddity
has two possible causes, and `NavigationStack` migration + a new bottom safe-area inset are _both_
plausible culprits for the same class of bug. Keeping them apart makes a bisect trivial.

---

## 3. The one real obstacle: generated code

The Swift 6 errors are in files that **cannot be hand-fixed**. Three mechanisms conspire:

1. `scripts/generate-swift.sh:30` runs `rm -rf "$OUTPUT_DIR"/*` — any hand edit is deleted on the
   next `npm run api:generate:swift`.
2. `package.json:53` — `api:check-drift:swift` regenerates and runs `git diff --exit-code` against
   `ios/BookVault/Generated/Models/`. A hand edit **fails CI** as drift.
3. The files are committed (not gitignored), so the broken state is what CI compiles.

So the fix must live where generation can reproduce it. Options, in preference order:

### Option 1 — Make `NumericRule` `Sendable` via a template override _(recommended)_

`NumericRule` is declared once in
[Validation.swift:15](../../ios/BookVault/Generated/Models/Validation.swift#L15):

```swift
public struct NumericRule<T: Comparable & Numeric> {
```

Its stored properties are all immutable value types, so it is _semantically_ `Sendable` already —
it just never says so. Adding the conformance fixes all 4 errors at the root:

```swift
public struct NumericRule<T: Comparable & Numeric & Sendable>: Sendable {
```

`generate-swift.sh:9` already declares `TEMPLATE_DIR="scripts/swift-templates"` — but **the directory
does not exist and the variable is never passed to the generator.** The hook is a stub. So this
option means genuinely wiring it up:

- Create `scripts/swift-templates/`, add the `Validation.mustache` override from the `swift5`
  generator, patched with the `Sendable` conformance.
- Pass `-t "$TEMPLATE_DIR"` in the generate command.
- Pin compatibility with the generator version already pinned in `openapitools.json` (7.23.0).

This is the durable fix — it survives regeneration and keeps the drift check meaningful.

### Option 2 — Post-generation patch step in the script

Append a `sed`/patch step after generation that adds the conformance. Simpler than templates, but
brittle: a generator upgrade that reformats the declaration silently breaks the patch.

### Option 3 — Exclude generated models from Swift 6 checking

Keep the generated group at Swift 5 while app code moves to 6. XcodeGen can set `SWIFT_VERSION` per
source group. Pragmatic escape hatch if templating fights back, but it leaves a permanent
non-uniformity in the build.

> Also update `generate-swift.sh:88`, which hardcodes `swiftformat … --swiftversion 5.9`.

---

## 4. Recommended plan structure

### Plan A — "View-layer correctness + Swift 6" _(one PR per step, one plan)_

Ordered so each step is independently revertible:

| Step      | Work                                                                                                                            | Size              | Risk                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------- | ---------------------- |
| ✅ **A0** | Drop iPad: `TARGETED_DEVICE_FAMILY: '1'` — **done**                                                                             | 1 line            | Very low               |
| ✅ **A1** | `@StateObject` → `@ObservedObject` on the singleton sites — **done** (32 sites)                                                 | 32 one-line edits | Very low               |
| ✅ **A2** | `@MainActor` on the 4 unannotated services (`AppIconManager`, `PlaybackSettings`, `ProgressManager`, `ThemeManager`) — **done** | Small             | Low                    |
| **A3**    | `NumericRule: Sendable` via template override; wire up `TEMPLATE_DIR`; bump swiftformat `--swiftversion`                        | Small but fiddly  | Medium — build tooling |
| **A4**    | Flip `SWIFT_VERSION: '6.0'` + `SWIFT_STRICT_CONCURRENCY: complete` in `project.yml`; `xcodegen generate`                        | 2 lines           | Low _once A3 lands_    |
| **A5**    | Convert the 10 production `NavigationView` → `NavigationStack`                                                                  | 10 sites          | Medium — the real work |
| **A6**    | _(optional)_ Legacy `PreviewProvider` → `#Preview` in the 10 remaining files; drops the `periphery:ignore` workarounds          | Small             | Very low               |

**Dependencies** — only one hard ordering constraint exists:

```
A3 ──▶ A4        (language mode breaks the build unless generated code is Sendable first)

A0, A1, A2, A5, A6   independent — any order, any time
A5 ──▶ Plan B        (recommended, not required)
```

**A5 is the step that actually needs care**, and it is worth restating why it's in this plan at all:
it converts the mini-player plan's single biggest risk (`NavigationView`'s unreliable safe-area
propagation into pushed destinations) into a non-issue _before_ that work starts.

Gate: `npm run validate:full` before each PR, per `CLAUDE.md` §2.

---

### Implementation notes — A0 + A1 + A2 (shipped July 28, 2026)

Delivered as one PR. `validate:full` green: web 525, DB 18, contract 286, iOS 698 tests, both drift
checks clean, SwiftLint `--strict` clean.

Four things differed from the plan and are worth recording:

1. **A1 was 32 sites, not 38.** The review's "38" counted all singleton-holding wrappers; 6 were
   already `@ObservedObject`. 31 view sites plus `BookVaultApp` were converted. The four genuinely
   view-owned objects (`CatalogViewModel`, `LibraryViewModel`, `RestoreRequestsViewModel`,
   `ChapterManager`) correctly kept `@StateObject`.

2. **`BookVaultApp` was converted after all.** The plan called it "defensible as-is" since the `App`
   struct is never recreated. Converted for consistency — `.environmentObject(authManager)` behaves
   identically either way, and leaving one outlier would invite the same drift back.

3. **A2 also required a test-side fix.** Making `ThemeManager` `@MainActor` broke
   `ThemeManagerRealTests`, a `nonisolated` `XCTestCase` touching now-isolated state — **the app still
   built; only the test target failed.** Fixed by marking the class `@MainActor`, matching the existing
   convention in `SyncManagerTests`. Expect the same for any future service-isolation change: check the
   test target, not just the app.

4. **`ProgressManager` got simpler, and one latent race closed.** It already annotated all 6 members
   `@MainActor` individually; hoisting to the class let those be removed. More importantly its mutable
   `progressCache` was **not** previously isolated — that dictionary was the one genuine data race in
   the four services.

**Also fixed (unplanned):** XcodeGen defaults `TARGETED_DEVICE_FAMILY` per target, so the **test
bundle** still declared `'1,2'` after A0. Set explicitly on both targets; all 4 build configurations
now report `1`.

**Not yet verified — needs a device/simulator pass.** A1 fixes a _latent_ bug, so a green suite does
not prove it. Manually exercise: tab switching, background/foreground, network toggle, theme change,
and mini-player tracking during playback.

---

### A0 — Drop iPad support

**Decision made (July 28, 2026): remove iPad support until there is appetite to design for it
properly.** Rationale: the app ships to iPad today via `TARGETED_DEVICE_FAMILY: '1,2'` with **zero**
adaptive layout — no `NavigationSplitView`, no size-class reads, no idiom checks anywhere in the view
layer (verified: the only `regular` match in the codebase is a `fontWeight`). That is a
stretched-phone experience, and shipping it unconsidered is worse than not shipping it.

**Verified as safe.** The app is distributed **ad-hoc**, not via the App Store —
`ExportOptions.plist` in the production archives shows `method: release-testing`. So this change has
**no App Store review implication and no existing-iPad-user impact**. (On an App Store app, dropping a
device family is a user-visible removal; here it is not.)

**Change** — [project.yml:61](../../ios/project.yml#L61):

```diff
-        TARGETED_DEVICE_FAMILY: '1,2'
+        TARGETED_DEVICE_FAMILY: '1'
```

Then `cd ios && xcodegen generate`.

**Deliberately unchanged:**

- **Orientation stays as-is.** `UISupportedInterfaceOrientations` keeps portrait + both landscapes
  (project.yml:42–45). iPhone landscape is still valid and users may rely on it; this step is about
  device family only. Note the mini-player bottom bar (Plan B, requirement L6) must still be verified
  in iPhone landscape.
- **`UIApplicationSupportsMultipleScenes: false`** — already correct, and more so now.
- **No code deletion.** There is no iPad-specific code to remove, which is precisely the problem
  being closed out.

**Verification:** confirm the iPad destination disappears from the Xcode scheme's run destinations,
and that `npm run validate:ios` still passes (the test target's `deploymentTarget` is untouched).

**Reversible** by restoring `'1,2'` — no code is lost, so a future iPad effort starts from a
deliberate design decision rather than an accident.

---

### A1 — `@StateObject` → `@ObservedObject` on singletons

**Rule**: if a view does not _create_ the object, it must not use `@StateObject`. All 38 sites hold a
`.shared` singleton, so all 38 become `@ObservedObject`.

```diff
-    @StateObject private var themeManager = ThemeManager.shared
+    @ObservedObject private var themeManager = ThemeManager.shared
```

**Two sites need judgment, not a blind swap:**

1. **[BookVaultApp.swift:15](../../ios/BookVault/BookVaultApp.swift#L15)** — `@StateObject private var
authManager = AuthManager.shared`, injected via `.environmentObject(authManager)`. The `App` struct
   is a genuine root-owner and is never recreated, so this one is _defensible_ as-is. Prefer
   `@ObservedObject` for consistency, but this is the one site where leaving it would not be a bug.
2. **[ContentView.swift:27-30](../../ios/BookVault/ContentView.swift#L27-L30)** — the drift source:
   three `@StateObject` + one `@ObservedObject` for the same category of object. All four → `@ObservedObject`.

**Do not** change `@StateObject` on genuinely view-owned objects — the view models
(`CatalogViewModel`, `LibraryViewModel`, `RestoreRequestsViewModel`) are correctly `@StateObject`
because the view _does_ create them. Only `.shared` sites change.

**Verification**: this is a semantics fix for a _latent_ bug, so tests passing does not prove much.
Manually exercise the case the bug affects — switch tabs repeatedly, background/foreground the app,
toggle network, and confirm views still update (theme changes apply, network banner reacts, mini
player tracks playback).

---

### A5 — `NavigationView` → `NavigationStack`

Ten production sites. Verified per-screen complications:

| Screen                | `.toolbar` | `navigationTitle` | Notes                                        |
| --------------------- | ---------- | ----------------- | -------------------------------------------- |
| `CatalogView`         | 1          | 3                 | 3 titles = conditional branches; verify each |
| `LibraryView`         | 2          | 1                 |                                              |
| `DownloadsView`       | 1          | 1                 |                                              |
| `ChapterListView`     | 1          | 1                 | Sheet-presented                              |
| `SearchView`          | 0          | 1                 | Custom search UI, **not** `.searchable`      |
| `BrowseView`          | 0          | 1                 |                                              |
| `SettingsView`        | 0          | 1                 | `Form`                                       |
| `OfflineModeView`     | 0          | 1                 |                                              |
| `PlaybackSpeedPicker` | 0          | 1                 | Sheet-presented                              |
| **`LoginView`**       | 0          | **0**             | **Delete the container — see below**         |

**Good news: zero `.searchable` usage** anywhere in the app. `.searchable` inside a migrated
container is the classic source of migration regressions; its absence removes that whole risk class.
`SearchView` uses custom search UI instead.

**`LoginView` is a deletion, not a migration.** Its `NavigationView`
([LoginView.swift:26](../../ios/BookVault/Views/Auth/LoginView.swift#L26)) wraps a static `VStack`
with no `navigationTitle`, no toolbar, and no `NavigationLink`. It provides nothing. Remove the
wrapper rather than converting it — but check it wasn't load-bearing for layout (a `NavigationView`
imposes its own safe-area behavior, so verify the logo/spacing before and after).

**Keep `NavigationLink(destination:)` as-is in this step.** Converting to
`navigationDestination(for:)` is a _separate_ change (deferred below). `NavigationStack` supports the
existing eager links unchanged, so mixing the two migrations only makes regressions harder to
attribute.

**The thing to actually watch:** `NavigationStack` does not accept the two-column behavior
`NavigationView` had on wide layouts. Since A0 drops iPad, this stops mattering — **which is why A0
before A5 is convenient**, though not strictly required.

**Verification per screen**: title renders (and correct display mode), toolbar items present and
tappable, push → detail → back works, and — because Plan B depends on it — **safe-area insets
propagate into pushed destinations**.

---

### Plan B — Mini-player bottom bar _(follow-up)_

[ios-mini-player-bottom-bar-plan.md](ios-mini-player-bottom-bar-plan.md), with two amendments once
Plan A lands:

- **Phase 4 is deleted.** The conditional `NavigationStack` migration is absorbed by A5.
- **Phase 3's per-screen occlusion audit stays** — still the core of the work, but now verifying a
  modern container rather than probing a deprecated one's edge cases.

### Deliberately _not_ in either plan

- **`@Observable` migration.** Still worthwhile (the `AudioPlayerManager.currentTime` re-render churn
  is real), but it is a _performance_ refactor touching 26 classes and every protocol in the DI layer.
  It has no correctness urgency and no user-visible payoff beyond smoother rendering. **Its own plan,
  later, service by service.**
- **`navigationDestination` / `NavigationPath` routing.** Natural successor to A5 and would let the
  deep link push instead of presenting a sheet — but changing containers _and_ routing in one pass
  makes regressions hard to attribute. Sequence it after Plan B.
- **iPad adaptive layout.** Resolved: **iPad support is being removed** (A0). Any future
  `NavigationSplitView` work starts from a deliberate decision to re-add the device family.

---

## 5. Note on A1 vs. a future `@Observable` migration

A1 fixes ~38 `@StateObject` → `@ObservedObject` lines. A later `@Observable` migration would touch
many of those same lines again (to plain `let` / `@State` / `@Bindable`). That overlap is real and I
don't want to pretend otherwise.

It is still the right order. A1 fixes a **live correctness bug** — mismatched ownership semantics that
can silently drop view updates — in an afternoon. `@Observable` is a perf refactor that may be weeks
out or may never be prioritized. Fixing a real bug now and re-touching the line later is correct;
deferring the bug fix to avoid duplicate work is not.

---

## 6. Readiness

**Ready to implement: A0, A1, A2, A5, A6.** Each has a concrete change, a verification step, and no
unresolved dependency.

**A3 has one open decision** (below) that should be settled before starting it — the _approach_ is
undecided, not the goal. A4 is trivial and gated on A3.

### The one remaining decision — A3's generated-code fix

Option 1 (template override) is the durable answer and my recommendation, but it means building the
template infrastructure that `generate-swift.sh` currently only pretends to have (`TEMPLATE_DIR` is
declared at line 9, never created, never passed to the generator). If you'd rather not take on
generator templating, **Option 3** (per-group `SWIFT_VERSION`) gets app code to Swift 6 today with one
documented exception — a reasonable trade for a personal project.

Suggested tactic: **attempt Option 1, time-box it, fall back to Option 3.** A3 is the only step with
meaningful unknowns, and it blocks nothing except A4.

### Settled

- **iPad** — removing it (A0). Verified safe: ad-hoc distribution, no App Store implication.
- **`SWIFT_STRICT_CONCURRENCY: complete` from the start** — yes. The measurement shows the code passes
  it today; it is much harder to adopt later once code drifts.
- **Plan A / Plan B split** — confirmed, for attribution rather than size (§2).

### Suggested first PR

**A0 + A1 + A2 together.** All three are low-risk, none depend on the others, and combined they are
still a small diff. That clears the trivial work in one pass and leaves A3/A4 (build tooling) and A5
(the real work) as focused PRs.
