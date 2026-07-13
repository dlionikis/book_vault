# Testing Hardening — Implementation Plan

> **Date**: July 13, 2026
> **Source**: [testing-coverage-review.md](testing-coverage-review.md) (findings + annotated re-prioritization)
> **Ordering rationale**: single-user app, manual release process, owner-QA on every TestFlight build. Cheap security-adjacent unit work first, Playwright web smoke second (before the S3 restore feature adds UI states), XCUITest demoted to P2.

---

## Execution split (VS Code vs. Xcode)

The test code for every phase is **authored in VS Code** (that's where the plan, codebase context, and web tooling live). Verification differs by language:

- **Phases 4, 6 (web/Node)** — authored AND verified in VS Code (`npm test`, `npm run test:e2e`). Fully autonomous; Xcode not involved.
- **Phases 1, 2, 3, 5 (Swift)** — authored in VS Code, but Swift can only be compiled/run via Xcode or the `xcodebuild` CLI. Each of these phases ends with a **📋 Xcode handoff prompt** — a self-contained instruction block to paste into Claude running inside Xcode, so it can build, run the tests, and fix failures with the tight inline loop (per-test run buttons, assertion overlays, debugger). The handoff prompt assumes no knowledge of this conversation; everything it needs is in the block. (Alternatively, the VS Code agent can self-verify via `xcodebuild test` — slower log-parsing loop, but no context handoff.)

**Note for Phase 5**: authenticated AV playback should get a real-device smoke test after the unit tests pass — simulator behavior isn't authoritative for AVFoundation/media paths (cf. the project's icon-switching lesson).

---

## Phase 0 — Land #79, re-measure, ratchet (BLOCKING — do first) ✅ DONE (July 13, 2026)

> **Outcome**: #79 merged (`f30646f`). Measured floor on the post-#79 unit tree: 37.21% stmts / 36.52% branch / 38.0% funcs / 37.55% lines. `coverageThreshold` ratcheted 34/32/35/34 → **37/36/38/37**; `npm run validate` green.

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

### 📋 Xcode handoff prompt (Phase 1)

> Paste into Claude running in Xcode after the VS Code agent has written/deleted the test files on the current branch. Goal: verify the placeholder-cleanup compiles and the suite is green.
>
> ```
> The iOS test suite in ios/BookVaultTests/ was just edited to remove ~24 placeholder `XCTAssertTrue(true)` stub tests. Two files changed: APIClientTests.swift (stubs deleted, two real tests added — testUnauthenticatedRequestOmitsAuthorizationHeader and testHandlesDecodingError) and AuthManagerTests.swift (deleted entirely — its content was all stubs or duplicated by AuthManagerRealTests.swift).
>
> Do this:
> 1. If any target membership or file references changed, run `cd ios && xcodegen generate` first.
> 2. Build the BookVault scheme and run the full BookVaultTests suite on an iPhone simulator.
> 3. Confirm: (a) it compiles, (b) all tests pass, (c) `grep -rl 'XCTAssertTrue(true' ios/BookVaultTests/ | wc -l` returns 0.
> 4. If the two new tests (omits-auth-header, decoding-error) fail, fix them: the first uses MockURLProtocol to assert no Authorization header is present when no token is set; the second returns malformed JSON via MockURLProtocol and asserts APIError.decodingError. Match the patterns already in APIClientRealTests.swift.
> 5. Report pass/fail counts and any fixes made. Do not add new test coverage beyond these two ported tests — this phase is cleanup only.
> ```

---

## Phase 2 — `CoverCacheManagerTests` (the #75 change with no safety net) ✅ DONE (July 13, 2026)

> **Outcome**: Added an injectable `URLSession` (option b) and `CoverCacheManagerRealTests.swift` (6 tests) reusing `MockURLProtocol`. All 6 pass; full suite 600 tests / 0 failures. The security test (`testTokenNotAttachedForS3URL`) was mutation-verified: deliberately removing the host guard made it (and the different-port test) fail, confirming they exercise the real logic rather than passing trivially.

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

### 📋 Xcode handoff prompt (Phase 2)

> Paste into Claude running in Xcode after the VS Code agent has (a) added the injectable `URLSession` seam to `CoverCacheManager.swift` and (b) written `CoverCacheManagerRealTests.swift`. Goal: verify the seam change + new tests, with the security assertion front and center.
>
> ```
> Two files changed on the current branch: ios/BookVault/Services/CoverCacheManager.swift gained an injectable URLSession init parameter (defaulting to .shared, following the same dual-init DI pattern DownloadManager uses), and a new test file ios/BookVaultTests/Services/Real/CoverCacheManagerRealTests.swift was added.
>
> Do this:
> 1. Run `cd ios && xcodegen generate` (a new test file was added).
> 2. Build the BookVault scheme and run CoverCacheManagerRealTests on an iPhone simulator.
> 3. The SECURITY-CRITICAL test is "token NOT attached to presigned S3 URL": when the download URL host is an S3 host (not the API base URL host), the request must carry NO Authorization header. If this test does not exist or does not actually assert header absence, that is a blocker — flag it, don't paper over it. The bearer token must never leak to S3.
> 4. Also confirm these pass: token IS attached for same-host+same-port API URLs; no token for same-host-different-port; no token when the token provider returns nil; already-cached covers issue zero network requests; and the cache mechanics (write/find/delete/clear/stats, per-user dir isolation).
> 5. If the URLSession seam didn't land correctly (e.g. tests can't intercept requests via MockURLProtocol because .shared is still hardcoded on the request path), fix the production code so the injected session is actually used for the download.
> 6. Report pass/fail counts and any fixes. Confirm the full BookVaultTests suite still builds and passes (the seam change must not break existing DownloadManager/other tests).
> ```

---

## Phase 3 — `SystemKeychain` tests ✅ DONE (July 13, 2026)

> **Outcome**: Added `SystemKeychainTests.swift` (7 tests) against the real Security framework on the simulator — no production code change. All pass; full suite green. Per-test unique key prefix + `tearDown` sweep prevents cross-run pollution. Mutation-verified the overwrite test: removing the delete-before-add in `save` makes it fail with `errSecDuplicateItem` (-25299), the classic keychain bug it guards.

**SUT**: `ios/BookVault/Services/SystemKeychain.swift` (conforms to `KeychainStoring`). Simulator fully supports `kSecClassGenericPassword` — test the **real** implementation, no mock (the mock is for consumers, not the SUT).

New file `ios/BookVaultTests/Services/Real/SystemKeychainTests.swift`, using unique per-test key prefixes + `tearDown` deletion:

1. `save` then `load` round-trips the value.
2. `save` over an existing key **overwrites** (this exercises the delete-then-add or update path — the classic keychain bug).
3. `load` of a missing key returns `nil`.
4. `delete` removes; subsequent `load` is `nil`; `delete` of a missing key doesn't throw.
5. Unicode/long values round-trip (encoding path, `KeychainError.encodingFailed` guard).

### 📋 Xcode handoff prompt (Phase 3)

> Paste into Claude running in Xcode after the VS Code agent has written `SystemKeychainTests.swift`. Goal: verify keychain round-trips against the real Security framework on the simulator.
>
> ```
> A new test file ios/BookVaultTests/Services/Real/SystemKeychainTests.swift was added on the current branch. It tests the REAL SystemKeychain implementation (ios/BookVault/Services/SystemKeychain.swift) against the simulator's keychain — no mock, because the mock exists for consumers, not for testing the keychain itself.
>
> Do this:
> 1. Run `cd ios && xcodegen generate` (new test file).
> 2. Build and run SystemKeychainTests on an iPhone simulator.
> 3. Confirm all pass: save→load round-trip; save over an existing key OVERWRITES (the delete-then-add-or-update path — the classic keychain bug to guard against); load of a missing key returns nil; delete removes and delete-of-missing doesn't throw; unicode/long values round-trip.
> 4. Watch for test pollution: each test must use a unique key prefix and clean up in tearDown, or a leftover keychain item fails a later run. If you see nondeterministic failures across runs, that's the cause — fix the isolation, don't just re-run.
> 5. If the simulator returns errSecItemNotFound / -25300 unexpectedly on save-then-load, it usually means the keychain access group or bundle entitlement isn't set for the test host — report the exact OSStatus rather than guessing.
> 6. Report pass/fail counts and any fixes.
> ```

---

## Phase 4 — `/api/audio/[...path]` route tests ✅ DONE (July 13, 2026)

> **Outcome**: Added `__tests__/api/audio/route.test.ts` (11 tests) covering the auth, S3, and local-filesystem branches incl. 206/416/404. Mocked the `requireUser` seam via a stub factory (the real module pulls in Prisma, which can't init in-test). The contract-suite happy-path GET already exists (openapi-contract.test.ts L2023), so no spec/contract change. Audio route coverage 0 → ~86% stmts / 71% branch; full unit suite 357 tests, 0 failures; overall coverage 38.87/38.42/38.4/39.29 (above the 37/36/38/37 gate).

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

### 📋 Xcode handoff prompt (Phase 5)

> Paste into Claude running in Xcode after the VS Code agent has done the protocol-wrapper refactor + written the tests. This is the most involved iOS phase: a production-code refactor, a concurrency test, and a required real-device playback check.
>
> ```
> The current branch refactored ios/BookVault/Services/AuthenticatedAVAssetResourceLoaderDelegate.swift for testability and added ios/BookVaultTests/Services/Real/AuthenticatedResourceLoaderTests.swift. The refactor: extracted the delegate's core logic (bookvault:// → http:// scheme conversion, authenticated URLRequest building with Range header, and the 401→refresh→retry state machine with its single-flight NSLock) into an internal type that operates on a `ResourceLoadingRequesting` protocol — because `AVAssetResourceLoadingRequest` has no public initializer and cannot be constructed in a test. The AVFoundation delegate is now a thin shim conforming the real request to that protocol; the tests drive the core type with a MockResourceLoadingRequest. An injectable URLSession (defaulting to .shared) was also added so MockURLProtocol can intercept.
>
> Do this:
> 1. Run `cd ios && xcodegen generate` (new test file, possibly new source file for the extracted type).
> 2. Build the BookVault scheme and run AuthenticatedResourceLoaderTests on an iPhone simulator.
> 3. Confirm all pass: scheme conversion (bookvault→http, bookvaults→https); outgoing request carries Authorization: Bearer <token>; Range header propagates for seek requests; 401→refresh-succeeds→retry-with-new-token; 401→refresh-fails→NSError domain AuthenticatedAVAssetResourceLoaderDelegate code 401.
> 4. The HARDEST and most important test is concurrency: two simultaneous loading requests both hit 401 → tokenRefreshHandler must be called EXACTLY ONCE (single-flight via the NSLock). If this test is flaky or the count is >1, the lock is being released too early or the refresh isn't actually shared — this is a real bug to fix in the production code, not a test to loosen. Run it several times to check for flake.
> 5. Verify the full BookVaultTests suite still builds and passes — the refactor touched a production file used by real playback, so nothing else should regress.
> 6. ⚠️ REQUIRED after unit tests pass: do a real playback smoke. Build to a physical device (or, if unavailable, the simulator as a fallback) and actually play an audiobook that streams through this resource loader — confirm audio starts and seeking works. The thin AVFoundation shim is the one part unit tests do NOT cover, and simulator behavior for AVFoundation/media is not authoritative (this project has been burned before by simulator-only verification of media/icon features). Do not mark this phase done on unit tests alone.
> 7. Report: unit pass/fail counts, concurrency-test stability across runs, any production-code fixes, and the result of the real playback smoke (device vs. simulator).
> ```

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
