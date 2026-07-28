# iOS: Logout + Audio Stops Every ~2 Hours — Requirements

> **Created**: July 25, 2026
> **Updated**: July 28, 2026 — CI caught an incomplete first fix (Defect 5); generation guard added
> **Status**: **Fix implemented and green** (691 iOS tests, 0 failures; CI green). Awaiting Tier 2 on-device verification.
> **Priority**: TBD
> **Platform**: iOS only (confirmed not observed on web)

---

## Reported Symptom

On iOS, roughly every ~2 hours: audio playback stops and the user is logged out (has to reopen the app and log back in). Not observed on web.

## User's Working Theory

The access token expires and forces a logout, which tears down playback. Given this is a personal audiobook app (not a banking/financial app), the user's proposed direction is: **once a device has logged in once, and the token/credential still matches what the backend expects, the user should not need to re-authenticate** — i.e., move toward a silent-refresh model where the user practically never sees a login screen on a device they've already authenticated, rather than a short hard expiry.

That said, a prior investigation into the codebase (details below) suggests the real mechanism may be more specific than plain expiry — **re-investigation on a real device is needed to confirm the actual failure mode before committing to a fix.**

## What the Codebase Investigation Found (July 2026) — Context, Not Yet Confirmed as Root Cause

This is background to inform the re-investigation, not a finalized diagnosis:

- **Token setup**: iOS uses a custom JWT system (`lib/jwt.ts`) separate from the web NextAuth session. Access token expiry defaults to `3600s` (1 hour, via `JWT_ACCESS_TOKEN_EXPIRY`). Refresh token is a 30-day UUID (`RefreshToken` table), rotated on each use (`app/api/auth/mobile/refresh/route.ts`).
- **A refresh mechanism already exists** — this isn't a from-scratch build. `APIClient.swift` catches 401s, attempts a single-flight refresh (`attemptTokenRefresh()`), retries once, and only force-logs-out after a _second_ 401 post-refresh.
- **This exact bug class has been fixed before, more than once**:
  - PR #56 (`docs/archive/completed-plans/ios-token-refresh-race-condition-fix.md`): originally, concurrent 401'd requests raced — only the first attempted refresh, others force-logged-out immediately. Fixed with a `TokenRefreshCoordinator` actor.
  - PR #66: the AVPlayer audio streaming path (`AuthenticatedResourceLoader.swift`) had its _own_ separate 401 handling with no refresh path at all, independently killing playback after ~1hr. Fixed by giving it its own single-flight refresh-and-retry logic.
  - A cluster of related fixes (PRs #52–#59) around token decoding/case-normalization.
- **A specific, still-open issue is documented** in `docs/analysis/architecture-review-2026-07.md` (item D-6, confirmed still open as of the July 19 refresh): a **check-then-act race condition** remains in the refresh coordination between `APIClient` and `AudioPlayerManager` — i.e., the single-flight coordinator fix may not fully cover every path.
- Given two independent fixes already targeted "~1 hour" symptoms and a known gap is still open, **the most likely mechanism is a residual race in the refresh path, not a hard/intentional expiry with no refresh at all.** But this hasn't been reproduced fresh — treat as a lead, not a conclusion.

## Root Cause — Tier 1 Results (July 27, 2026)

Tier 1 tests are written and **have been run against current code**. They corrected the initial code-inspection diagnosis in two important ways. Findings, in evidence order:

| #   | Defect                                         | Test result                                    | Status                  |
| --- | ---------------------------------------------- | ---------------------------------------------- | ----------------------- |
| 1   | Check-then-act race in `attemptTokenRefresh()` | **passed** (8 concurrent 401s → 1 refresh)     | Latent, not the cause   |
| 2   | Lost-wakeup hang in waiter registration        | **passed** (all 8 returned)                    | Latent, not the cause   |
| 3   | Resource loader retries with stale token       | **FAILED** — 2nd 401, playback torn down       | **Confirmed trigger**   |
| 4   | Force-logout not deduplicated                  | **FAILED** — 8 concurrent 401s → **8 logouts** | **Confirmed amplifier** |

**Revised conclusion: the trigger is Defect 3 (the AVPlayer path's fixed-sleep refresh), and Defect 4 amplifies any single refresh failure into a total session teardown.** Defects 1 and 2 are real hazards in the source but did **not** reproduce under concurrency — Swift's actor serialization narrows the window far more than static reading suggested. They are worth closing opportunistically; they are not what is logging the user out.

The initial inspection called Defects 1/2 the likely mechanism. The tests disproved that. Recorded here so the correction isn't lost.

### Defect 1 — check-then-act race in `APIClient.attemptTokenRefresh()`

[`APIClient.swift:458-472`](../../ios/BookVault/Services/APIClient.swift#L458-L472):

```swift
if await refreshCoordinator.isRefreshInProgress() {   // ← check
    return await withCheckedContinuation { continuation in
        Task { await refreshCoordinator.addWaiter(continuation) }   // ← act (separate hop)
    }
}
await refreshCoordinator.markRefreshStarted()
```

The check and the act are two separate `await`s on the actor, with a suspension point between them. The actor makes each _individual_ call safe but does nothing to make the pair atomic. Two requests that 401 simultaneously can both observe `isRefreshInProgress() == false` and both proceed to refresh.

**Why that logs the user out:** refresh tokens are **rotated on every use** (`app/api/auth/mobile/refresh/route.ts`). The second refresh presents a token the first one already consumed, the backend rejects it, and the failure path force-logs-out.

### Defect 2 — lost-wakeup hang in the waiter path (more severe)

`addWaiter` is called from inside a **detached `Task`**, so registration is not ordered against the refresh completing. If the in-flight refresh reaches `completeRefresh()` (which drains `waiters` and clears the array) before that `Task` body runs, the continuation is appended to an already-drained array and **nobody ever resumes it**. That request hangs forever — no timeout, no error, no logout. A hung progress-sync or stream request is a plausible match for "audio just stops."

Note also that `beginRefresh()` ([`APIClient.swift:20-27`](../../ios/BookVault/Services/APIClient.swift#L20-L27)) returns `nil` on **both** branches, making it impossible to use correctly. It is dead code, and its unusability is likely why the caller hand-rolled the broken check-then-act above.

### Defect 3 — the AVPlayer path is a second, separately-broken implementation

[`AuthenticatedResourceLoader.swift:254-301`](../../ios/BookVault/Services/AuthenticatedResourceLoader.swift#L254-L301) does **not** share the coordinator. It has its own `NSLock`-based single-flight, and its "wait for the other refresh" branch is a blind sleep:

```swift
try? await Task.sleep(nanoseconds: concurrentRefreshWait)  // default 500ms
refreshSucceeded = tokenProvider() != nil
```

It waits a fixed 500 ms and then merely checks that _a_ token exists — not that a _new_ one arrived. If the refresh takes longer than 500 ms (very plausible on cellular), this reads the **stale** token, retries with it, takes a second 401, and tears down playback. It is also a genuine check-then-act against the `APIClient` coordinator, since the two mechanisms are unaware of each other.

**Confirmed by test.** The token sequence recorded across the two concurrent stream requests was:

```
["stale-token", "stale-token", "stale-token", "fresh-token"]
```

The second request woke from its 50 ms wait while the 300 ms refresh was still in flight, retried with the stale token, and took a second 401 → `AuthenticatedAVAssetResourceLoaderDelegate Code=401` → playback torn down. Reproduced in 0.75 s.

_Caveat:_ the test arranges refresh latency (300 ms) to exceed the loader's wait (50 ms). That ratio is realistic on cellular but is set up here — the test proves the **mechanism**, not its real-world frequency. Tier 2 establishes how often it actually fires.

### Defect 4 — force-logout is not deduplicated (found by test, not by inspection)

Not in the original analysis; surfaced by the Tier 1 guardrail test. `forceLogoutHandler()` is called **per failing request** at [`APIClient.swift:319`](../../ios/BookVault/Services/APIClient.swift#L319) and [`:356`](../../ios/BookVault/Services/APIClient.swift#L356), with no guard against repeats.

**8 concurrent 401s produced 8 force-logouts.** Every in-flight request independently tears down the session. This turns a single transient refresh failure into a full, immediate teardown — and likely explains why the logout presents as so abrupt and total rather than as one recoverable request failure.

**Net:** two independent refresh implementations, with the streaming one broken (Defect 3) and the logout path unguarded against pile-on (Defect 4) — both on the exact path exercised during long playback (streaming + progress sync overlapping). This is consistent with the symptom recurring despite the PR #56 and PR #66 fixes: each fixed one path and left the other.

### Test-coverage gap that let this survive

`APIClientRealTests.swift` has 27 tests and **none of them exercise a 401 → refresh → retry**. `testRefreshTokenSuccess` only tests the refresh _endpoint_ in isolation, never the concurrent-401 coordination. The race was unprotected by construction.

## Test Plan

Three tiers, cheapest first. Tier 1 proves the mechanism deterministically; Tiers 2–3 confirm the fix under real conditions.

### Tier 1 — Deterministic unit tests ✅ DONE

Written to [`ios/BookVaultTests/Services/Real/TokenRefreshConcurrencyTests.swift`](../../ios/BookVaultTests/Services/Real/TokenRefreshConcurrencyTests.swift). Reused the existing `MockURLProtocol` (in `APIClientRealTests.swift`) plus the `tokenRefreshHandler` / `forceLogoutHandler` / `concurrentRefreshWaitNanoseconds` injection seams — no new harness needed.

Whole suite runs in **under 1 second**, versus a 2-hour soak.

1. **Single-flight under concurrency** — 8 concurrent 401s → assert one refresh. → **passes today** (Defect 1 latent, not live).
2. **Rotation safety** — assert no refresh token is presented twice. → **passes today**.
3. **No lost wakeup** — fast refresh + concurrent waiters, timeout as the assertion. → **passes today** (Defect 2 latent, not live).
4. **Resource loader uses the refreshed token** — refresh slower than the loader's wait. → **FAILS**, confirming Defect 3.
5. **Failed refresh logs out exactly once** — 8 concurrent 401s with a failing refresh. → **FAILS (8 logouts)**, revealing Defect 4.

Run them with:

```bash
xcodebuild -project ios/BookVault.xcodeproj -scheme BookVault -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BookVaultTests/TokenRefreshConcurrencyTests \
  -only-testing:BookVaultTests/ResourceLoaderRefreshConcurrencyTests test
```

Note: new test files require `cd ios && xcodegen generate` before they are picked up — otherwise the suite reports "passed" having run **zero** tests.

Tests 1–3 stay in the suite as regression guards even though they pass: they pin the invariants so the latent hazards cannot become live later.

### Tier 2 — Compressed on-device repro (~5 minutes, not 2 hours)

A refresh cycle every 60 s compresses ~2 hours of exposure into a few minutes, and — unlike Tier 1 — exercises the real AVPlayer + progress-sync overlap where the concurrency window actually opens. Highest-value verification step.

**`JWT_ACCESS_TOKEN_EXPIRY` is server-side only** ([`lib/jwt.ts`](../../lib/jwt.ts) reads it when minting the token). iOS consumes whatever expiry it is handed, so **no app rebuild is needed** to change it and there is no iOS-side setting for it.

**Recommended setup — local server + physical device on the LAN.** Real device, real AVPlayer, zero production impact, instant rollback.

1. `JWT_ACCESS_TOKEN_EXPIRY="60"` in `.env.local`, then restart `npm run dev`.
2. Point the Debug build at the Mac's LAN IP instead of `localhost` — a device cannot reach `localhost`. Edit `API_BASE_URL` in [`ios/Config/Debug.xcconfig`](../../ios/Config/Debug.xcconfig) (note the `$()` escaping used to keep `//` from being read as a comment), then `cd ios && xcodegen generate` and rebuild.
3. No ATS change required: `NSAllowsArbitraryLoads` is already set in [`Info.plist`](../../ios/BookVault/Info.plist), so cleartext HTTP to a LAN IP is permitted.

Capture with `log stream` filtered to the app. The `DebugLogger.auth` lines already trace refresh start/completion/waiter counts, and after this fix also log `"Token already refreshed since this request began - skipping redundant refresh"` — seeing that line is positive confirmation the Defect 5 guard is firing on real traffic.

**What to look for:** exactly one refresh per expiry cycle, no `forceLogout`, and playback continuing across several cycles. More than one refresh per cycle means a surplus rotated-token consumption survived.

Vary across runs: foreground vs. backgrounded/locked, and a wifi↔cellular switch mid-playback (the latter is what makes refresh latency exceed the old fixed timer).

**Alternative — prod at 60 s.** More realistic but higher blast radius: `JWT_ACCESS_TOKEN_EXPIRY` is baked into the ECS **task definition** (`book-vault:9`), which is immutable, so changing it means registering a new revision and pointing the service at it — infra-only, no image rebuild, ~2–3 min to roll. Rollback is re-pointing at `:9`. Every live session gets 60 s tokens while set (web is unaffected; NextAuth is separate). Only meaningful **after** this PR is merged and deployed — against current prod code it just reproduces the bug faster.

### Tier 3 — Full soak, once, as final confirmation

2+ hours against production token lifetimes, logs captured, only after Tiers 1–2 pass. Confirms the fix end-to-end; not needed to find the bug.

### Still worth checking on device (unchanged from the original investigation)

- Confirm `AuthManager.forceLogout()` / `clearCachesOnLogout` is genuinely what fires, rather than playback dying for an unrelated reason that merely _looks_ like a logout.
- Confirm iOS-only by leaving a web session open in parallel.

## Fix Direction

Root cause is now identified, so the shape of the fix is clearer than when this was drafted:

Ordered by what the evidence supports:

- **Unify the two refresh implementations** (required — fixes the confirmed trigger): have `AuthenticatedResourceLoader` await the _same_ coordinator as `APIClient` instead of sleeping a fixed interval and then checking only that _a_ token exists. The wait must be on the refresh actually completing, not on a timer. This is the piece PRs #56 and #66 each fixed on only one side; leaving two mechanisms is precisely what let the symptom survive both. Fixes Defect 3.
- **Deduplicate force-logout** (required — fixes the confirmed amplifier): one refresh failure should produce exactly one logout, regardless of how many requests are in flight. Fixes Defect 4.
- **Make the refresh atomic and single-flight for real** (recommended, lower priority): collapse the check-then-act into one actor method, and stop registering waiters from a detached `Task`. Delete the unusable `beginRefresh()`. Addresses Defects 1 and 2 — latent today, but the tests exist to keep them that way.
- **Optionally extend token lifetime**: fewer refresh cycles means fewer chances to hit the bug, but it does not close it. Only alongside the fixes above, never instead of them.
- Broader "never re-prompt for login on a trusted device" framing (user's stated preference) is achievable via a robust silent-refresh model without necessarily making the access token itself long-lived or non-expiring — worth deciding deliberately rather than defaulting to "just extend expiry," since the refresh-token mechanism already exists and is the safer way to get the same user-facing outcome (no visible re-login) while keeping access tokens short-lived.

## Fix As Implemented (July 27, 2026)

All four defects closed. The central change is that **one coordinator now serves the whole app**, so the streaming and JSON-API paths can no longer refresh independently.

**New:** [`TokenRefreshCoordinator.swift`](../../ios/BookVault/Services/TokenRefreshCoordinator.swift)

- `TokenRefreshCoordinator.refresh(using:)` — claim-or-join in **one** actor-isolated step, with no suspension point between checking and claiming, and waiter registration synchronous with the actor rather than in a detached `Task`. Closes Defects 1 and 2 structurally. There is deliberately no public `isRefreshInProgress()`: exposing one is what invited the original check-then-act race.
- `TokenRefreshCoordinator.shared` — the app-wide instance. Production wires `APIClient.shared` and every per-playback resource loader to it.
- `OneShotGate` — an actor latch admitting one caller until reset; used for logout dedup.

**Changed:**

- [`APIClient.swift`](../../ios/BookVault/Services/APIClient.swift) — deleted the old private coordinator (including the unusable `beginRefresh()`); `attemptTokenRefresh()` now delegates to the shared one. All four 401 logout paths route through a new `forceLogoutOnce()`, and the gate re-arms on successful login so a later session can still log itself out.
- [`AuthenticatedResourceLoader.swift`](../../ios/BookVault/Services/AuthenticatedResourceLoader.swift) — **the core fix.** Replaced the `NSLock` + fixed-`Task.sleep` scheme with an await on the shared coordinator. The `concurrentRefreshWaitNanoseconds` parameter is gone: waiting is now on the refresh genuinely completing, so there is no timer to out-run. Also removes an `NSLock`-in-async-context warning that was slated to become a Swift 6 error.
- [`AuthenticatedAVAssetResourceLoaderDelegate.swift`](../../ios/BookVault/Services/AuthenticatedAVAssetResourceLoaderDelegate.swift) / [`AudioPlayerManager.swift`](../../ios/BookVault/Services/AudioPlayerManager.swift) — the coordinator is injected rather than created per-delegate. A delegate is built for each playback, so constructing one per instance would have silently restored the two-coordinator bug.

**Tests:** 7 in [`TokenRefreshConcurrencyTests.swift`](../../ios/BookVaultTests/Services/Real/TokenRefreshConcurrencyTests.swift), all green; full iOS suite 691 passing, SwiftLint clean on every touched file.

`testStreamingAndAPIPathsShareOneRefresh` is the one that matters most — it drives an API 401 and a streaming 401 concurrently and asserts a single refresh. **Verified to genuinely fail (2 refreshes) when the coordinator is un-shared**, so it will catch any future regression that reintroduces a second refresh mechanism. That is precisely the gap that survived both PR #56 and PR #66.

### Defect 5 — stale 401 triggers a redundant refresh (caught by CI, not local)

**The first version of this fix was incomplete.** CI failed `testConcurrentUnauthorizedRequestsTriggerExactlyOneRefresh` with **"got 2"** — two refreshes on 8 concurrent 401s — while the same test passed 5/5 locally at 0.07 s. CI took 0.911 s, ~13× slower, which opened a window a fast machine never hit.

The mechanism is not a race in the coordinator; it is a **stale 401**. Requests do not all 401 at the same instant. A request already in flight when a refresh completes is still answered `401` — the server decided that before the token was swapped. By the time that late 401 surfaces, the coordinator is idle, so there is nothing to join and the caller starts a **second, sequential** refresh. The token was already fresh, so in production that surplus refresh **consumes a rotated refresh token for nothing** — the exact failure this work set out to eliminate.

Fix: a **generation counter** in the coordinator, incremented on each successful refresh. Callers capture the generation _before_ issuing a request and pass it back if that request 401s; if the generation has advanced, the 401 is stale and the caller is told to retry instead of refreshing again.

- `TokenRefreshCoordinator.currentGeneration()` plus a `observedGeneration:` parameter on `refresh(...)`.
- `APIClient.execute` / `executeRaw` capture the generation before `session.data(for:)`.
- `AuthenticatedResourceLoader.startLoading` captures it before dispatching, threading it through `executeRequest` → `handleUnauthorized`. (`startLoading` must stay synchronous for AVFoundation, so the capture happens in a `Task`.)

Guarded by `testLateArriving401DoesNotTriggerSecondRefresh`, which sequences on **explicit signals rather than timing**, so it behaves identically on a fast laptop and a slow runner (0.008 s, no sleeps).

**Process note worth keeping.** My first attempt at that test passed even with the fix disabled — it was vacuous, because a blocking `XCTWaiter` in the URLProtocol handler meant the intended interleaving never occurred. It was rewritten and then **verified to fail with "got 2"** when the generation guard is disabled, matching CI exactly. Any new concurrency test here should be confirmed to fail against the unfixed code before being trusted; a passing test is not evidence until then.

### Remaining risk

Tier 1 proves the mechanism under controlled timing. It cannot prove real-world frequency or that no _other_ path also tears down playback. Tier 2 is still required before calling this fixed.

## Explicitly Out of Scope (for now)

- Changes to web session handling (NextAuth) — not implicated, bug is iOS-only.
- Any change to the _security model_ itself (e.g., removing auth entirely) — not what was asked; the ask is about not re-prompting on an already-trusted device, not removing authentication.

## Acceptance Criteria

- [x] Tier 1 tests written and run (July 27, 2026) — 5 tests, sub-second suite.
- [x] Root cause confirmed **by failing test**, not inference: Defect 3 (stale-token retry on the AVPlayer path) is the trigger; Defect 4 (un-deduplicated force-logout) is the amplifier. Defects 1–2 disproved as the live mechanism.
- [x] Defect 3 fixed — the streaming path waits on refresh _completion_, not a fixed timer.
- [x] Defect 4 fixed — one refresh failure produces exactly one logout.
- [x] Defects 1–2 closed structurally — claim-or-join is atomic; waiter registration is synchronous.
- [x] All 6 Tier 1 tests passing and kept in the standing suite; full iOS suite 690 green, SwiftLint clean.
- [x] Both refresh paths coordinate through one shared `TokenRefreshCoordinator` — no second implementation left behind, and a test fails if that sharing is ever undone.
- [ ] Verified on device via the Tier 2 compressed repro (60 s token expiry), then the Tier 3 soak.
- [ ] User is not prompted to re-login during normal use of an already-authenticated device, including through long playback sessions spanning multiple access-token lifetimes.
- [ ] A genuinely invalid/revoked credential (e.g., explicit logout, backend-side revocation) still correctly logs the user out — this shouldn't become "tokens never expire, full stop."
- [ ] Verified specifically during audio playback (foreground + backgrounded/locked-screen), since that's the reported trigger context, not just general app usage.
