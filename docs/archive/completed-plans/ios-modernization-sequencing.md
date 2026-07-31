# iOS Modernization — Sequencing Decision

> **Status**: ✅ **Complete.** All of Plan A (A0–A6) shipped, plus Plan B (#140) and Plan C (#142).
> **Created**: July 28, 2026
> **Companions**: [ios-view-architecture-review.md](ios-view-architecture-review.md) ·
> [ios-mini-player-bottom-bar-plan.md](../archive/completed-plans/ios-mini-player-bottom-bar-plan.md)

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

> ⚠️ **This measurement was incomplete — do not rely on it.** It built only the app target via
> command-line overrides and missed `DebugLogger`, `SystemKeychain`, and 6 structural errors in
> generated `URLSessionImplementations.swift`. The first two are fixed (A3); the third is
> [Plan C](../archive/completed-plans/ios-swift6-generated-networking-plan.md) and is the reason A4 is now
> the last step rather than a trivial 2-line flip. Kept here as written because the flawed method is
> itself the lesson: flip the real build setting and compile **both** targets.
>
> The claim that "hand-written code is already Swift 6 clean" did hold up — the two misses were a
> mutable global and a missing conformance, both one-liners. And the `URLSessionImplementations`
> errors turned out to be in **unused** code, so the conclusion (Swift 6 is close) was right for the
> wrong reasons.

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

| Step      | Work                                                                                                                            | Size                                                     | Risk                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------- |
| ✅ **A0** | Drop iPad: `TARGETED_DEVICE_FAMILY: '1'` — **done**                                                                             | 1 line                                                   | Very low                               |
| ✅ **A1** | `@StateObject` → `@ObservedObject` on the singleton sites — **done** (32 sites)                                                 | 32 one-line edits                                        | Very low                               |
| ✅ **A2** | `@MainActor` on the 4 unannotated services (`AppIconManager`, `PlaybackSettings`, `ProgressManager`, `ThemeManager`) — **done** | Small                                                    | Low                                    |
| ✅ **A3** | `Sendable` validation rules via generator template override — **done**                                                          | Small but fiddly                                         | Medium — build tooling                 |
| ✅ **A5** | Convert the 10 production `NavigationView` → `NavigationStack` — **done** (+25 preview sites)                                   | 10 sites                                                 | Medium — the real work                 |
| ✅ **A6** | Legacy `PreviewProvider` → `#Preview` in 10 files; dropped all 10 `periphery:ignore` workarounds — **done**                     | Small                                                    | Very low                               |
| ✅ **A4** | Flip `SWIFT_VERSION: '6.0'` + `SWIFT_STRICT_CONCURRENCY: complete` on all 3 targets — **done** (July 31, 2026)                  | 3 protocols + `APIClient` isolation + 40 test-file fixes | Medium — touched the auth/refresh path |

**A4 moved to the end.** It was originally "2 lines, low risk, gated on A3." A3 landed and A4 was
still blocked — on generated **URLSession** code, a materially bigger problem than the validation
rules (see [Plan C](../archive/completed-plans/ios-swift6-generated-networking-plan.md)).

**Update (July 30, 2026): Plan C shipped (#142), and A4 is _still_ not a 2-line flip.** Removing the
generated request layer cleared every generated blocker, but flipping the language mode then surfaced
app-code ones. Plan C also shipped `Sendable` generated models (needed by `MockData`'s `static let`
fixtures), so nothing generated remains in A4's way.

**Measured on merged `main` (July 31, 2026): 11 errors across 4 files.**

| File                          | Errors |
| ----------------------------- | ------ |
| `LibraryManager.swift`        | 5      |
| `ProgressManager.swift`       | 4      |
| `NotificationRegistrar.swift` | 2      |

⚠️ **Do not trust a single build's error count here** — this was first reported as "2 errors," which
was wrong. The compiler stops at the first failing file, so one build under-reports. The 11 above is
the union of four consecutive builds, and it may still grow as each fix lets the compiler reach
further. Same lesson as §1's flawed measurement, in a new disguise.

They are not 11 independent problems. Three DI protocols need `Sendable` — `APIClientProtocol` (most
of them), `CoverCaching`, and `NotificationAuthorizing` — plus one distinct case at
`LibraryManager.swift:159`, a closure passed to `Task.detached` that captures main-actor state.

The substantive work is `APIClient`: it holds `accessToken` and two handler closures
(`forceLogoutHandler`, `tokenRefreshHandler`) as unisolated `var`s, so the conformance is not free.
Isolating them means touching the token-refresh path that PR #131 just fixed — which is why A4 is
deliberately its own PR.

**Dependencies:**

```
A3 ✅ ──▶ Plan C ✅ ──▶ APIClient Sendable ──▶ A4

A0 ✅, A1 ✅, A2 ✅, A5 ✅, A6 ✅   independent — any order, any time
A5 ──▶ Plan B ✅             (recommended, not required)
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

### Implementation notes — A3 (shipped July 29, 2026)

Template override worked as hoped. `validate:ios` green: 698 tests, Swift drift check clean,
SwiftLint `--strict` clean.

1. **The `TEMPLATE_DIR` hook is now real.** It was declared at `generate-swift.sh:9` but the directory
   never existed and `-t` was never passed. Added `-t "$TEMPLATE_DIR"` plus a hard precondition: if
   `Validation.mustache` is missing, generation **fails** rather than silently emitting code that
   won't compile under Swift 6.

2. **All three rule structs got `Sendable`, not just `NumericRule`.** `StringRule` is also held as
   `static let` (2 sites) and only escaped erroring because it has no generic parameter for the
   checker to complain about. Fixing one and not the others would have been a latent repeat.

3. **Correction to §3's reasoning.** That section said the rule structs' fields are "immutable value
   types." They are declared `var`. The `Sendable` conformance is still sound — `static let` copies
   are not shared mutable state — but the stated justification was wrong.

4. **Two unplanned concurrency fixes**, both improvements independent of Swift version:
   - `DebugLogger.verboseLoggingEnabled` was a nonisolated mutable global read from ~459 call sites
     across every actor. Now `NSLock`-backed, matching `FileExtensionStorage` in `DownloadManager`.
     Only the test suite writes it.
   - `SystemKeychain` — `final` and stateless, so it declares `Sendable` directly.

5. **`--swiftversion` bumps deliberately reverted.** Both `ios/.swiftformat` and
   `generate-swift.sh:99` stay at 5.9. Telling swiftformat 6.0 while the compiler is on 5.0 is
   incoherent; these move with A4.

**The A4 measurement in §1 was incomplete — see Plan C.** It reported "4 errors, all `NumericRule`."
Actually flipping the flag surfaced `DebugLogger`, `SystemKeychain`, and **6 structural errors in
generated `URLSessionImplementations.swift`**. The original probe built only the app target and did
not exercise all strict-concurrency paths. Lesson: measure by flipping the real setting and building
**both** targets, not with command-line overrides on one.

---

### Implementation notes — A5 (shipped July 29, 2026)

`NavigationView` is now **entirely absent** from the codebase. `validate:full` green: web 525, DB 18,
contract 286, iOS 698, both drift checks clean, SwiftLint `--strict` clean, no deprecation warnings.

Two corrections to what this section predicted:

1. **`CatalogView` has one production `navigationTitle`, not three.** The table below said 3; the other
   two are inside `PreviewProvider` blocks. Same original error as the `NavigationView` count.

2. **`LoginView` was a deletion, and the plan's reasoning was incomplete.** It correctly called this a
   deletion rather than a conversion, but described the container as providing "nothing." It actually
   carried `.navigationBarHidden(true)` — so it added a nav bar and then hid it. Both lines are gone.
   Verified with `git diff -w`: ignoring indentation, the change is exactly **3 deleted lines**, no
   logic touched. Confirmed on the simulator that the layout is unchanged and the offline escape hatch
   (added in #132) still renders under its `!networkMonitor.isConnected` condition.

**Also converted: the 25 preview-block occurrences.** Not strictly required, but these are what
inflated the original count from 10 to 35 and would have kept doing so on every future audit. Leaves
zero `NavigationView` in the repo, so the grep is now trustworthy.

**Verification gap — be honest about this one.** The suite proves nothing about navigation UI: there is
**no UI test target** (no `XCUIApplication` anywhere in `BookVaultTests/`). What was actually verified:
a clean build with no deprecation warnings, 698 unit tests, and a simulator launch confirming the
login screen renders correctly with safe-area insets respected. **Not** verified automatically: push →
detail → back on each of the 9 tab screens, and safe-area propagation into pushed destinations — which
is the entire reason A5 precedes Plan B. Simulator tap automation was unavailable (no `idb`), so
**this needs the manual pass in §5 of the mini-player plan before Plan B relies on it.**

**Remedy proposed:** [ios-ui-testing-plan.md](../archive/completed-plans/ios-ui-testing-plan.md) — an XCUITest target covering
five smoke flows, including the push → detail → back flow this gap describes. Recommended **before**
Plan B so the mini-player change ships with automated verification rather than manual passes.

### Implementation notes — A6 (shipped July 30, 2026)

All 10 legacy `PreviewProvider` structs converted to the `#Preview` macro. Net **-48 lines** across 10
files. `validate:ios` green: 698 tests, drift clean, SwiftLint `--strict` clean.

**The real win is deleting a workaround.** Each `PreviewProvider` needed a
`// periphery:ignore - Used by Xcode Previews` comment to stop dead-code analysis flagging it. The
`#Preview` macro needs none, so **all 10 suppressions are gone.** (The 5 remaining `periphery:ignore`
comments in `MockData.swift` are for mock fixtures — a different purpose, correctly left alone.)

Two shapes existed: bare sibling views with `.previewDisplayName(...)`, and a `Group { }` wrapper.
Both become separate `#Preview("Name") { }` blocks, matching the convention already used in
`CatalogView` and `LibraryView`. The `Group` cases (`SearchView`, `BrowseView`) needed hand-fixing —
an automated split mishandled their leading comments and produced an empty first block.

`PreviewProvider` is now absent from the codebase.

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

| Screen                | `.toolbar` | `navigationTitle` | Notes                                      |
| --------------------- | ---------- | ----------------- | ------------------------------------------ |
| `CatalogView`         | 1          | 1                 | ~~3 titles~~ — 2 of the 3 were in previews |
| `LibraryView`         | 2          | 1                 |                                            |
| `DownloadsView`       | 1          | 1                 |                                            |
| `ChapterListView`     | 1          | 1                 | Sheet-presented                            |
| `SearchView`          | 0          | 1                 | Custom search UI, **not** `.searchable`    |
| `BrowseView`          | 0          | 1                 |                                            |
| `SettingsView`        | 0          | 1                 | `Form`                                     |
| `OfflineModeView`     | 0          | 1                 |                                            |
| `PlaybackSpeedPicker` | 0          | 1                 | Sheet-presented                            |
| **`LoginView`**       | 0          | **0**             | **Delete the container — see below**       |

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

[ios-mini-player-bottom-bar-plan.md](../archive/completed-plans/ios-mini-player-bottom-bar-plan.md), with two amendments once
Plan A lands:

- **Phase 4 is deleted.** The conditional `NavigationStack` migration is absorbed by A5.
- **Phase 3's per-screen occlusion audit stays** — still the core of the work, but now verifying a
  modern container rather than probing a deprecated one's edge cases.

### Plan C — Swift 6 readiness for the generated networking layer

**Now its own plan: [ios-swift6-generated-networking-plan.md](../archive/completed-plans/ios-swift6-generated-networking-plan.md).**

**Blocks:** A4 only. Nothing else in Plan A or B waits on it.

**The investigation recommended below was run, and it inverted the plan.** The blocking code turned
out to be **dead code**: the generated request layer is referenced only by other generated files —
the app's networking is the hand-written `APIClient` talking to `URLSession` directly. Deleting all
seven request-layer files and rebuilding broke **no app code** (only two references inside another
generated file).

So C1 (fork the 682-line `URLSessionImplementations.mustache`) and C2 (separate framework target) are
**withdrawn**. The adopted approach is **C3 — stop generating code we never use.** The endstate has
less code, no vendor fork, and no structural seam.

See the plan file for the one real complication (`JSONEncodable` is declared in the same file as the
unused `RequestTask`, so a naive models-only exclusion will not compile), the mechanism options, and
the `-g swift6` generator lead worth time-boxing first.

### Deliberately _not_ in any plan

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

**Done:** A0, A1, A2 (#133) · A3 (#134) · A5 (#135) · A6 (#136) · Plan B (#140) · Plan C (July 30, 2026).

**Ready now:** nothing — **Plan A is complete.**

A4 shipped July 31, 2026. What it actually took:

1. `Sendable` on two DI protocols (`APIClientProtocol`, `NotificationAuthorizing`). `CoverCaching`
   needed nothing — it was already `@MainActor`.
2. `APIClient` made `final` and its three mutable properties (`accessToken`,
   `forceLogoutHandler`, `tokenRefreshHandler`) moved behind a new lock-backed `Locked<Value>` box.
3. `Task.detached` → plain `Task` at `LibraryManager.swift:159`. The detached task hopped straight
   back to the main actor anyway, so it bought no concurrency while creating a real race.
4. `AppDelegate` → `@MainActor` with `nonisolated` UN delegate methods; the notification `userInfo`
   is flattened to `[String: String]` before crossing into the Task.
5. `AuthenticatedResourceLoader` → `@unchecked Sendable` (all `let`s plus a lock-guarded dictionary),
   and `ResourceLoadingRequesting` → `Sendable`.
6. **~40 fixes across 13 test files** — far more than the app changes. Mostly mechanical:
   `@MainActor` async `setUp`, `@unchecked Sendable` on XCTestCase subclasses and mocks, and
   captured `var`s boxed in `Locked`.
7. The flip itself on all three targets, plus `--swiftversion 6.0` in `ios/.swiftformat` and
   `generate-swift.sh`.

**The error count was never trustworthy from one build.** It went 11 → 4 → 5 → 2 → 1 → 0 for the app
target, then 43 → 53 → 23 → 48 → 24 → 22 → 9 → 7 → 3 → 1 → 0 for the tests: each fix let the compiler
reach further. Always re-measure; never treat a single build's count as the remaining work.

### Settled

- **iPad** — removed (A0). Verified safe: ad-hoc distribution, no App Store implication.
- **A3 approach** — template override (Option 1) chosen and shipped. It worked cleanly: one
  overridden file, one changed generated file, drift check still meaningful.
- **Plan A / Plan B split** — confirmed, for attribution rather than size (§2).
- **URLSession work is its own plan (Plan C), not a Plan A step** — see §7. Now written up as
  [ios-swift6-generated-networking-plan.md](../archive/completed-plans/ios-swift6-generated-networking-plan.md), with the
  investigation done: the blocking code is unused, so the approach is removal, not a vendor fork.
- **Generator 7.24.0 is not an upgrade path** — verified identical template plus an `image/`
  content-type regression.

---

## 7. Why the URLSession work is its own plan

> Asked directly: append it to Plan A as a final step, or split it out? Goal is the correct endstate,
> not the shortest path.

**Split it out (Plan C).** Not because of size — because it is a different _kind_ of work, and mixing
kinds inside one plan is what makes plans stop being useful.

Everything in Plan A is **bounded and locally verifiable**: a known list of call sites, a mechanical
change, and a green gate that means done. Even A3, the fiddliest, was "override one file, diff one
generated file."

Plan C was neither:

1. **The approach wasn't decided, and one option deletes the problem instead of solving it.** That
   deserved to be investigated and argued on its own, not smuggled in under "finish A4."
2. **It looked like ongoing ownership, not a one-time change.** Patching the vendor template would
   have meant a 3-way merge at every generator upgrade, forever. A "final step" framing hides a
   permanent maintenance obligation inside a checklist item.
3. **Its risk profile is inverted from Plan A's.** Plan A's steps are individually safe and
   collectively invisible. Plan C looked like it touched the network path for a payoff
   (`SWIFT_VERSION 6.0`) that is **entirely invisible to users**. That trade needs to be made
   deliberately, in daylight.
4. **A4 stops being a hostage.** With A4 last and gated on Plan C, A5 → Plan B (the mini player, the
   thing you originally asked for) proceeds without ever waiting on generated networking code.

**Splitting it out is what surfaced the answer.** Given its own plan, point 1 got investigated
properly — and the finding was that the blocking code is **dead code**, referenced only by other
generated files. That reduced Plan C from "fork a 682-line vendor template carrying every API call" to
"stop generating what we never use," and eliminated points 2 and 3 outright. Buried as a Plan A
bullet, the likely outcome was patching the template and inheriting the fork forever.

**The endstate:** app and generated code both compiling under Swift 6 with
`SWIFT_STRICT_CONCURRENCY: complete`, **no forked vendor template, less generated code than today**,
and `A4` reduced to the 2-line flip it was always supposed to be.
