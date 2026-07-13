# Pre-Restore Hardening Plan (P0 + P1)

> **Created**: July 12, 2026
> **Status**: Planned
> **Source**: [analysis/architecture-review-2026-07.md](../analysis/architecture-review-2026-07.md) — this plan turns that review's P0/P1 items into executable specs. P2 items remain as backlog in the review doc.
> **Sequencing**: Complete before Phase 0 of [s3-archive-restore-workflow-v2.md](./s3-archive-restore-workflow-v2.md). The restore feature adds ~6 authenticated routes, extends the downloads endpoint/iOS DownloadManager, and adds S3-mocked tests — every item here reduces its cost or risk.
> **Estimated effort**: P0 ≈ half a day, P1 ≈ 1.5 days. Suggested as 4 PRs (see [PR breakdown](#pr-breakdown)).

---

## Decisions (recommended defaults — veto before implementation starts)

| #   | Decision                                    | Recommended default                                                                                                                                                                                               | Alternative considered                                                                                      |
| --- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| D1  | How to fix the unauthenticated images route | **Dual-auth + image-extension allowlist + `Cache-Control: private`**, plus a ~5-line iOS change so dev builds attach the bearer token to cover downloads                                                          | Allowlist-only (keeps covers public/cacheable, zero client changes) — weaker but acceptable                 |
| D2  | Deleted-user bearer tokens (SEC-2)          | **Accept access-token-lifetime staleness (≤1 h) on both channels; refresh is the revocation point.** Document it and pin with a test                                                                              | Per-request DB existence check (adds a query to every mobile API call — not worth it for a single-user app) |
| D3  | Fate of `lib/api-schemas.ts` (514 LOC)      | **Keep the Zod validation suite, move the file to `__tests__/helpers/api-schemas.ts`** — it is imported only by the gated type-validation test; relocating makes its test-only role structural instead of implied | Delete it and rely solely on `jest-openapi` (loses stricter-than-spec type assertions)                      |
| D4  | `POST /api/books/[id]/chapters` gating      | **Admin-gate via `requireAdmin`** (re-extraction is a legitimate admin operation). `GET` stays user-level — lazy extraction on first playback is a product feature                                                | Remove the POST entirely                                                                                    |

---

## P0 Items

### P0-1: Secure `/api/images/[...path]` (SEC-1)

**Current state**: [app/api/images/[...path]/route.ts](../../app/api/images/%5B...path%5D/route.ts) has no auth and streams any S3 key — the full audiobook library is downloadable unauthenticated via predictable keys.

**Changes** (per D1):

1. Add the dual-auth check (session OR bearer) at the top of the handler — same block as `audio/[...path]`; after P1-1 lands, both switch to `requireUser()`.
2. Add an extension allowlist as defense-in-depth, applied in BOTH the S3 and local branches:
   ```typescript
   const ALLOWED_IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
   if (!ALLOWED_IMAGE_EXTENSIONS.includes(path.extname(filePath).toLowerCase())) {
     return NextResponse.json({ error: 'Not found' }, { status: 404 });
   }
   ```
3. Change `Cache-Control` from `public, max-age=31536000, immutable` to `private, max-age=31536000, immutable` (browser may cache; shared caches may not).
4. **iOS companion change**: [CoverCacheManager.swift:146](../../ios/BookVault/Services/CoverCacheManager.swift#L146) uses `URLSession.shared.data(from:)` with no auth. Production covers are presigned S3 URLs (unaffected); dev covers are `/api/images/...` URLs and will start returning 401. Fix: build a `URLRequest` and attach the bearer token when the URL's host matches the API base URL's host; leave S3/other hosts untouched.
5. While in the file: fix `validateMediaPath` (SEC-4) to compare against `mediaDir + path.sep` (or use `path.relative` and reject `..` prefixes) — [lib/media.ts:28-32](../../lib/media.ts#L28-L32).

**Tests** (new `__tests__/api/images/route.test.ts`):

- 401 for unauthenticated request
- 200 + correct content-type for an authenticated image request (local branch, test-data fixture)
- 404 for an authenticated request targeting a non-image extension (`.m4b`)
- `validateMediaPath` unit cases including the sibling-prefix case (`/data/media-evil` vs `/data/media`)

**Acceptance**: `curl` against a dev server confirms 401 unauth / 200 authed / 404 for `.m4b`; web covers still render (session cookie); iOS dev build covers still render.

### P0-2: Authorization gaps (SEC-3)

1. `POST /api/books/[id]/chapters` → gate with `requireAdmin` (per D4). Update the OpenAPI spec (the operation's description/security should reflect admin-only) and regenerate types.
2. `POST /api/library/series/[seriesId]` → add `normalizeUuid(params.seriesId)` + 400 on invalid, matching sibling routes.
3. Tests: 403 for non-admin chapter POST; 400 for malformed series UUID.

### P0-3: Fix coverage tooling

**Current state**: `jest --coverage` crashes in istanbul instrumentation (`test-exclude` calls `promisify(glob)`; glob ≥9 has no callback API). Cause: `"overrides": { "glob": "^11.0.0" }` in package.json.

**Changes**:

1. Check why the override exists (`git log -S '"glob"' -- package.json`, `npm audit`). If it was a blanket deprecation/vulnerability silence, remove it entirely; if a specific dependency needs new glob, scope the override to that dependency only (npm supports nested overrides: `{ "overrides": { "<pkg>": { "glob": "^11" } } }`).
2. Verify `npx jest --coverage` produces real numbers and all suites still pass.
3. Record the measured baseline in this file, then add `coverageThreshold.global` to jest.config.js set ~3 points below baseline (ratchet up later; the goal is preventing silent regression, not hitting a number).

**Acceptance**: `npm run test:coverage` exits 0 with a non-zero coverage table.

### P0-4: Truth in STATUS.md

Update [docs/STATUS.md](../STATUS.md): remove/correct "All tests passing" (unit suite requires Docker DB today; coverage was unmeasurable), link the architecture review, and list this plan + the restore plan under Next Up. Keep it to a handful of lines.

---

## P1 Items

### P1-1: `requireUser()` + `errorResponse()` helpers, migrate ~34 sites

**New file `lib/api-auth.ts`** (mirrors `requireAdmin`'s discriminated-union shape):

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';

export type AuthedUser = { id: string; username: string };

export type RequireUserResult =
  | { user: AuthedUser; error?: never }
  | { user?: never; error: NextResponse };

/** Dual auth: web session cookie OR mobile bearer token. */
export async function requireUser(request: NextRequest): Promise<RequireUserResult> {
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = (session?.user as AuthedUser | undefined) || mobileUser;
  if (!user) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  }
  return { user };
}
```

**New helper in `lib/api-utils.ts`** (or alongside):

```typescript
export function errorResponse(status: number, message: string): NextResponse {
  return NextResponse.json({ error: message }, { status });
}
```

**Migration**: replace the inline block in all 23 route files (~34 handler occurrences — grep `getServerSession` under `app/api`, excluding `[...nextauth]`):

```typescript
const auth = await requireUser(request);
if (auth.error) return auth.error;
const user = auth.user;
```

Rules: behavior-identical (same 401 body/status); normalize any bare `Response` usages to `NextResponse` while touching; normalize `{ message }` error bodies to `{ error }` (7 occurrences — check the OpenAPI spec for each before changing; update spec if it documents `message`). Adopt `logger.error` instead of `console.error` in files touched.

**Tests**: unit tests for `requireUser` (session-only, bearer-only, both, neither); the existing route tests must pass unchanged (they mock `@/lib/auth`, which stays the underlying seam — mocks of `getAuthUserFromRequest` keep working since `requireUser` calls it).

**Acceptance**: `grep -rn "getServerSession" app/api --include=route.ts` returns only `[...nextauth]` and `lib` files; `npm test` + `npm run test:contract` green.

### P1-2: Partition Jest into unit vs integration

**Target layout** (jest.config.js `projects`):

| Project       | Environment | Matches                                                                                                 | Runs in                         |
| ------------- | ----------- | ------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `unit-node`   | node        | `__tests__/api/**`, `__tests__/lib/**`, `__tests__/scripts/**` (minus integration list)                 | `npm test`                      |
| `unit-dom`    | jsdom       | `__tests__/components/**`, `__tests__/pages/**`                                                         | `npm test`                      |
| `integration` | node        | `__tests__/integration/**` (move `api/downloads/route.test.ts` + `scripts/seed-test-user.test.ts` here) | `npm run test:integration` only |

Implementation notes:

- Each project is wrapped with `next/jest`'s `createJestConfig` (call it per-project; it returns an async config — export an async function resolving all three).
- `npm test` → `jest --selectProjects unit-node unit-dom`; new script `test:integration` → `docker-compose up -d && prisma migrate deploy && jest --selectProjects integration` (or a small shell script mirroring existing conventions).
- The undici/fetch polyfills in `jest.setup.js` become node-project-only (or unnecessary there); keep jsdom setup separate.
- Move the `jose` mock out of global `moduleNameMapper` (see P1-4) — the mapping currently force-stubs jose for every test.
- Contract tests (`openapi-contract`, `api-types-validation`) stay env-gated as today; they belong to `unit-node` matching but self-skip without `RUN_CONTRACT_TESTS`.

**Acceptance**: fresh clone, no Docker: `npm test` fully green. With Docker up: `npm run test:integration` green. CI docs (`docs/testing.md`) updated.

### P1-3: Run contract tests in `validate:full`

Add a step to [scripts/validate.sh](../../scripts/validate.sh) after the unit-test step: `npm run test:contract`. Precondition: the dev server needs the DB — add an early check (`docker-compose ps` / port 5433 probe) with a clear error message telling the user to start Docker. Update `docs/testing.md`.

**Acceptance**: `npm run validate:full` executes the live contract assertions (visible in output: N contract tests run, not skipped) and fails if a handler drifts from the spec.

### P1-4: Real JWT/auth tests

1. Remove the global `jose` stub from `moduleNameMapper` (jest.config.js `'^jose$'` / `'^.*/jose$'` entries). Suites that relied on it (`auth/mobile/*` tests) switch to explicit `jest.mock('@/lib/jwt')` — mocking OUR boundary, not the crypto library.
2. New `__tests__/lib/jwt.test.ts` with real jose: sign→verify roundtrip asserts claims (userId, username, exp); expired token rejected; tampered payload/signature rejected; token signed with wrong secret rejected.
3. New `__tests__/lib/auth.test.ts` for `getAuthUserFromRequest`: valid bearer → user; malformed/missing header → null; expired token → null. **Pin D2 with an explicit test**: a valid token for a since-deleted user still resolves (document why in the test name/comment), and the refresh route rejects the deleted user (that test likely exists in mobile refresh tests — verify, add if missing).
4. The transformIgnorePatterns already handle jose ESM — no config change needed there.

**Acceptance**: auth/JWT behavior is pinned by tests that would fail on an expiry, claim, or verification regression.

### P1-5: `/api/books` correctness fixes

1. Replace raw `parseInt` with the existing `parsePagination` (caps limit at 100) — [app/api/books/route.ts:50-51](../../app/api/books/route.ts#L50-L51).
2. Delete the JSDoc for the four never-implemented filters (`authorId/narratorId/categoryId/seriesId`). Do not implement them now — the entity-detail routes already serve those views.
3. Remove the broken `sort=author|narrator|series` page-local sorting: check `docs/api/openapi.yaml` first — if the spec advertises these sort values, remove them from the spec too, regenerate types (TS + Swift), and confirm neither web nor iOS sends them (grep `sort=` usages). If a client uses them, DB-side sorting via relation is the fallback — but removal is preferred.
4. Tests: limit is capped (request `limit=5000` → 100); default sort stable.

### P1-6: Dead code deletion / consolidation

| Action        | Files                                                                                                                                                                                                                                                                                               |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Delete        | `lib/api-url.ts`                                                                                                                                                                                                                                                                                    |
| Delete        | `components/ProgressBadge.tsx` + `ProgressBadge.stories.tsx` + its test (verified unused; keep `ProgressStatus`/`ProgressControls` — their `useProgress` consolidation is P2)                                                                                                                       |
| Move          | `lib/api-schemas.ts` → `__tests__/helpers/api-schemas.ts` (per D3); update the one import in `api-types-validation.test.ts`; exclude helpers dir from `testMatch`                                                                                                                                   |
| Consolidate   | Point `BookCard.tsx`, `books/[id]/page.tsx`, `books/[id]/play/page.tsx`, `library/page.tsx` at `lib/utils/formatRuntime.ts`; delete the four inline copies (diff-check the implementations first — if they differ, the lib version wins and snapshots of rendered output confirm no visible change) |
| Consolidate   | `formatTime` from `AudioPlayer.tsx` + `ChapterList.tsx` → `lib/utils/formatTime.ts` with a unit test                                                                                                                                                                                                |
| Delete (iOS)  | `ios/BookVault.xcodeproj.backup/`, nested `ios/ios/`, `ios/archive/`, `ios/build/`; add `ios/build/` to `.gitignore` if absent; run `xcodegen generate` + build to confirm nothing referenced them                                                                                                  |
| Delete (root) | `debug-storybook.log`, stray `~` file, `.tmp/` if present                                                                                                                                                                                                                                           |

**Acceptance**: `npm run validate` green; `grep -rn "api-url\|ProgressBadge"` in app/components returns nothing (README mentions updated); iOS builds clean.

### P1-7: iOS — route DownloadManager's stray network calls through the DI seam

**Current state**: `checkEligibility` and `generateDownloadUrl` use `URLSession.shared` directly (~[DownloadManager.swift:557,598](../../ios/BookVault/Services/DownloadManager.swift#L557)) with a hand-rolled `createAuthenticatedRequest`, bypassing `APIClient`'s auth/refresh/error handling and the test seam. **The restore feature's 202-handling lands on exactly these calls — fix the seam first.**

1. Add typed methods to `APIClient` (+ `APIClientProtocol`): `checkDownloadEligibility(bookId:)` and `generateDownloadUrl(bookId:deviceId:)`, using the existing generic `execute` path (gains token refresh + consistent errors for free).
2. `DownloadManager` calls these via its injected `apiClient`; delete `createAuthenticatedRequest` and the two inline `URLSession.shared` calls + hand-rolled decoding.
3. Update/extend `BookVaultTests/Services/Real/DownloadManagerRealTests` to cover both calls through `MockURLProtocol` (success, 401→refresh→retry, network failure). Remove any placeholder assertions touched.

**Acceptance**: `npm run ios:test` green; `grep -n "URLSession.shared" ios/BookVault/Services/DownloadManager.swift` returns nothing.

---

## PR Breakdown

| PR                      | Contents                                      | Est. |
| ----------------------- | --------------------------------------------- | ---- |
| 1 — Security P0         | P0-1, P0-2, P0-4 (+ iOS cover-auth companion) | ~3h  |
| 2 — Test infrastructure | P0-3, P1-2, P1-3, P1-4                        | ~4h  |
| 3 — Backend cleanup     | P1-1, P1-5, P1-6 (web/lib parts)              | ~4h  |
| 4 — iOS cleanup         | P1-7, P1-6 (iOS artifact deletion)            | ~2h  |

Each PR: `npm run validate` locally; PR 2 onward also `npm run validate:full` (now including contract tests); PR 4 runs `npm run ios:validate`. Order matters only in that PR 3's `requireUser` migration should land after PR 1 (images route then switches to the helper as part of PR 3's sweep).

## Out of Scope (P2 backlog — see review doc §Part 3)

Error/loading boundaries, shared client-fetch helper, AudioPlayer hook extraction + dark mode (fold into restore-feature Phase 4), iOS god-object splits, APIClient execute dedup, refresh-coordinator atomicity, progress-component consolidation, cover-URL convention unification, `createMany` series-add, rate-limit/cache single-instance documentation, Storybook `composeStories`.
