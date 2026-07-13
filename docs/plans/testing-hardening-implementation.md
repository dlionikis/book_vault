# Testing Hardening — Implementation Plan

> **Date**: July 13, 2026
> **Source**: [testing-coverage-review.md](testing-coverage-review.md) (findings + annotated re-prioritization)
> **Ordering rationale**: single-user app, manual release process, owner-QA on every TestFlight build. Cheap security-adjacent unit work first, Playwright web smoke second (before the S3 restore feature adds UI states), XCUITest demoted to P2.

---

## Phase 0 — Land #79, re-measure, ratchet (BLOCKING — do first)

Everything below assumes #79's tree: the three-project Jest config, real-jose tests, and the iOS `DownloadManager`→`APIClient` seam.

1. **Merge PR #79** (`hardening/p1-backend-cleanup` → `main`). It exists because #76–#78 merged into stacked parent branches instead of main.
2. **Re-measure coverage** on the new baseline: `npm run test:coverage` — NOT bare `npx jest --coverage`, which would run all three Jest projects including `integration` (requires Docker) and skew the measurement relative to the threshold's unit-only scope. Do NOT assume the review's 39/36/40/40 — #79 changes both numerator (new jwt/auth tests) and denominator (project split; downloads tests moved to the `integration` project).
3. **Ratchet `coverageThreshold`** in `jest.config.js` from 34/32/35/34 up to the newly measured floor (round down to integers).
4. Re-run `npm run validate` to confirm the gate holds.

**Done when**: #79 on main, thresholds equal measured floor, validate green.

---

## Phase 1 — iOS placeholder cleanup (24 stubs)

Every stub below is `XCTAssertTrue(true)`. Disposition per stub, based on verified Real-test equivalents:

### `ios/BookVaultTests/Services/APIClientTests.swift` (13 stubs)

| Stub                                                 | Disposition      | Covered by                                                                                |
| ---------------------------------------------------- | ---------------- | ----------------------------------------------------------------------------------------- |
| `testRequestIncludesContentTypeHeader`               | **Delete**       | `APIClientRealTests.testRequestIncludesCorrectContentType` (L478)                         |
| `testAuthenticatedRequestIncludesBearerToken`        | **Delete**       | `APIClientRealTests.testAuthorizationHeaderIncludedWhenTokenSet` (L454)                   |
| `testUnauthenticatedRequestOmitsAuthorizationHeader` | **Port to Real** | No equivalent — add to `APIClientRealTests` with MockURLProtocol asserting header absence |
| `testDecodesISO8601DateWithFractionalSeconds`        | **Delete**       | `ModelDecodingTests` date-format cases                                                    |
| `testDecodesISO8601DateWithoutFractionalSeconds`     | **Delete**       | `ModelDecodingTests`                                                                      |
| `testDecodesDateOnlyFormat`                          | **Delete**       | `ModelDecodingTests`                                                                      |
| `testHandles401AsUnauthorized`                       | **Delete**       | `APIClientRealTests.testLoginUnauthorizedError` (L205)                                    |
| `testHandles404AsNotFound`                           | **Delete**       | `APIClientRealTests.testFetchBookNotFound` (L357)                                         |
| `testHandles500AsServerError`                        | **Delete**       | `APIClientRealTests.testServerErrorHandling` (L411)                                       |
| `testHandlesNetworkError`                            | **Delete**       | `APIClientRealTests.testNetworkErrorHandling` (L435)                                      |
| `testHandlesDecodingError`                           | **Port to Real** | No equivalent — MockURLProtocol returning malformed JSON, assert `APIError.decodingError` |
| `testLoginReturnsTokensAndUser`                      | **Delete**       | `APIClientRealTests.testLoginSuccess` (L130)                                              |
| `testLoginStoresAccessToken`                         | **Delete**       | `APIClientRealTests.testLoginSuccess` asserts token set                                   |

### `ios/BookVaultTests/Services/AuthManagerTests.swift` (11 stubs)

All 11 have Real equivalents in `AuthManagerRealTests.swift` (login success/failure, keychain storage, logout + server call, force-logout, refresh success/failure-clears-session, session restore). **Delete the whole file** — the non-stub content is only an initial-state check, which `AuthManagerRealTests` also covers.

**Net new work**: 2 ported tests (`omitsAuthorizationHeader`, `decodingError`). Everything else is deletion.

**Done when**: `grep -rl 'XCTAssertTrue(true' ios/BookVaultTests/ | wc -l` returns 0 (`grep -rc` prints per-file counts, never a clean zero); iOS suite green (`mcp BuildProject`/`RunAllTests` or CI `ios-tests.yml`).

---

## Phase 2 — `CoverCacheManagerTests` (the #75 change with no safety net)

**SUT**: `ios/BookVault/Services/CoverCacheManager.swift`. Testable init already exists:
`init(cacheDirectory:userIdProvider:authTokenProvider:apiBaseURLProvider:)` (L95–110). The security-relevant logic is L166–173: bearer token attached **only when** `url.host == apiURL.host && url.port == apiURL.port`.

**Constraint**: `URLSession.shared` is hardcoded (L175). Two options:

- (a) Register a `URLProtocol` globally via `URLProtocol.registerClass` for request capture (works with `.shared`), or
- (b) Preferred: add an injectable `URLSession` parameter defaulting to `.shared` — matches the dual-init pattern used elsewhere; #78 did exactly this for `DownloadManager`.

**Test cases** (new file `ios/BookVaultTests/Services/Real/CoverCacheManagerRealTests.swift`, temp cache directory per test):

1. **Token attached to API-host URL** — apiBaseURL `http://localhost:3000`, download URL same host/port → request has `Authorization: Bearer <token>`.
2. **Token NOT attached to presigned S3 URL** — download URL `https://book-vault-media.s3.amazonaws.com/...` → no Authorization header. _This is the security assertion: never leak the bearer token to S3._
3. **Same host, different port → no token** (port check is part of the guard).
4. **Nil token provider → no header** even for API host.
5. **Already cached → no network request issued** — pre-populate the cache, call `cacheCover` again, assert zero requests (pins the `hasCover` guard at the top of `cacheCover`).
6. Cache mechanics: `cacheCover` writes file, `hasCover`/`localCoverURL` find it, `deleteCover`/`clearCache` remove it, `getCacheStats` counts correctly — per-user directory isolation via `userIdProvider`.

---

## Phase 3 — `SystemKeychain` tests

**SUT**: `ios/BookVault/Services/SystemKeychain.swift` (conforms to `KeychainStoring`). Simulator fully supports `kSecClassGenericPassword` — test the **real** implementation, no mock (the mock is for consumers, not the SUT).

New file `ios/BookVaultTests/Services/Real/SystemKeychainTests.swift`, using unique per-test key prefixes + `tearDown` deletion:

1. `save` then `load` round-trips the value.
2. `save` over an existing key **overwrites** (this exercises the delete-then-add or update path — the classic keychain bug).
3. `load` of a missing key returns `nil`.
4. `delete` removes; subsequent `load` is `nil`; `delete` of a missing key doesn't throw.
5. Unicode/long values round-trip (encoding path, `KeychainError.encodingFailed` guard).

---

## Phase 4 — `/api/audio/[...path]` route tests

**SUT**: `app/api/audio/[...path]/route.ts`. New file `__tests__/api/audio/route.test.ts` → lands in the **unit-node** Jest project (`__tests__/api/**` testMatch). Model directly on `__tests__/api/images/route.test.ts` from #75 — same auth pattern, same mocking style.

**Mocks**: `getServerSession` (next-auth), `getAuthUserFromRequest` (`@/lib/auth`), `isS3Enabled` / `getS3ObjectMetadata` / `streamS3ObjectWithRange` (`@/lib/s3`), `fs` (`statSync`, `createReadStream`), `validateMediaPath` (`@/lib/media`).

**Test matrix**:

| Case                  | Setup                                 | Expect                                                                     |
| --------------------- | ------------------------------------- | -------------------------------------------------------------------------- |
| No session, no token  | both auth mocks null                  | 401                                                                        |
| Session cookie auth   | `getServerSession` → user             | 200/206                                                                    |
| Bearer token auth     | `getAuthUserFromRequest` → user       | 200/206                                                                    |
| S3: full request      | `isS3Enabled`=true, no Range          | 200, full stream                                                           |
| S3: valid range       | `Range: bytes=0-1023`                 | 206, `Content-Range: bytes 0-1023/<size>`                                  |
| S3: range beyond size | start ≥ size                          | 416                                                                        |
| S3: missing object    | metadata throws `NoSuchKey`           | 404                                                                        |
| Local: path traversal | `validateMediaPath` → false           | 403 (verified: route returns `{ error: 'Invalid file path' }`, status 403) |
| Local: missing file   | `statSync` throws                     | 404                                                                        |
| Local: valid range    | ReadStream called with `{start, end}` | 206                                                                        |
| Local: invalid range  |                                       | 416                                                                        |

Also add the happy-path GET to `openapi-contract.test.ts` — `/api/audio/{path}` is already in the spec (verified, openapi.yaml line ~2483), so no spec change is needed.

---

## Phase 5 — `AuthenticatedAVAssetResourceLoaderDelegate` tests

**SUT**: `ios/BookVault/Services/AuthenticatedAVAssetResourceLoaderDelegate.swift`. Injectable: `tokenProvider`, `tokenRefreshHandler` (init, L19–22). **Not** injectable: internal `URLSession` (L35–38) — add a `URLSessionConfiguration` (or session) init parameter defaulting to current behavior, so MockURLProtocol can intercept.

**⚠️ The session seam alone is NOT sufficient.** `AVAssetResourceLoadingRequest` has **no public initializer** — tests cannot construct one, so cases 2–6 below cannot drive `resourceLoader(_:shouldWaitForLoadingOfRequestedResource:)` directly. Required refactor (do this first):

1. Define a small protocol wrapping the parts of the loading request the delegate actually uses:
   ```swift
   protocol ResourceLoadingRequesting: AnyObject {
       var requestURL: URL? { get }
       var requestedByteRange: (offset: Int64, length: Int)? { get }  // from dataRequest
       func provide(_ data: Data)
       func finishLoading()
       func finishLoading(with error: Error?)
       var isCancelled: Bool { get }
   }
   ```
2. Extract the core logic (scheme conversion, authenticated `URLRequest` construction with Range header, the 401→refresh→retry state machine with its single-flight lock) into an internal `AuthenticatedResourceLoader` type operating on `ResourceLoadingRequesting`.
3. The AVFoundation delegate becomes a thin shim: a private extension conforms `AVAssetResourceLoadingRequest` to the protocol; the delegate forwards into the core type. The shim stays untested (it's declarative glue); all behavior below is tested against a mock conformance.

**Test cases** (`ios/BookVaultTests/Services/Real/AuthenticatedResourceLoaderTests.swift`, driving the core type with a `MockResourceLoadingRequest`):

1. Scheme conversion: `bookvault://` → `http://`, `bookvaults://` → `https://` (L76–89) — pure logic, testable even before the refactor.
2. Outgoing request carries `Authorization: Bearer <token>` from `tokenProvider`.
3. Range header propagation for seek requests (L102–110).
4. **401 → refresh → retry**: first response 401, `tokenRefreshHandler` returns true, request retried with new token (L158–166, 199–256).
5. 401 → refresh fails → NSError domain `AuthenticatedAVAssetResourceLoaderDelegate` code 401 (L250).
6. Concurrent 401s trigger **one** refresh (NSLock, L29/206–211) — two simultaneous mock loading requests, assert `tokenRefreshHandler` called once.

Manual verification after the refactor: stream one book on a device/simulator (the shim is the one part tests don't cover).

---

## Phase 6 — Playwright web smoke

**Current state**: not installed (`@playwright/test` orphaned in lockfile only), no config, no e2e dir.

1. `npm i -D @playwright/test && npx playwright install chromium` (chromium only — single-user app, no cross-browser need).
2. `playwright.config.ts` at repo root:
   - `testDir: 'e2e'` — outside all Jest `testMatch` patterns, so no collision with the three-project split.
   - `webServer: { command: 'npm run dev', port: 3000, reuseExistingServer: true }`.
   - **Prerequisite: Docker Postgres** — the dev server needs the DB. `globalSetup` should probe port 5433 first and fail with a clear "run `docker-compose up -d`" message (same pattern `scripts/validate.sh` uses for its integration/contract steps).
   - `globalSetup` then runs `scripts/seed-test-user.ts` (seeds `testuser`/`password123`, env-overridable via `TEST_USER_USERNAME`/`TEST_USER_PASSWORD`) — same seeding CI's `api.yml` already uses for contract tests.
3. **One smoke spec** (`e2e/smoke.spec.ts`): login → search for a seeded book → open detail → start playback (assert audio element/player state) → add to library → assert it appears in `/library`. Storage-state reuse so login happens once.
4. `package.json`: `"test:e2e": "playwright test"`.
5. **CI**: new job patterned on `api.yml`'s contract-test job (Postgres service → migrate → seed → dev server → run). Keep it a separate workflow (`e2e.yml`) so flake never blocks unit CI; retries: 1.
6. **Timing**: land before the S3 restore feature so archive/restore UI states get specs as they're built, not backfilled.

---

## Deferred (explicitly not now)

| Item                                                                                            | Why deferred                                                                                                                         | Trigger to revisit                                                                             |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| **XCUITest** (P2)                                                                               | Highest-maintenance, flakiest category; release loop is already human-verified (owner QAs every TestFlight build)                    | App gains users, or release path automates. Then: one minimal launch→login→play smoke, no more |
| **SearchManager tests**                                                                         | Hardcoded `APIClient.shared` + `URLSession.shared` — needs the dual-init DI seam first (same pattern #78 applied to DownloadManager) | Do the seam refactor as its own small PR, then test                                            |
| Browse/Search/entity web routes                                                                 | Breadth backfill, not security-adjacent                                                                                              | Ongoing, opportunistic (e.g., when a route changes)                                            |
| Interactive web components (`SearchBar`, `AddToLibraryButton`, `PlaybackClient`, `ChapterList`) | Playwright smoke covers the highest-value interactions end-to-end first                                                              | After Phase 6                                                                                  |
| Negative iOS fixtures, branch-coverage push                                                     | Quality improvement, not gap-closing                                                                                                 | Ongoing                                                                                        |

---

## Sequencing & sizing

| Phase                      | Size                                                                                                                                                  | Depends on             |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| 0 — Land #79 + ratchet     | ~1 hr                                                                                                                                                 | —                      |
| 1 — Stub cleanup           | ~2 hrs (mostly deletion; 2 ported tests)                                                                                                              | 0 (iOS seams from #78) |
| 2 — CoverCacheManager      | ~half day (incl. URLSession seam)                                                                                                                     | 0                      |
| 3 — SystemKeychain         | ~2 hrs                                                                                                                                                | —                      |
| 4 — /api/audio route       | ~half day                                                                                                                                             | 0 (Jest projects)      |
| 5 — ResourceLoaderDelegate | ~1–1.5 days (incl. protocol-wrapper refactor — `AVAssetResourceLoadingRequest` can't be instantiated in tests — plus session seam + concurrency test) | 0                      |
| 6 — Playwright smoke       | ~1 day (incl. CI wiring)                                                                                                                              | 0                      |

Phases 1–5 are independent of each other and can be individual small PRs. Phase 6 is standalone. Suggested PR grouping: (0), (1+2+3 as "iOS test hardening"), (4), (5), (6).

## Verification per phase

- iOS phases: `cd ios && xcodegen generate` if targets change; run suite via Xcode (`RunAllTests`) or push and let `ios-tests.yml` (macos-14 simulator) verify.
- Web phases: `npm run validate` (includes threshold gate post-Phase 0); `npm run test:contract` if the OpenAPI spec changed.
- Playwright: `npm run test:e2e` locally against dev server; then confirm `e2e.yml` green in CI.
