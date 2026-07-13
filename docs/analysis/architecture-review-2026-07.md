# Architecture & Test Review — July 2026

> **Date**: July 12, 2026
> **Scope**: Full application review — backend (app/api, lib), web frontend (app, components), iOS app, database schema, test suites, and validation tooling — conducted before starting the S3 archive/restore feature ([plans/s3-archive-restore-workflow-v2.md](../plans/s3-archive-restore-workflow-v2.md)).
> **Method**: Four parallel subsystem reviews with file:line evidence, key claims independently re-verified, full test suite and coverage tooling executed.

---

## Executive Summary

The codebase is in **good architectural shape for its size** — significantly better than typical for a personal project. The foundations are right: correct Prisma singleton usage, a centralized book transformer, OpenAPI-first with generated types and drift checks on both platforms, a genuinely well-engineered iOS dependency-injection layer, and disciplined schema design. The debt is concentrated and specific rather than systemic.

However, the review found:

- **One P0 security hole**: the images route has no authentication and streams arbitrary S3 keys — the entire audiobook library is downloadable without credentials.
- **The safety net has holes exactly where it matters**: the live OpenAPI contract tests (the best tests in the repo) are skipped in every default validation path; coverage tooling is silently broken; `npm test` is red on a fresh machine; and the security-critical auth/JWT code has zero unit tests.
- **A tractable duplication problem**: the dual-auth block is copy-pasted ~34 times, and several utility behaviors exist in 2–4 copies while shared versions sit unused.

**Verdict**: fix the P0s and the test-infrastructure defects before starting the restore feature (~1–2 days), fold the `requireUser()` helper into the feature work, and take the rest opportunistically. No large refactor is warranted.

### Scorecard

| Area                           | Grade  | One-line assessment                                                                                |
| ------------------------------ | ------ | -------------------------------------------------------------------------------------------------- |
| Data layer / schema            | **A−** | 16 models, correct join tables, composite indexes matching query patterns                          |
| Backend API design             | **B**  | Right patterns exist but adopted inconsistently; heavy auth duplication; one unauthenticated route |
| Web frontend                   | **B**  | Correct server/client split; player component overloaded; no error/loading boundaries              |
| iOS app                        | **A−** | Protocol-oriented DI done properly; two god-objects; strongest layer in the repo                   |
| Test effectiveness             | **C+** | Good tests exist but the highest-value layer never runs; critical modules untested                 |
| Test/validation infrastructure | **C**  | Coverage broken, DB tests mixed into unit run, contract tests orphaned from CI                     |
| API governance (OpenAPI-first) | **A**  | Spec-first + codegen + drift checks + pre-commit hooks — genuinely excellent                       |

---

## What Is Done Well (calibration)

These are worth naming so the findings below don't read as systemic criticism:

1. **OpenAPI governance is exemplary.** Spec-first workflow, TS + Swift codegen, `api:check-drift` for both platforms, `check-endpoint-coverage.ts` for spec↔route parity, and a pre-commit hook that regenerates types when the spec changes. This is better governance than most production teams have.
2. **iOS protocol-oriented DI.** 13 focused protocols, dual initializers (private production wiring + public DI init), injected closures instead of singleton reach-through, injectable `URLSession`/`UserDefaults`, `skipAudioSetup` for tests. The expensive architectural work for testability is already done.
3. **Correct concurrency where it's hard**: actor-based single-flight token refresh (iOS), synchronous temp-file move inside the background-download delegate, refresh-token rotation in a DB transaction ([app/api/auth/mobile/refresh/route.ts](../../app/api/auth/mobile/refresh/route.ts)).
4. **`lib/db.ts`, `BOOK_INCLUDE` + `transformBook`, and `requireAdmin`** are each the right abstraction, correctly implemented. (`requireAdmin`'s discriminated-union shape is the template the user-auth path should copy.)
5. **Offline-first iOS data flow**: local-first progress writes, conflict-aware merge, connectivity-triggered sync drain, and background-download state reconciliation across app termination.
6. **Web server/client component split is correct by default** — data fetching in async server components, `'use client'` reserved for interactive leaves.
7. **Real-handler testing is the norm** where tests exist — the admin cost tests mock only the AWS boundary and assert real aggregation logic plus secret redaction ([\_\_tests\_\_/api/admin/costs.test.ts:215](../../__tests__/api/admin/costs.test.ts#L215)).

---

## Part 1: Design Findings

### P0 — Security (fix before anything else)

**SEC-1. `/api/images/[...path]` is completely unauthenticated and streams arbitrary S3 keys.**
[app/api/images/[...path]/route.ts:7](../../app/api/images/%5B...path%5D/route.ts#L7) has no session or bearer check (every other media/data route has one), and the S3 branch passes the raw joined path to `streamS3Object()` with no key restriction. Consequence: **any unauthenticated caller can stream any object in the media bucket — including full audiobooks** — via `/api/images/<book-folder>/<file>.m4b`. Keys are predictable (`Title [ASIN]/…`). Fix: add the dual-auth check; if covers should remain cacheable without auth, instead restrict the route to image content (extension/content-type allowlist) and keep audio keys out. Note the `Cache-Control: public, immutable` header — if auth is added, the caching strategy needs a decision at the same time.

**SEC-2. Deleted users keep working on mobile until token expiry.**
The web session callback re-checks the DB and invalidates deleted users ([lib/auth.ts:59-73](../../lib/auth.ts#L59-L73)); the bearer path ([lib/auth.ts:99-121](../../lib/auth.ts#L99-L121) → `verifyAccessToken`) never touches the DB. A deleted user's access token remains valid for up to 1 hour, and the refresh flow is the only revocation point. For a single-user app this is low practical risk, but the two auth channels should have the same posture — either accept token-lifetime staleness on both (and document it) or check existence on both.

**SEC-3. Content-mutating endpoints gated only by "logged in."**
`POST /api/books/[id]/chapters` lets any authenticated user trigger ffprobe extraction and delete/rewrite the shared `Chapter` table. `POST /api/library/series/[seriesId]` skips UUID validation that sibling routes perform. Gate chapter mutation behind `requireAdmin` (or remove the POST); add `normalizeUuid` to the series route.

**SEC-4 (low). Hardening nits.** `validateMediaPath` uses a `startsWith` prefix check without a trailing separator ([lib/media.ts:28-32](../../lib/media.ts#L28-L32)) — `/data/media-evil` passes for `/data/media`. ffprobe is invoked via shell-string interpolation with only quote escaping ([lib/audio-metadata.ts:81-86](../../lib/audio-metadata.ts#L81-L86)) — switch to `execFile` with an argument array and add a timeout (it currently runs unbounded inside a request handler).

### Design improvements

**D-1. Extract `requireUser(request)` — the single highest-leverage refactor.**
The 6-line dual-auth block appears in **23 route files, ~34 handler occurrences**. `requireAdmin` ([lib/admin-auth.ts](../../lib/admin-auth.ts)) already demonstrates the right shape (discriminated union `{ user } | { error }`). Consequences of the duplication are concrete: SEC-2 can't be fixed in one place today, and the images route (SEC-1) shows what happens when boilerplate is the mechanism — it gets forgotten. **This directly benefits the restore feature, which adds ~6 new authenticated routes.**

**D-2. Standardize error handling and logging.**
Three patterns coexist: bare `console.error` (~33 route files) vs `lib/logger.ts` (2 files); `withLogging` wraps 15 of 39 routes; error bodies are `{ error }` ×145 but `{ message }` ×7, and the chapters route leaks internal `error.message` to clients. Add an `errorResponse(status, message)` helper next to `requireUser`, adopt `logger` in touched files, and normalize on `{ error }`.

**D-3. `/api/books` correctness trio.** ([app/api/books/route.ts](../../app/api/books/route.ts))

- JSDoc documents `authorId/narratorId/categoryId/seriesId` filters that were never implemented — false API contract; implement or delete the docs.
- `sort=author|narrator|series` sorts only the current page in JS after DB pagination — semantically wrong results; sort in the query or drop the options.
- `limit` is raw `parseInt` with no cap (`limit=1000000` is honored); use the existing `parsePagination` (which caps at 100) as `search/route.ts` already does.

**D-4. Single-instance assumptions should be documented or removed.**
`lib/rate-limit.ts` keeps the progress rate-limit map in module memory with a module-scope `setInterval` (per-instance limits, does nothing meaningful under scale-out or serverless), while `checkDownloadLimit` in the same file is correctly DB-backed. `lib/admin-cache.ts` is likewise per-instance with FIFO (not LRU) eviction. With a single ECS task this works today — add a comment stating the assumption, or make the progress limiter DB-backed like its sibling.

**D-5. Web resilience gaps.**

- **No `error.tsx`, `loading.tsx`, or `not-found.tsx` anywhere in `app/`**, and no error boundaries — any client-side throw white-screens; multi-query server pages have no loading UI.
- **Every client fetch swallows errors to `console.error`** with no user-visible state (~10 copy-pasted sites; `AddToLibraryButton` doesn't even check `res.ok`). A tiny shared fetch helper with error state would fix all of them.
- **The AudioPlayer has zero `dark:` variants** — the app's most prominent surface glows white in dark mode while the rest of the app is fully themed. (Relevant to the restore feature: the new `ArchiveStatusBadge`/restore UI lands on these same surfaces.)

**D-6. iOS structural debt (from the iOS review, ranked).**

- `AudioPlayerManager` (1,042 LOC) owns audio session, remote commands, now-playing info, chapters, observers, progress saving, _and_ auto-download/stream-swap orchestration. Extract `NowPlayingInfoController`, `RemoteCommandController`, and a `PlaybackDownloadCoordinator` (the last also removes the `concreteDownloadManager` protocol-escape hatch).
- `DownloadManager` bypasses its own DI seam: eligibility/URL-generation calls use `URLSession.shared` directly (lines ~557, ~598) — the only network code in the app that can't be mock-tested. Route through `APIClient` or the injected session. **Do this before the restore feature adds 202-handling to those exact calls.**
- `APIClient.execute`/`executeWithoutRefresh` are ~90% identical; the refresh coordinator contains a dead `beginRefresh()` and a check-then-act gap between `isRefreshInProgress()` and `markRefreshStarted()` (two separate actor hops — two callers can both start a refresh). Collapse to one atomic actor method.

### Simplification / dead code (safe deletions, verified unused)

| Item                                                    | Evidence                                                                                                                 | Action                                                                   |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `lib/api-schemas.ts` (514 LOC)                          | Imported only by the gated type-validation test; the runtime validation it implies doesn't happen                        | Keep **only** if wired into contract testing; otherwise delete           |
| `lib/api-url.ts`                                        | Imported nowhere; contains a literal `'https://your-production-domain.com'` placeholder                                  | Delete                                                                   |
| `components/ProgressBadge.tsx` (162 LOC + story + test) | Imported nowhere (README mention only); duplicates `ProgressStatus`/`ProgressControls`                                   | Delete; consolidate the two survivors around a shared `useProgress` hook |
| `formatRuntime` ×4 inline copies                        | `BookCard`, `books/[id]/page`, `play/page`, `library/page` each define it while `lib/utils/formatRuntime.ts` sits unused | Point all four at the lib version                                        |
| `formatTime` ×2                                         | `AudioPlayer.tsx`, `ChapterList.tsx`                                                                                     | Consolidate                                                              |
| iOS stale artifacts                                     | `BookVault.xcodeproj.backup/`, nested `ios/ios/BookVault`, `archive/`, `build/`                                          | Delete from tree                                                         |
| `ContinueListening` vs `ContinueListeningButton`        | Same session + `userProgress` query duplicated in two server components                                                  | Extract one shared query function                                        |
| Cover URL convention split                              | `ContinueListening*` prefix with `/api/images/`, `BookCard`/detail pages use raw `transformBook` output                  | Pick one convention; one of these paths is wrong                         |
| N+1 series-add loop                                     | `library/series/[seriesId]/route.ts:53-73` — per-book `findUnique`+`create`, no transaction                              | `createMany({ skipDuplicates: true })`                                   |

**Testability cross-cutting note**: several modules read `process.env` and construct AWS clients at import time (`lib/s3.ts:12-13`, all four admin routes). The `S3_ENABLED` work in Phase 0 of the restore plan is the natural moment to move `lib/s3.ts` env reads inside functions.

---

## Part 2: Test Review

### Are the existing tests effective?

**Mixed — with a sharp pattern: the best layers don't run, and the layers that run miss the riskiest code.**

| Layer                                       | Verdict                                | Evidence                                                                                                                                                                          |
| ------------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Live OpenAPI contract tests (~43 endpoints) | **Excellent — but skipped by default** | Real HTTP against a running server, `toSatisfyApiSpec()`, strict extra-field checks. Gated behind `RUN_CONTRACT_TESTS`; **not run by `npm test`, `validate`, or `validate:full`** |
| Admin API tests                             | **Effective**                          | Boundary-mocked AWS, real aggregation + secret-redaction assertions                                                                                                               |
| Progress API tests                          | **Effective**                          | Real conflict-resolution logic asserted (last-write-wins path)                                                                                                                    |
| Mobile auth tests                           | **Weak where it matters**              | `jose` globally stubbed → tokens asserted only `toBeDefined()`; **no test anywhere really signs/verifies a JWT**                                                                  |
| Downloads API tests                         | **Effective but misplaced**            | Real-DB integration tests inside the default unit run → `npm test` fails without Docker Postgres                                                                                  |
| Component tests (10 components, 5 pages)    | **Mixed**                              | Good role/label-driven tests; but 4 AudioPlayer tests assert nothing ("verify no errors"), one asserts Tailwind class names                                                       |
| Performance tests                           | **Not effective**                      | Wall-clock `toBeLessThan(1000)` against fully mocked Prisma — measures nothing real, adds flake                                                                                   |
| iOS XCTest (42 files, ~608 tests)           | **Strongest layer**                    | Mock/Real dual suites, `MockURLProtocol`, integration flow tests — but 24 literal `XCTAssertTrue(true)` placeholders, and the outer (non-Real) suites largely test mocks          |

### Test-infrastructure defects (verified by running them)

1. **`npm test` is red on a fresh machine**: 13 failures in `__tests__/api/downloads/route.test.ts` because it uses the real Prisma client against a live DB that wasn't running. STATUS.md's "All tests passing" is stale. Unit and DB-integration tests must be partitioned (separate Jest project or a `test:integration` script that manages the DB).
2. **Coverage tooling is completely broken**: `jest --coverage` crashes during istanbul instrumentation and reports 0/0. Root cause: `"overrides": { "glob": "^11.0.0" }` in package.json breaks `test-exclude`'s `promisify(glob)` (glob ≥9 removed the callback API). Until fixed, coverage cannot be measured at all — and there's no `coverageThreshold` configured even once it works.
3. **The contract suite is orphaned**: `validate:full` runs drift + endpoint-coverage checks + `npm test`, but never `test:contract`. The one layer that would catch handler↔spec behavioral drift ships green without executing.
4. **Single jsdom environment for everything** — API route tests run in jsdom with undici polyfills instead of a node environment (works, but a multi-project Jest config would remove the polyfill hacks and enable the unit/integration split cleanly).

### What testing is missing (ranked by risk)

1. **`lib/auth.ts` + `lib/jwt.ts` — zero unit tests, and JWT signing/verification is stubbed everywhere.** Expiry, claims, tampered tokens, and the bearer-path behavior in SEC-2 are all unverifiable today. Un-stub `jose` for a dedicated `jwt.test.ts` (it runs fine in Jest with the existing transform config).
2. **The entire `/api/library/**` surface\*\* (add/remove, checks, lists CRUD, reorder) — no unit tests; only reachable via the skipped contract suite.
3. **Core playback path on web**: `PlaybackClient` untested; `app/api/audio/[...path]` (range requests! the thing iOS seeking depends on) and `app/api/images/[...path]` untested — the two routes where a regression means "the app stops working."
4. **`lib/rate-limit.ts`, `lib/media.ts`, `api-utils.ts`** — small, pure, high-fan-in; cheap to cover.
5. **Books route pagination/sort behavior** (would have caught D-3).
6. **For the upcoming restore feature**: the plan's Ring-1 tests (mocked `HeadObject`/`RestoreObject`) need `aws-sdk-client-mock`; the S3 mocking pattern established there should also backfill `lib/s3.ts` streaming-range tests.

### Recommended test-suite changes

1. Fix the glob override (pin only where needed, or drop it) → coverage works → add a modest `coverageThreshold` to prevent regression.
2. Split Jest into projects: `unit` (node env for API/lib, jsdom for components) and `integration` (downloads + future DB tests, run via `test:integration` with the DB up). `npm test` = unit only, always green.
3. Add `test:contract` to `validate:full` (it already manages its own server lifecycle).
4. Write `jwt.test.ts` + `auth.test.ts` with real jose.
5. Delete the meaningless tests: the 2 wall-clock performance suites, the 4 "verify no errors" AudioPlayer tests (replace with real seek/skip assertions via a stubbed media element), the Tailwind-class assertion, and the 24 iOS placeholders (or fill them).
6. Reuse Storybook stories in RTL tests via `composeStories` — 10 stories currently contribute zero regression coverage.

---

## Part 3: Prioritized Action Plan

### P0 — Before anything else (~half a day)

1. Auth (or content-restrict) `/api/images/[...path]` — SEC-1
2. Admin-gate `POST /api/books/[id]/chapters`; UUID-validate series route — SEC-3
3. Fix the glob override so coverage works; update STATUS.md's stale "all tests passing" claim

### P1 — Pre-feature hardening (~1–1.5 days, do before restore-feature Phase 0)

4. `requireUser()` helper + `errorResponse()` helper; migrate routes (mechanical, ~34 sites) — D-1, D-2
5. Partition Jest (unit vs integration); wire `test:contract` into `validate:full`
6. `jwt.test.ts`/`auth.test.ts` with real jose; decide SEC-2 posture and test it
7. Fix `/api/books` limit cap + remove phantom filters/broken sorts — D-3
8. Delete verified dead code (`api-url.ts`, `ProgressBadge.tsx`, `formatRuntime` copies; decide `api-schemas.ts`)
9. iOS: route `DownloadManager`'s two `URLSession.shared` calls through the injected seam (the restore feature touches exactly these)

### P2 — Opportunistic (fold into feature work or do later)

10. `error.tsx`/`loading.tsx`/`not-found.tsx`; shared client-fetch helper with error states — D-5
11. AudioPlayer: extract `useProgressSaver` + `useMediaElement` hooks; add `dark:` variants (do alongside the restore-feature player changes, which touch this component anyway)
12. iOS: split `AudioPlayerManager`; collapse `APIClient.execute` duplication; fix refresh-coordinator check-then-act gap
13. Consolidate progress components; unify cover-URL convention; `createMany` for series-add
14. Document or fix single-instance rate-limit/cache assumptions
15. Storybook `composeStories` reuse; delete/replace no-op tests

### Explicitly not recommended

- No framework changes, no state-management library for the web app (the server-component architecture is right), no iOS rearchitecture (the DI foundation is sound), no test-runner migration. The codebase's shape is good; it needs seams tightened, not walls moved.

---

## Relationship to the S3 Restore Feature

The restore feature multiplies exposure to exactly the weak spots found here: it adds ~6 authenticated routes (build them on `requireUser`, not 6 more copies), extends the downloads endpoint and iOS `DownloadManager` (fix the `URLSession.shared` bypass first), adds S3-mocked tests (needs the Jest partition + working coverage), and adds UI to the player surfaces (the dark-mode and error-state gaps become more visible). Doing P0+P1 first (~2 days) makes the feature cheaper and safer to build; deferring the rest is fine.
