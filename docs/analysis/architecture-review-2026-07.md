# Architecture & Test Review — July 2026

> **Original**: July 12, 2026 — full application review conducted before the S3 archive/restore feature.
> **Refreshed**: July 19, 2026 — every finding below was **independently re-verified against current code** (three parallel verification passes with file:line evidence). Status tags reflect the July 19 state.
> **Scope**: backend (app/api, lib), web frontend, iOS app, schema, test suites, validation/CI tooling.

---

## What changed between July 12 and July 19

Two large bodies of work landed after the original review and substantially closed its gaps:

1. **Pre-restore hardening (PRs #75–#79)** — fixed the P0 security holes and the test-infrastructure defects.
2. **Dependency major-upgrade ladder (PRs #88–#101)** — see [archive/completed-plans/dependency-major-upgrades.md](../archive/completed-plans/dependency-major-upgrades.md). Net result:
   - **Next 14 → 16**, **React 18 → 19**, **Prisma 5 → 6**, **Storybook → 10.5**, **zod 3 → 4**, **undici → 8**; **`node-fetch` removed** (was unused).
   - **Runtime Node 20 → 24 (Active LTS)** across Docker + CI; the AWS SDK `NodeVersionSupportWarning` is gone.
   - **Deploy build fixed**: cross-arch amd64 (qemu segfault on the Next 16 SWC binary) → **native arm64 / Graviton** (`book-vault:5` task def, healthy in prod).
   - **`npm audit`: 0 high / 0 critical** (4 framework-internal moderates remain).
   - Test infra hardened: Jest partitioned (unit vs `JEST_INTEGRATION` integration), coverage tooling fixed with a `coverageThreshold` ratchet, and **contract + integration suites now run in both `validate:full` and GitHub CI**.
   - Real-DB `$transaction` integration coverage added (`progress/batch`, `refresh`, `reorder`).

**The only remaining dependency-ladder item is Prisma 6 → 7** (its own plan, "Phase 5b" — ESM + `prisma.config.ts` + driver adapter + generated-client path move; unblocked by Node 24, guarded by the new real-DB coverage). Deferred by design: TypeScript 7 (typescript-eslint incompatible until ~TS 7.1, Oct 2026 — would break `npm run lint`), Tailwind 4 (CSS-first overhaul, UI-regression risk, no visual-regression net), eslint 10 (coupled to the TS 7 churn).

---

## Executive Summary (refreshed)

The July 12 verdict — "good architectural shape for its size; concentrated, specific debt, not systemic" — still holds, and the codebase is now **materially healthier**: every P0 security hole and every test-infrastructure defect from the original review is resolved and verified.

What **remains open** (all lower-severity, none blocking):

- **Two security items**: **SEC-2** (mobile bearer path doesn't re-check the DB, so a deleted user's token works until expiry — single-user app, low practical risk) and **half of SEC-4** (ffprobe still invoked via shell-string `exec` with no timeout, in a request handler).
- **Web resilience (D-5)**: still no `error.tsx`/`loading.tsx`/`not-found.tsx` boundaries; client fetches still have no user-visible error state; the AudioPlayer still has **zero `dark:` variants**.
- **Consistency/debt**: no `errorResponse()` helper (D-2); the `/api/books` limit-cap fix (D-3) was **not** applied to the analogous `lib/api-helpers.ts` entity-detail path; the POST /chapters handler still leaks `error.message`; per-instance rate-limit/cache assumptions (D-4) remain undocumented.
- **Test tail**: the library add/remove/check/lists routes still lack unit tests (reorder is covered via integration); the real `rate-limit` path is only exercised in the gated integration suite; a handful of low-value component tests ("verify no errors", Tailwind-class assertions) remain; one misnamed `performance.test.ts`.

**Verdict**: no blocker to the S3 restore feature. The remaining items are a modest, well-understood backlog — fold the resilience + `dark:` items into the restore-feature UI work (which touches those exact surfaces), and address SEC-2/SEC-4 and the `api-helpers` limit cap as small standalone fixes.

### Scorecard (July 12 → July 19)

| Area                           | Was   | Now    | What moved it                                                                                    |
| ------------------------------ | ----- | ------ | ------------------------------------------------------------------------------------------------ |
| Data layer / schema            | A−    | **A−** | Unchanged; Prisma 5→6 clean, singleton discipline intact                                         |
| Backend API design             | B     | **B+** | `requireUser` extracted + fully adopted (26 routes, 0 inline auth); books correctness fixed      |
| Web frontend                   | B     | **B−** | No regressions, but D-5 (boundaries, error UX, AudioPlayer dark mode) still entirely open        |
| iOS app                        | A−    | **A−** | 24 `XCTAssertTrue(true)` placeholders removed; god-objects/`URLSession.shared` bypass still open |
| Test effectiveness             | C+    | **B+** | Real-jose auth/JWT tests, audio-range + images tests, real-DB `$transaction` tests added         |
| Test/validation infrastructure | C     | **A−** | Jest partitioned; coverage fixed + ratcheted; contract **and** integration now in CI             |
| API governance (OpenAPI-first) | A     | **A**  | Unchanged — still exemplary                                                                      |
| Dependency / supply-chain      | (n/a) | **A−** | 0 high/critical; on current LTS Node 24 + current framework majors; one Prisma major remaining   |

---

## Part 1: Design Findings — status

### Security

| ID                                | July 12      | July 19           | Evidence                                                                                                                                                                                                                                                                                                                |
| --------------------------------- | ------------ | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SEC-1** images route unauth     | P0 open      | ✅ **FIXED**      | `app/api/images/[...path]/route.ts:24-26` dual-auth; `:11,30-33` extension allowlist; `Cache-Control: private`. _Minor caveat:_ content-type is trusted from S3, not derived from the allowlisted extension — the audiobook-download vector is closed, but a non-image body under an image extension would still serve. |
| **SEC-2** deleted user on bearer  | P0 open      | ⚠️ **STILL-OPEN** | `lib/auth.ts` web session re-checks DB (`:59-73`); the bearer path `getAuthUserFromRequest` (`:99-127`) → `verifyAccessToken` (`jwt.ts:51-70`) does pure crypto, no DB lookup. `requireUser` inherits the gap. Deleted user's token valid ~1h. Low practical risk (single-user), but the two channels still disagree.   |
| **SEC-3** content-mutating routes | P0 open      | ✅ **FIXED**      | `chapters/route.ts:191-201` POST now `requireAdmin` + `normalizeUuid`; `library/series/[seriesId]/route.ts:16-19` now `isValidUuid`-guards (POST + DELETE).                                                                                                                                                             |
| **SEC-4** hardening nits          | P0(low) open | ⚙️ **PARTIAL**    | Path check fixed — `media.ts:28-34` now uses `resolvedPath === mediaDir                                                                                                                                                                                                                                                 |     | startsWith(mediaDir + path.sep)`. **ffprobe NOT fixed** — `audio-metadata.ts`still`exec`with shell-string interpolation + manual`\"` escaping and **no timeout** (`:81-86,147-151`); runs unbounded inside a request handler. Switch to `execFile(args[])` + timeout. |

### Design improvements

| ID                                  | July 19             | Evidence / note                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ----------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **D-1** `requireUser` extraction    | ✅ **FIXED**        | `lib/api-auth.ts:26-36` (discriminated union). 26 route files adopt it; **0** inline `getServerSession`/`getAuthUserFromRequest` remain in `app/api/`.                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **D-2** error/logging consistency   | ⚙️ **PARTIAL**      | `logger` adoption 2 → 36 files; `console.error` in `app/api` down to 8 files. **But** no `errorResponse()` helper was added, and **POST /chapters still leaks `error.message`** to clients (`chapters/route.ts:301-306`). GET-chapters leak is fixed.                                                                                                                                                                                                                                                                                                                           |
| **D-3** `/api/books` correctness    | ✅ **FIXED**        | Phantom filters removed from JSDoc + code; page-only sort removed (DB `orderBy`); `parsePagination` caps limit at 100. **New**: the _same_ uncapped-limit bug survives in `lib/api-helpers.ts:101` (entity-detail endpoints) — `parseInt(limit                                                                                                                                                                                                                                                                                                                                  |     | '20')`with no cap. Migrate it to`parsePagination`. |
| **D-4** single-instance assumptions | ⚠️ **OPEN**         | `rate-limit.ts` progress limiter still in-memory `Map` + `setInterval`, undocumented; `admin-cache.ts` still per-instance FIFO. (The _download_ limiter is correctly DB-backed.) **Correction (July 19, evening): the single-task premise is already violated — `book-vault-spot` runs desiredCount 2**, so the in-memory progress limiter and admin-cache are split across tasks _today_ (per-task limits; per-task cache staleness). Low severity for a single-user app, but the fix is now "make it DB-backed or accept and document per-task behavior", not just a comment. |
| **D-5** web resilience              | ⚠️ **OPEN (all 3)** | (a) still no `error.tsx`/`loading.tsx`/`not-found.tsx` anywhere in `app/`. (b) client fetches still swallow to `console.error` with no user-facing state — though `AddToLibraryButton` now guards on `res.ok` (`:56,74,92,111`), a failed add just silently no-ops. (c) `AudioPlayer.tsx` still has **0** `dark:` classes (hard-coded `bg-white`/`text-gray-*`). **Fold into the restore-feature UI work — it lands on these exact surfaces.**                                                                                                                                  |
| **D-6** iOS structural debt         | ⚠️ **OPEN**         | `AudioPlayerManager` god-object and `APIClient.execute` duplication + refresh check-then-act gap remain open. **Correction (July 19, evening): `DownloadManager`'s `URLSession.shared` bypasses were in fact FIXED in the hardening (#79)** — eligibility/URL-generation now go through the injected `APIClientProtocol` (`DownloadManager.swift:546,559`), so the restore feature's 202-handling there is mock-testable as-is. Residual raw `URLSession.shared` lives in `LibraryManager` (1) and `SearchManager` (4) — their own request executors, outside the restore path. |

### Dead code / cleanup

| Item                                                       | July 19                                                                                                                                               |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/api-url.ts`                                           | ✅ already deleted                                                                                                                                    |
| `components/ProgressBadge.tsx` (+ story + test)            | ✅ already deleted                                                                                                                                    |
| inline `formatRuntime` ×4 / `formatTime` ×2                | ✅ consolidated — `lib/utils/formatRuntime.ts` & `formatTime.ts` now the live single sources (do NOT delete)                                          |
| `__mocks__/@/lib/prisma.ts`                                | 🧹 **still a delete-safe orphan** — targets `@/lib/prisma` (doesn't exist; real client is `@/lib/db`), not wired by `jest.config.js`. Safe to delete. |
| N+1 series-add loop (`library/series/[seriesId]/route.ts`) | ⚠️ still per-book `findUnique`+`create`; `createMany({skipDuplicates})` still wanted                                                                  |

---

## Part 2: Test Review — status

### Test-infrastructure defects — all ✅ FIXED

1. **`npm test` red on fresh machine** → Jest now has three projects (`jest.config.js:80-116`); default export ships only `unit-node` + `unit-dom`, and `integration` is pushed **only** when `JEST_INTEGRATION=true`. The downloads test moved to `__tests__/integration/`. `npm test` is unit-only and green without Docker.
2. **Coverage tooling broken** → works now; `coverageThreshold` ratchet at `jest.config.js:138-145` (37/36/38/37). The `glob`/`test-exclude` overrides resolve cleanly; coverage artifacts regenerate.
3. **Contract suite orphaned from CI** → `validate.sh` → `run_db_suites` runs **both** `test:contract` and `test:integration`; `api.yml`'s `contract-tests` job runs the integration suite (`:153-158`) **and** contract tests (`:180-185`) against a `postgres:15` service. Both layers now gate PRs.

### Missing tests (ranked) — status

1. **`lib/auth.ts` + `lib/jwt.ts`** → ✅ **FIXED** — `__tests__/lib/jwt.test.ts` + `auth.test.ts` use **real jose**: sign/verify roundtrip, expiry, tampered payload, wrong-secret rejection, and a structural assertion that the bearer path never hits the DB (which is also the evidence for SEC-2).
2. **`/api/library/**`** → ⚙️ **PARTIAL** — only `series-route.test.ts` has unit coverage; `reorder` is covered end-to-end via `integration/transaction-routes.test.ts`. `library/route` (add/list), `library/check`, `library/[bookId]` (remove), `library/lists*` still lack unit tests.
3. **Playback routes** → ✅ **FIXED** — `__tests__/api/audio/route.test.ts` tests HTTP Range (206 + `Content-Range`, 416, open-ended, local + S3); `images/route.test.ts` tests auth + allowlist + traversal.
4. **`lib/rate-limit.ts`, `lib/media.ts`, `api-utils.ts`** → ⚙️ **PARTIAL** — `media` ✅ (incl. the sibling-prefix case), `api-utils` ✅ (`parsePagination`/`parseBookFields`). `rate-limit`'s real path runs **only** in the gated integration suite; the default unit run always mocks it.

### Low-value tests flagged for deletion — status

- 4 AudioPlayer "verify no errors" tests → ⚠️ **still present** (`AudioPlayer.test.tsx:126,229,301,313` — tautological `toBeInTheDocument()` after "verify no errors"). Replace with real seek/skip assertions via a stubbed media element.
- Tailwind-class assertions → ⚠️ **still present** (AudioPlayer `:163,213`; also `BookGrid`, `BackButton`, `Pagination`). Assert behavior/roles, not class strings.
- 2 wall-clock perf suites → ⚙️ **1 of 2 remain** — `books/chapters-performance.test.ts:235` still has `toBeLessThan(1000)` on mocked Prisma; `app/api/search/performance.test.ts` was repurposed into a real `api-utils` test (but is now **misnamed** — rename to reflect it tests pagination parsing, and drop the stale coverage HTML).
- 24 iOS `XCTAssertTrue(true)` placeholders → ✅ **all removed** (0 matches in `ios/`).

---

## Part 3: Prioritized Action Plan (refreshed)

The original P0/P1 are done. What remains, re-prioritized:

### Small standalone fixes (~half day total)

1. **SEC-4 ffprobe** — switch `lib/audio-metadata.ts` to `execFile(['ffprobe', ...args])` + a timeout. Removes a shell-injection surface and an unbounded call in a request handler.
2. **`lib/api-helpers.ts` limit cap** — route the entity-detail pagination through `parsePagination` (the D-3 fix, unmigrated here). One-line class of bug, currently `limit=1000000` honored on author/narrator/series/category detail.
3. **POST /chapters leak** — stop returning `details: error.message`; log it, return a generic message (matches the GET handler).
4. **Delete the orphan** `__mocks__/@/lib/prisma.ts`; rename the misnamed `app/api/search/performance.test.ts`.

### SEC-2 — decide the posture (not just patch)

Either accept token-lifetime staleness on **both** auth channels and document it (reasonable for a single-user app), or add a DB existence check to the bearer path to match the web session. Pick one and write the test (the auth test already asserts the _current_ no-DB behavior, so changing it is a deliberate contract change).

### Fold into the S3 restore feature (it touches these exact surfaces)

5. **D-5 web resilience** — add `error.tsx`/`loading.tsx`/`not-found.tsx`, a shared client-fetch helper with error state, and **`dark:` variants on the AudioPlayer** (the restore UI — `ArchiveStatusBadge`/cold-storage warnings — lands on the player and detail surfaces).
6. ~~**D-6 iOS** — route `DownloadManager`'s `URLSession.shared` calls through the injected seam~~ — **already done in #79** (verified July 19 evening); no blocker for the restore feature's 202-handling.
7. **Test tail** — as the restore feature adds S3-mocked tests (`aws-sdk-client-mock`), backfill unit tests for the untested `library/**` routes and replace the low-value AudioPlayer tests with real assertions.

### Opportunistic / later

8. `errorResponse()` helper (D-2); document or DB-back the per-instance rate-limit/cache (D-4); `createMany` for series-add; Storybook `composeStories` reuse; a `rate-limit` unit test that runs in the default suite.
9. **Prisma 6 → 7** — the one remaining dependency major; its own plan.

### Explicitly still not recommended

No framework changes beyond the ladder already in progress, no web state-management library, no iOS rearchitecture. The shape is right; this is seam-tightening, not wall-moving. (Original review's judgment, unchanged.)

---

## Relationship to the S3 Restore Feature

The original coupling still holds, now with most prerequisites met: `requireUser` exists (build the ~6 new routes on it), Jest is partitioned with working coverage + CI-enforced contract/integration suites (S3-mocked tests have a home), and the deploy path is stable on native-arm64/Graviton. The two things still worth doing **before/within** the feature: fix the iOS `DownloadManager.URLSession.shared` bypass (the feature adds 202-handling there), and land the D-5 resilience + AudioPlayer `dark:` work alongside the restore UI that lands on those surfaces. Phase 0 (on-demand stream endpoint, PR #88) is already merged.
