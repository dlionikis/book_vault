# Testing Coverage Review — Book Vault (iOS + Web)

> **Status**: ✅ **Superseded / historical (July 2026).** A point-in-time review whose recommendations were executed in [testing-hardening-implementation.md](testing-hardening-implementation.md); several findings were already resolved when it ran (see the inline `⚠️ Annotation` notes). Archived for reference.
> **Date**: July 13, 2026
> **Validated against**: `main` @ `e6f9764` (Security P0, #75)
> **Method**: Full web Jest run with coverage, Xcode test-plan enumeration, and a diff of merged PRs against the prior review baseline (`dd9bb2b`).

---

> ## ⚠️ Review annotations (July 13, 2026)
>
> **Baseline caveat that reframes this document**: at the time this review ran, `main` contained **only PR #75**. PRs #76–#78 were merged, but into their stacked parent branches rather than main (base branches weren't deleted at merge, so GitHub never retargeted them). Their content lands on main via **PR #79**. Consequently, several findings below are accurate for the measured tree but **already resolved** in work that was believed merged. Inline annotations marked `⚠️ Annotation` throughout; summary of corrections:
>
> - **Already resolved by #76–#78 (lands with #79)**: coverage thresholds exist (34/32/35/34); Jest is partitioned into unit/integration projects; real-jose JWT/auth tests exist (17 tests); `api-schemas.ts` relocated to `__tests__/helpers/` (test support, not untested runtime code); iOS `DownloadManager` DI seam closed; iOS suite is 617 tests, web unit suite is 454.
> - **Factual errors**: the swift-testing "mandate" does not exist anywhere in the repo; `AuthManagerTests` has 11 placeholder stubs (not 6; 24 total with `APIClientTests`); `lib/auth.ts`/`lib/jwt.ts` had **zero** tests at this baseline (claimed "well covered"); "18 of 23 services tested" contradicts the 6 untested services listed (17/23).
> - **Confirmed-valid gaps surviving all merges**: `CoverCacheManager` (changed in #75 without an iOS test — fair hit), `/api/audio/[...path]`, `SystemKeychain`, `AuthenticatedAVAssetResourceLoaderDelegate`, `SearchManager`, browse/search/entity routes, interactive web components, the 24 iOS placeholders, no E2E anywhere.
> - **Re-prioritization**: XCUITest as P0 is overweighted for a single-user app with a manual release process — see the annotated sequencing section for the recommended order.

---

## Executive Summary

The two platforms have **inverted testing profiles**: strong service/logic layers underneath, and an unprotected UI layer on top.

| Layer                   | iOS                                              | Web (Next.js)                                  |
| ----------------------- | ------------------------------------------------ | ---------------------------------------------- |
| Service/logic           | ✅ Strong (unit + "Real" integration, 608 tests) | ⚠️ ~40% measured line coverage                 |
| API/contract            | N/A                                              | ✅ Strong (OpenAPI contract + CI drift check)  |
| Security-critical paths | ⚠️ Keychain/stream-auth untested                 | ✅ Improved — P0 tests merged & passing (#75)  |
| UI                      | ❌ None                                          | ⚠️ ~33% components, ~28% pages                 |
| E2E                     | ❌ None                                          | ❌ None                                        |
| Coverage enforcement    | N/A                                              | ❌ No thresholds — coverage can silently erode |

> ⚠️ **Annotation**: coverage thresholds DO exist in the #76 work landing via #79 (34/32/35/34, set from the pre-#75 baseline). Correct action is now to **ratchet them up** toward this review's measured 39/36/40/40 floor, not to add them.

**Headline finding: there are zero UI tests anywhere.** The iOS project has no XCUITest target (`project.yml` declares only app + unit-test targets), and the web app has no Playwright/Cypress. Every end-to-end user journey — login, playback, search, add-to-library, offline transitions — is unverified. The service layers underneath are genuinely well tested (especially iOS), so risk is concentrated at the top of the stack, not the bottom.

### Verified Live Results (2026-07-13)

- **Web suite: all green** — 41 suites / 350 tests passed, 0 failures, 4.6s. (2 suites / 108 tests skipped — the OpenAPI contract tests, which only run against a live dev server via `npm run test:contract`.)
- **Measured web coverage**: 39.98% statements / 36.2% branches / 40.6% functions / 40.72% lines.
- **iOS**: 608 enabled tests, 0 disabled, single unit-test target (`BookVaultTests`). No XCUITest target exists.

> ⚠️ **Annotation**: these numbers are pre-#76. After #79 lands: web unit suite is **454 tests** (adds 17 real-jose JWT/auth tests among others; the 13 downloads tests moved to a separate `integration` Jest project requiring Docker), iOS is **617 tests**. Contract tests also now run in local `validate:full`, not only via `npm run test:contract`.

### Recently Closed (PR #75)

The security-hardening work shipped with tests, now green on `main`:

| Merged test                                        | Covers                                            |
| -------------------------------------------------- | ------------------------------------------------- |
| `__tests__/api/books/chapters-auth.test.ts`        | Admin-gate on chapter rewrite                     |
| `__tests__/api/images/route.test.ts`               | Auth + extension/path validation on image serving |
| `__tests__/api/library/series-route.test.ts`       | UUID validation, auth enforcement                 |
| `__tests__/lib/media.test.ts`                      | Path-traversal prevention                         |
| `__tests__/api/openapi-contract.test.ts` (updated) | Contract coverage for hardened routes             |

---

## Part 1 — iOS

### The Good

- **Excellent service-layer coverage.** 17 of 23 services are tested, most with a dual pattern: mock-based unit tests _and_ "Real" integration tests exercising the actual implementation against mocked externals (URLProtocol for HTTP, in-memory Keychain, temp-dir FileManager, isolated UserDefaults suites). This catches both logic errors and real serialization/persistence bugs.
  > ⚠️ **Annotation**: corrected from "18 of 23" — the appendix lists **6** untested services, making this 17/23.
- **Mature mock infrastructure.** All 11 major protocols have protocol-conforming mocks with call tracking, configurable failure injection, and `reset()` for isolation.
- **Strong state-machine and offline testing.** `AudioPlayerManager`, `DownloadManager`, `NetworkMonitor`, and `SyncManager` cover transitions and boundary conditions well. `PlaybackFlowTests` covers the online → offline → reconnect → sync journey across six coordinated mocks — the single most valuable test in the suite.
- **Good async discipline** — proper `@MainActor` usage, async test methods, no obvious flakiness patterns.
- **Defensive model decoding tests** — multiple date formats (ISO8601 ± fractional seconds, date-only), null/minimal fields, matching the API's custom decoder.

### The Bad

- **No UI tests.** 28+ SwiftUI views have zero coverage — no snapshot tests, no view-model tests, no XCUITest. Navigation, view state, and error/empty-state rendering are entirely unverified.
- **Placeholder tests masquerading as coverage.** `APIClientTests.swift` (13 tests) and `AuthManagerTests.swift` (6 tests) are largely `XCTAssertTrue(true)`-style stubs. These inflate the 608 count and give a **false green signal** for two of the most security-critical components. (Real coverage lives in the `Real/` variants; the stubs should be completed or deleted.)
  > ⚠️ **Annotation**: count correction — verified by grep, `AuthManagerTests.swift` has **11** `XCTAssertTrue(true)` stubs, `APIClientTests.swift` has 13: **24 total**. The finding itself stands (delete or complete them).
- **`CoverCacheManager.swift` changed in #75 (+35 lines, auth-related) but still has no dedicated tests** — a behavior change to a security-adjacent path shipped without iOS-side coverage. The web side of the same change _was_ tested; the iOS consumer wasn't.
- **Incomplete DI.** Some services still use singletons (`APIClient.shared`), limiting test isolation.
  > ⚠️ **Annotation**: mostly resolved/overstated. #78 (lands via #79) closed the last genuine seam bypass (`DownloadManager`'s two `URLSession.shared` calls). The remaining `.shared` singletons all follow the dual-init pattern (private production wiring + public DI initializer) and are injectable in tests by design.

### iOS Gap Register

| Priority | Gap                                                                                         | Why it matters                                           |
| -------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **P0**   | No `BookVaultUITests` target; zero UI/view coverage                                         | Top-of-funnel flows completely unverified                |
| **P0**   | `SystemKeychain` — untested                                                                 | Token storage; a security primitive with no direct tests |
| **P0**   | ~19 placeholder stubs in `APIClientTests`/`AuthManagerTests`                                | False confidence on auth/networking                      |
| **P0**   | `CoverCacheManager` — modified in #75, still untested                                       | Changed code with no safety net                          |
| **P1**   | `AuthenticatedAVAssetResourceLoaderDelegate` — untested                                     | Authenticated audio streaming; complex and failure-prone |
| **P1**   | `SearchManager` — untested                                                                  | User-facing feature with zero coverage                   |
| **P1**   | No auth-flow integration test (login → authed call → refresh → logout)                      | Only exercised in fragments                              |
| **P2**   | `PlaybackSettings`, `AppIconManager` — untested                                             | Lower risk; rounds out coverage                          |
| **P2**   | Negative/malformed-data fixtures; specific error types (storage full, Keychain unavailable) | Error paths thinly tested                                |

> **Framework note**: CLAUDE.md prescribes swift-testing (`@Test`), but the suite is 100% XCTest. Defensible for a mature suite — but the mandate and reality should be reconciled (update the doc, or adopt `@Test` for new tests).

> ⚠️ **Annotation**: **factual error** — no swift-testing mandate exists in CLAUDE.md or anywhere else in the repo (verified by repo-wide grep; the only mention of swift-testing is this document). There is nothing to reconcile; disregard this note.

---

## Part 2 — Web (Next.js)

### The Good

- **Contract testing is the standout.** `__tests__/api/openapi-contract.test.ts` (~1,900 lines) validates live responses against `docs/api/openapi.yaml` via `jest-openapi`, and `scripts/check-endpoint-coverage.ts` fails CI on spec/route drift. This OpenAPI-first discipline keeps the API and its iOS/web clients honest.
- **Solid validation pipeline** — `validate` / `validate:full` chain format, lint, typecheck, spec validation, drift check, and tests.
- **Security-focused tests now on main** (see PR #75 table above): auth gates, path-traversal prevention, UUID validation — durable regression protection.
- **Core `lib/` utilities well covered** — auth, jwt, s3, media, book-transformer, api-helpers, audio-metadata.
  > ⚠️ **Annotation**: **incorrect at this baseline** — `main@e6f9764` has _zero_ tests for `lib/auth.ts` and `lib/jwt.ts` (jose was globally stubbed in Jest config, so no test anywhere actually signed or verified a token). Real-jose JWT/auth tests (17) arrive with #79. The other utilities listed are correctly described.
- **Fast, non-flaky suite** — 350 tests in 4.6s.

### The Bad

- **~40% coverage with no thresholds enforced.** `jest.config.js` collects coverage but sets no `coverageThreshold`, so coverage can silently erode. The single easiest high-leverage fix.
  > ⚠️ **Annotation**: resolved in #76 (lands via #79) — thresholds exist at 34/32/35/34. Remaining action: ratchet to ~39/36/40/40 per this review's measurement. Worth noting the tooling backstory: coverage was _unmeasurable_ until #76 fixed a broken `glob` override, which is why no threshold existed.
- **Entire route families untested**: all Browse routes (authors/categories/narrators/series), all entity-detail routes, both Search routes, `/api/audio/[...path]` streaming, most Library-list routes, `/api/auth/register`, `/api/health`.
- **Interactive components under-tested** (~33%). `SearchBar`, `AddToLibraryButton`, `PlaybackClient`, `ChapterList` have no tests; Storybook stories exist but aren't automated assertions.
- **Branch coverage (36.2%) trails line coverage** — error paths and conditionals are the weak spot in what coverage exists.
- **No E2E.** No Playwright/Cypress.

### Web Gap Register

| Priority | Gap                                                                                        | Why it matters                                            |
| -------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| **P0**   | No `coverageThreshold` in `jest.config.js`                                                 | Stops silent erosion; makes coverage a gate               |
| **P0**   | `/api/audio/[...path]` streaming untested                                                  | The remaining untested media surface (images now covered) |
| **P1**   | Browse (4), Search (2), entity-detail (4) routes — 0 tests                                 | Core discovery features                                   |
| **P1**   | Interactive components: `SearchBar`, `AddToLibraryButton`, `PlaybackClient`, `ChapterList` | Key UI interactions, no regression net                    |
| **P1**   | `lib/rate-limit`, `lib/api-schemas` (Zod), `lib/api-utils` (pagination/UUID) — untested    | Data-layer + abuse-prevention logic                       |
| **P2**   | `/api/auth/register`, `/api/health`, library-lists CRUD                                    | Fill remaining route gaps                                 |
| **P2**   | Branch coverage at 36%                                                                     | Error paths under-exercised                               |

> ⚠️ **Annotation**: first P0 row resolved via #79 (ratchet instead, see above). In the third P1 row, drop `api-schemas` — #77 relocated it to `__tests__/helpers/` as test-support code consumed by the type-validation suite; it is not untested runtime logic. `rate-limit` and `api-utils` remain valid gaps.

---

## Cross-Cutting: Close the UI/E2E Gap

The theme uniting both platforms. Given how strong the unit layers already are, E2E smoke tests are worth more than further unit backfill.

1. **iOS**: Add a `BookVaultUITests` target (XCUITest) to `project.yml`. Start with a smoke suite: launch → login → open a book → start playback → go offline → verify resume. This single flow covers the highest-traffic path that currently has zero protection.
2. **Web**: Add Playwright for the equivalent browser journey (login → search → play → add to library).

---

## Recommended Sequencing

1. **Days — stop the bleeding**
   - Add `coverageThreshold` to `jest.config.js`, locking in today's floor (`statements: 39, branches: 36, functions: 40, lines: 40`) so it can only ratchet up.
   - Delete or complete the iOS placeholder stubs in `APIClientTests`/`AuthManagerTests` (removes false-green on auth).
2. **Now-urgent**
   - Add `CoverCacheManagerTests` — the one component that changed behavior this cycle without a test.
3. **1 sprint — finish the hardening arc**
   - Cover the remaining security-critical primitives: `SystemKeychain`, `AuthenticatedAVAssetResourceLoaderDelegate`, `/api/audio/[...path]`.
4. **1–2 sprints — UI smoke tests**
   - `BookVaultUITests` target + login→playback smoke flow (XCUITest).
   - Playwright happy path on web.
5. **Ongoing — breadth backfill**
   - Browse/Search/entity routes; interactive components; error-path/branch coverage.

> ⚠️ **Annotation — amended sequencing**: agree with items 1–3 and 5 (item 1's threshold becomes a _ratchet_ to 39/36/40/40 once #79 lands). Item 4 needs re-weighting for this project's context — a single-user app with a manual release process where the owner personally QAs every TestFlight build:
>
> 1. Merge **PR #79** first — it changes the baseline this doc measured.
> 2. Cheap, security-adjacent unit work: `CoverCacheManagerTests` (the #75 bearer-attach logic: token sent to API host, never to presigned S3 URLs), delete/complete the 24 placeholders, `SystemKeychain`, `AuthenticatedAVAssetResourceLoaderDelegate`, `/api/audio/[...path]` route tests.
> 3. **Playwright web smoke** (login → search → play → add-to-library) — cheap, headless in CI, and well-timed _before_ the S3 restore feature adds archive/restore UI states worth covering.
> 4. **XCUITest: demote from P0 to P2.** It's the highest-maintenance, flakiest test category (simulator management in CI, timing waits, breaks on UI tweaks), and the iOS release loop is already human-verified. Revisit if the app gains users or an automated release path. A minimal launch→login→play smoke is the most that's justified today.

---

## Appendix: Inventory Snapshot

> ⚠️ **Annotation**: counts below are the `main@e6f9764` snapshot. Post-#79: iOS 617 tests (9 new DownloadManager/APIClient seam tests), web 454 unit tests in three Jest projects (unit-node / unit-dom / integration), and `DownloadManagerRealTests` now use isolated per-test `UserDefaults`.

### iOS (`ios/BookVault/BookVaultTests`, 608 tests, all XCTest)

| Area                        | Files | Notes                                                               |
| --------------------------- | ----- | ------------------------------------------------------------------- |
| Services (mock-based unit)  | 13    | ~256 tests; `APIClientTests`/`AuthManagerTests` largely stubs       |
| Services/Real (integration) | 14    | ~327 tests; URLProtocol HTTP mocking, Keychain/file-I/O integration |
| Models                      | 1     | JSON decoding, date-format variations                               |
| Integration                 | 1     | `PlaybackFlowTests` — online/offline/sync journey                   |
| Mocks                       | 11    | All major protocols; call tracking + failure injection              |
| Fixtures                    | 1     | Factory methods for all OpenAPI models; no negative fixtures        |

**Untested services**: `SystemKeychain`, `AuthenticatedAVAssetResourceLoaderDelegate`, `SearchManager`, `CoverCacheManager`, `PlaybackSettings`, `AppIconManager`.
**Untested views**: all 28+ SwiftUI views.

### Web (`__tests__/`, 41 active suites / 350 tests + 2 contract suites)

| Area             | Coverage       | Notes                                                                                                                 |
| ---------------- | -------------- | --------------------------------------------------------------------------------------------------------------------- |
| API routes       | ~16/40 (~40%)  | Auth-mobile, admin, progress, downloads, images, chapters, library/series tested; browse/search/entity/audio untested |
| `lib/` utilities | ~10/20 (~50%)  | Core auth/media/s3/transform tested; rate-limit/schemas/utils untested                                                |
| Components       | ~10/27 (~37%)  | Display components tested; interactive components largely not                                                         |
| Pages            | ~5/18 (~28%)   | Home, book detail, browse-authors, settings, admin dashboard                                                          |
| Contract         | ~30+ endpoints | `jest-openapi` against live dev server; drift check in CI                                                             |
| E2E              | 0              | No Playwright/Cypress                                                                                                 |
