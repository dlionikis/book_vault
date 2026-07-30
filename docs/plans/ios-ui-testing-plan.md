# iOS UI Testing Plan (XCUITest)

> **Status**: Phases 1–3 + 5 shipped July 30, 2026 · Phase 4 (flows U2–U5) remaining
> **Scope**: iOS test infrastructure. No app logic, no API, no DB, no web.
> **Created**: July 30, 2026
> **Related**: [ios-modernization-sequencing.md](ios-modernization-sequencing.md) ·
> [ios-mini-player-bottom-bar-plan.md](ios-mini-player-bottom-bar-plan.md)

---

## 1. Why

There is **no UI test target**. `BookVaultTests` is `type: bundle.unit-test`, and there is no
`XCUIApplication` anywhere in the repo. The 698 iOS tests are all unit tests exercising services,
view models, and mocks — **none of them instantiate a view**.

This produced a concrete, named gap on the last two PRs:

- **A5** (`NavigationView` → `NavigationStack`, #135) migrated every navigation container in the app.
  The full gate went green, and the gate proved **nothing** about navigation. Push → detail → back was
  never verified automatically, and neither was safe-area propagation into pushed destinations.
- **Plan B** (mini-player bottom bar) is a layout change on **every screen**, whose central
  requirement (L1: "no screen's content is clipped or unreachable") is exactly what a green unit suite
  cannot speak to.

The value is not coverage. It is **a handful of critical-path smoke flows that fail loudly when
navigation or layout breaks.**

### Ordering argument

Doing this **before Plan B** means the mini-player work has automated verification of the precise
thing it risks breaking. Doing it after means Plan B ships on manual passes and the tests get written
against whatever behavior resulted — including any bug.

---

## 2. Framework choice: XCUITest

**Recommendation: XCUITest.** First-party, already in the toolchain, no new dependency, runs under the
existing `xcodebuild`-based gate.

| Option       | Verdict                                                                                                                                                                                                                                        |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **XCUITest** | **Chosen.** Ships with Xcode, same `xcodebuild test` invocation the gate already uses, Xcode can record flows to bootstrap tests, and it drives the real app via the accessibility tree.                                                       |
| **Maestro**  | Genuinely lower ceremony (YAML flows, faster to write, better failure output). Rejected only because it adds a runtime dependency and a second test system outside `validate:ios`. Reconsider if XCUITest flakiness becomes the dominant cost. |
| **Appium**   | Rejected. Cross-platform value is irrelevant for a Swift-only app; heaviest setup of the three.                                                                                                                                                |

---

## 3. The prerequisite nobody will expect

**The app has almost no accessibility identifiers.** Measured:

| Annotation                     | Count |
| ------------------------------ | ----- |
| `.accessibilityLabel`          | 14    |
| `.accessibilityHint`           | 5     |
| `.accessibilityElement`        | 1     |
| `.accessibilityAddTraits`      | 1     |
| **`.accessibilityIdentifier`** | **0** |

This corrects an earlier claim of mine that the views "already carry accessibility annotations, so
there's real groundwork done." There is _some_ — but **zero identifiers**, and identifiers are what UI
tests should query.

Why it matters: `.accessibilityLabel` is **user-facing text**. Querying it couples tests to copy, to
localization, and to book titles from live data:

```swift
app.buttons["Now playing: The Ocean at the End of the Lane"].tap()   // brittle
app.buttons["miniPlayer"].tap()                                      // stable
```

`.accessibilityIdentifier` is invisible to users, never localized, and free to be stable.

**So Phase 1 is adding identifiers**, not writing tests. Roughly 15–25 on the elements the smoke flows
touch: tab bar items, the mini player and its play/pause control, grid/list cells, login fields and
button, and the back affordance. Do **not** blanket-annotate the app — only what tests query.

> Existing `.accessibilityLabel`s stay as-is. They serve VoiceOver and are correct for that; the
> identifiers are additive.

---

## 4. Scope: five flows, no more

Deliberately minimal. UI tests are slow (seconds each, vs. 698 unit tests in ~4.5s) and flaky when
over-invested in. With 698 unit + 286 contract tests already covering logic, these exist **only** to
catch what those structurally cannot.

| #      | Flow                                                              | Catches                                                          |
| ------ | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| **U1** | Launch → login screen renders; fields and button present          | Login layout regressions (the screen whose container A5 deleted) |
| **U2** | Login → catalog loads with ≥1 cell                                | Auth + first-screen wiring                                       |
| **U3** | Catalog → tap cell → detail pushes → back returns                 | **Navigation push/pop — the A5 gap**                             |
| **U4** | Switch every tab; each root renders its title                     | Tab wiring, including the offline tab swap                       |
| **U5** | Start playback → mini player appears → tap → full player presents | **The Plan B surface**                                           |

**U3 and U5 are the reason this plan exists.** U1/U2/U4 are cheap once the harness exists.

### Explicitly out of scope

- Visual/snapshot regression testing (different tool, different failure mode, high maintenance)
- Exhaustive per-screen coverage
- Download, restore, or sync flows (slow, network-dependent, already contract-tested)
- Landscape/Dynamic Type matrices — keep those manual per the mini-player plan

---

## 5. Implementation

### Phase 1 — Accessibility identifiers

Add `.accessibilityIdentifier(...)` to the elements U1–U5 query. Suggested names — stable, terse,
namespaced by screen:

```
login.username, login.password, login.submit, login.continueOffline
tab.catalog, tab.browse, tab.search, tab.library, tab.downloads, tab.restores, tab.settings
catalog.grid, catalog.cell            (cell identifier applied per item)
bookDetail.root, bookDetail.play
miniPlayer.root, miniPlayer.playPause
nowPlaying.root
```

**Verify VoiceOver is unaffected** — setting an identifier must not shadow an existing label. Spot-check
the mini player, which already combines children via `.accessibilityElement(children: .combine)`.

### Phase 2 — Add the UI test target

`ios/project.yml`:

```yaml
BookVaultUITests:
  type: bundle.ui-testing
  platform: iOS
  deploymentTarget: '17.0'
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.bookvault.BookVaultUITests
      TARGETED_DEVICE_FAMILY: '1' # xcodegen defaults to '1,2' — A0 lesson
      SWIFT_VERSION: '5.0' # keep in step with the app; moves with A4
      GENERATE_INFOPLIST_FILE: YES
  sources:
    - path: BookVaultUITests
  dependencies:
    - target: BookVault
```

**Do not add it to the default `BookVault` scheme's `test:` block.** That block currently lists only
`BookVaultTests`, and `scripts/ios-validate.sh` runs a bare `xcodebuild test -scheme BookVault`, so
adding it there would silently put slow UI tests in the fast inner loop.

Instead add a **separate scheme**:

```yaml
BookVault-UITests:
  build:
    targets:
      BookVault: all
      BookVaultUITests: [test]
  test:
    config: Debug
    targets:
      - BookVaultUITests
```

### Phase 3 — Test harness

A base class handling launch, login, and teardown, so individual tests stay short:

- `XCUIApplication()` with a `--uitesting` launch argument.
- **The app must honor that argument** by resetting to a known state — clear the keychain session so
  U1 always sees the login screen, and skip the `loadMostRecentlyPlayedBook()` auto-load that would
  otherwise make U5's "mini player appears" assertion vacuous. **This is an app-side change**, small
  but real, and the only place this plan touches app code.
- Use `waitForExistence(timeout:)` everywhere, never `sleep`. This is the single biggest determinant
  of flakiness.

### Phase 4 — Write U1–U5

One file per flow. Assert on identifiers, not labels.

### Phase 5 — Wire into the gate

- `package.json`: `"ios:test:ui": "./scripts/ios-validate.sh --ui-only"` (new flag → new scheme).
- **Keep out of `validate:ios` and `validate:full`.** They are already ~30s for iOS; UI tests would
  add minutes to the pre-PR loop for little marginal signal.
- **CI**: add a step to `.github/workflows/ios-tests.yml` (already `macos-14`, already path-filtered on
  `ios/**`). Mark it **non-blocking initially** (`continue-on-error: true`), matching how SwiftLint and
  coverage are already treated there. Promote to blocking once it has been green for a couple of weeks
  — an immediately-blocking flaky UI suite is how teams learn to ignore CI.
- Requires a booted simulator; the destination-selection logic in `ios-validate.sh` already handles
  picking one.

---

## 6. Risks

| Risk                                  | Mitigation                                                                                                                                                                                                                    |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Flakiness erodes trust**            | 5 flows only; `waitForExistence` never `sleep`; non-blocking in CI at first                                                                                                                                                   |
| **Tests need a backend**              | U2–U5 need `npm run dev` + seeded data. `scripts/seed-e2e.ts` already exists for Playwright — reuse it. Document the prerequisite loudly or the suite fails confusingly                                                       |
| **Slow feedback**                     | Excluded from `validate:ios`; separate scheme and npm script                                                                                                                                                                  |
| **Identifier churn**                  | Identifiers are invisible to users, so they only change when someone edits them — far more stable than labels                                                                                                                 |
| **Auto-loaded book breaks U5**        | `loadMostRecentlyPlayedBook()` populates `currentBook` at launch, so the mini player may already be visible before playback. The `--uitesting` reset must handle this — noted in the mini-player plan as an open question too |
| **Scope creep into snapshot testing** | Explicitly out of scope (§4)                                                                                                                                                                                                  |

---

## 6a. Implementation notes — Phases 1–3 + 5 (shipped July 30, 2026)

Infrastructure is live and proven: **3 UI tests pass in 22.8s**. Unit suite went 698 → **703**
(5 new parity tests). `validate:full` green, exit 0.

**Phase 4 is deliberately incomplete.** U1 (login) is done because it needs no backend and therefore
proves the harness. U2–U5 need `npm run dev` + `npm run e2e:seed` and are the next PR.

What differed from the plan:

1. **The identifiers are shared constants, not string literals.** `A11y` in
   `BookVault/Support/AccessibilityIdentifiers.swift` is the source of truth. A UI test bundle runs
   out-of-process and **cannot `@testable import` the app**, so `BookVaultUITests/A11yID.swift`
   mirrors the strings. Duplication drifts silently, so `A11yIdentifierParityTests` in the unit target
   pins the app-side values — a rename now fails a fast unit test instead of producing a UI test that
   mysteriously cannot find an element.

2. **`.accessibilityElement(children: .combine)` on the mini player is a real constraint, as
   predicted.** It collapses the play/pause button into the parent element. An identifier is set on
   both, but **U5 must verify the button is independently tappable** — if it is not, the combine
   modifier has to be reworked, which is a change to the mini player's accessibility semantics and
   overlaps Plan B's requirement A1.

3. **Two app-side hooks, both gated on `--uitesting`** (`UITestEnvironment`):
   - `AuthManager.restoreSession()` **clears** the keychain rather than merely skipping restoration,
     so state cannot leak between runs.
   - `ContentView`'s `loadMostRecentlyPlayedBook()` is suppressed, so "the mini player appears" is not
     vacuously true at launch.
     A parity test asserts both are inactive without the launch argument, so a shipping build can never
     clear the keychain on launch.

4. **Scheme separation verified, not assumed.** `BookVault.xcscheme` tests only `BookVaultTests`;
   `BookVault-UITests.xcscheme` tests only `BookVaultUITests`. Confirmed `validate:ios` runs 703 unit
   tests with zero `LoginFlowUITests` — the fast loop is intact.

5. **Unplanned fix:** `.xcresult/` bundles were not gitignored. Pre-existing (CI already wrote
   `TestResults.xcresult`), and the new UI bundle would have widened it. Added.

**Timing confirms the plan's caution:** ~7s per UI test vs 703 unit tests in 4.2s. Keeping these out
of `validate:ios` was the right call.

---

## 7. Effort and sequencing

| Phase                             | Size                                         |
| --------------------------------- | -------------------------------------------- |
| 1 — identifiers                   | Small-medium (15–25 annotations, mechanical) |
| 2 — target + scheme               | Small                                        |
| 3 — harness + `--uitesting` reset | **Medium — the real work**                   |
| 4 — five flows                    | Medium                                       |
| 5 — gate + CI                     | Small                                        |

**Recommended: Phases 1–3 as one PR** (infrastructure, provably working with a single trivial test),
then **Phases 4–5 as a second** (the flows and the wiring). Splitting keeps the infrastructure review
separate from the test-content review.

**Sequence against other work:** this **before Plan B**, per §1. It is the only way the mini-player
change gets automated verification of the occlusion and navigation behavior it puts at risk. If that
ordering is unattractive, the honest alternative is accepting manual verification for Plan B and
writing these tests afterward.

---

## 8. Open questions

1. **Before Plan B, or after?** Recommendation is before (§1, §7). Cost is delaying the feature you
   originally asked for; benefit is that the feature ships with real verification.
2. **How much of the `--uitesting` reset belongs in the app?** Minimum is keychain-clear plus skipping
   the auto-load. Anything more (seeded fixtures, mock API mode) is a larger app-side surface and
   should be argued separately.
3. **Blocking in CI from day one, or after a green streak?** Recommendation: non-blocking first,
   consistent with how SwiftLint and coverage are already handled in `ios-tests.yml`.
