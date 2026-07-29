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

> ⚠️ **This measurement was incomplete — do not rely on it.** It built only the app target via
> command-line overrides and missed `DebugLogger`, `SystemKeychain`, and 6 structural errors in
> generated `URLSessionImplementations.swift`. The first two are fixed (A3); the third is
> [Plan C](#plan-c--swift-6-readiness-for-the-generated-urlsession-layer) and is the reason A4 is now
> the last step rather than a trivial 2-line flip. Kept here as written because the flawed method is
> itself the lesson: flip the real build setting and compile **both** targets.

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

| Step      | Work                                                                                                                            | Size              | Risk                    |
| --------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------- | ----------------------- |
| ✅ **A0** | Drop iPad: `TARGETED_DEVICE_FAMILY: '1'` — **done**                                                                             | 1 line            | Very low                |
| ✅ **A1** | `@StateObject` → `@ObservedObject` on the singleton sites — **done** (32 sites)                                                 | 32 one-line edits | Very low                |
| ✅ **A2** | `@MainActor` on the 4 unannotated services (`AppIconManager`, `PlaybackSettings`, `ProgressManager`, `ThemeManager`) — **done** | Small             | Low                     |
| ✅ **A3** | `Sendable` validation rules via generator template override — **done**                                                          | Small but fiddly  | Medium — build tooling  |
| **A5**    | Convert the 10 production `NavigationView` → `NavigationStack`                                                                  | 10 sites          | Medium — the real work  |
| **A6**    | _(optional)_ Legacy `PreviewProvider` → `#Preview` in the 10 remaining files; drops the `periphery:ignore` workarounds          | Small             | Very low                |
| **A4**    | Flip `SWIFT_VERSION: '6.0'` + `SWIFT_STRICT_CONCURRENCY: complete` — **now the last step**, gated on Plan C below               | 2 lines           | Low _once Plan C lands_ |

**A4 moved to the end.** It was originally "2 lines, low risk, gated on A3." A3 landed and A4 is
still blocked — on generated **URLSession** code, a materially bigger problem than the validation
rules (see [Plan C](#plan-c--swift-6-readiness-for-the-generated-urlsession-layer)).

**Dependencies:**

```
A3 ✅ ──▶ Plan C ──▶ A4      (language mode needs the URLSession layer Sendable-clean)

A0 ✅, A1 ✅, A2 ✅, A5, A6   independent — any order, any time
A5 ──▶ Plan B                (recommended, not required)
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

### Plan C — Swift 6 readiness for the generated URLSession layer

**Its own plan, not a step appended to Plan A.** The reasoning is in §7 below; the short version is
that this is a different _kind_ of work (owning a fork of a vendor template that carries every API
call in the app) with a different risk profile and a different review need than anything in Plan A.

**Blocks:** A4 only. Nothing else in Plan A or B waits on it.

#### The problem

Under `SWIFT_VERSION 6.0` + `SWIFT_STRICT_CONCURRENCY complete`, the generated
`URLSessionImplementations.swift` (682 lines) produces 6 errors:

| Line | Error                                                                                     |
| ---- | ----------------------------------------------------------------------------------------- |
| 62   | `var challengeHandlerStore` — nonisolated global shared mutable state                     |
| 65   | `var credentialStore` — nonisolated global shared mutable state                           |
| 163  | capture of `self` (non-`Sendable` `URLSessionRequestBuilder<T>`) in a `@Sendable` closure |
| 163  | capture of `completion` (non-`Sendable` closure) in a `@Sendable` closure                 |
| 164  | capture of `cleanupRequest` (non-`Sendable` closure) in a `@Sendable` closure             |
| 371  | non-final class `SessionDelegate` cannot conform to `Sendable`                            |

These are **structural**, not a missing annotation. The template is already partially Swift-6 aware —
`dataTaskFromProtocol`'s completion handler is declared `@escaping @Sendable` (template line 31/36),
and that is precisely what makes the captures at 163–164 illegal. Upstream is mid-migration.

#### Verified: upgrading the generator does not fix it

Generator 7.24.0 (released 2026-07-20, newer than our 7.23.0 pin) ships a
`URLSessionImplementations.mustache` that is **byte-identical except one unrelated line**:

```diff
-} else if contentType.hasPrefix("application/octet-stream") || contentType.hasPrefix("image/") {
+} else if contentType.hasPrefix("application/octet-stream"){
```

That is a **regression for us** — it drops `image/` content-type handling, which this app relies on
for cover art. So 7.24.0 is not an upgrade path; it is a downgrade plus the same Swift 6 errors.
Re-check on each future generator release before doing any of the work below.

#### Options

**C1 — Patch `URLSessionImplementations.mustache` as a second template override _(recommended)_**

Extends the mechanism A3 already established and proved. Work required:

1. `final class SessionDelegate` (line 371) — check nothing subclasses it.
2. Replace the two mutable global `SynchronizedDictionary` stores with a lock-protected type, or
   move them into the delegate's instance state.
3. Restructure the dataTask completion closure (lines 162–166) so it does not capture `self`,
   `completion`, or `cleanupRequest` across the `@Sendable` boundary — the genuinely delicate part.
4. Regenerate, build under Swift 6, run the full gate.

- **Pro**: no new build targets; consistent with A3; drift check keeps working; keeps generated code
  in the same module.
- **Con**: we own a fork of a 682-line vendor template covering the app's entire network path. Every
  future generator upgrade needs a 3-way merge. This is the real cost, and it is ongoing.
- **Mitigation**: coverage here is unusually good — 698 iOS tests plus 286 live contract tests all
  exercise this code path, so a mistake shows up fast rather than silently.

**C2 — Extract generated models into a separate framework target kept at Swift 5**

Mixed-language-mode build: app code at 6.0, generated code at 5.0.

- **Pro**: zero vendor-template ownership; generator upgrades stay trivial.
- **Con**: new framework target, module boundary, `import` churn across the app, and everything
  crossing that boundary must be `Sendable` anyway — so it may not even avoid the work. Leaves a
  permanent structural seam to explain forever.
- **Note**: this replaces "Option 3" from §3, which was **wrong as written** — it claimed XcodeGen
  could set `SWIFT_VERSION` per _source group_. It cannot; `SWIFT_VERSION` is target-level and
  `-swift-version` is whole-module in the compiler. A separate target is the only real form of that
  idea.

**C3 — Replace the generated URLSession layer with hand-written networking**

The app already has a hand-written `APIClient` (838 lines) that is Swift 6 clean. The generated
`URLSessionImplementations` may be largely redundant.

- **Investigate first**: how much of the generated request machinery does `APIClient` actually route
  through? If little, deleting it beats patching it.
- **Pro**: removes the problem permanently, no fork, no extra target.
- **Con**: potentially the largest change; needs the contract tests as the safety net.

#### Recommended sequence

1. **Scope C3 first** — one afternoon of investigation. If `APIClient` does not meaningfully depend
   on the generated URLSession layer, C3 is the correct endstate and the other options are moot. This
   is cheap to answer and changes everything, so it goes first.
2. If C3 is not viable, **do C1**, with `image/` handling explicitly preserved and a regression test.
3. Treat **C2 as the fallback** if C1's closure restructuring proves unsound.
4. Then flip **A4** (2 lines) and delete this plan.

#### Also part of Plan C

- Bump `--swiftversion` to 6.0 in **both** `ios/.swiftformat` and `scripts/generate-swift.sh:99`.
  Deliberately **not** done in A3: with the compiler on 5.0, telling swiftformat 6.0 would be
  incoherent. These move with A4, not before.

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

**Done:** A0, A1, A2 (PR #133) · A3 (PR #134).

**Ready now:** **A5** (`NavigationStack`), **A6** (previews). Both independent, both concrete.

**Blocked:** **A4** — waits on Plan C.

### Settled

- **iPad** — removed (A0). Verified safe: ad-hoc distribution, no App Store implication.
- **A3 approach** — template override (Option 1) chosen and shipped. It worked cleanly: one
  overridden file, one changed generated file, drift check still meaningful.
- **Plan A / Plan B split** — confirmed, for attribution rather than size (§2).
- **URLSession work is its own plan (Plan C), not a Plan A step** — see §7.
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

Plan C is neither:

1. **It creates ongoing ownership, not a one-time change.** C1 means maintaining a fork of a 682-line
   vendor template that carries every API call in the app. That cost recurs at every generator
   upgrade, forever. A "final step" framing hides a permanent maintenance obligation inside a
   checklist item.
2. **The approach isn't decided, and one option deletes the problem instead of solving it.** C3 —
   discovering the generated URLSession layer is largely redundant next to the hand-written
   `APIClient` — would be the genuine correct endstate. That deserves to be investigated and argued on
   its own, not smuggled in under "finish A4."
3. **Its risk profile is inverted from Plan A's.** Plan A's steps are individually safe and
   collectively invisible. Plan C touches the network path for a payoff (`SWIFT_VERSION 6.0`) that is
   **entirely invisible to users**. That trade needs to be made deliberately, in daylight.
4. **A4 stops being a hostage.** With A4 last and gated on Plan C, A5 → Plan B (the mini player, the
   thing you originally asked for) proceeds without ever waiting on generated networking code.

The "correct endstate" instinct is right, and it is exactly why this should not be a bullet at the
bottom of Plan A: appended final steps are the ones that quietly never happen. As its own plan with a
recommended investigation-first sequence, it stays a real decision with a real owner.

**What that endstate is:** app and generated code both compiling under Swift 6 with
`SWIFT_STRICT_CONCURRENCY: complete`, no forked vendor template if C3 proves viable, and `A4` reduced
to the 2-line flip it was always supposed to be.
