# Plan C — Swift 6 Readiness for the Generated Networking Layer

> **Status**: ✅ **Implemented (July 30, 2026).** Phases 1–2 shipped: the generated request layer is
> no longer generated (112 → 102 files, 11 support files → 3). **Phase 3 (A4) did not land** — the
> trim removed every _generated_ blocker, but flipping the language mode surfaced an app-code one
> that this plan did not predict. See §9.
> **Scope**: iOS generated OpenAPI code + generation script. No app logic, no API, no DB, no web.
> **Created**: July 29, 2026
> **Blocks**: step **A4** (`SWIFT_VERSION: 6.0`) in
> [ios-modernization-sequencing.md](ios-modernization-sequencing.md). Nothing else.
> **Parent plan**: [ios-modernization-sequencing.md](ios-modernization-sequencing.md) §4 / §7

---

## 1. Headline: the blocking code is dead code

The investigation this plan was created to run has been **done**, and it inverts the plan.

The 6 Swift 6 errors blocking A4 are all in generated request-execution machinery that **no app or
test code references**. The app's networking is the hand-written `APIClient` (838 lines), which
talks to `URLSession` directly ([APIClient.swift:113-124](../../ios/BookVault/Services/APIClient.swift#L113-L124))
and never touches the generated builders.

**Evidence:**

| Check                                                                                          | Result                                                     |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| App/test references to `RequestBuilder`, `URLSessionRequestBuilderFactory`, `OpenAPIClientAPI` | **0** — only other generated files                         |
| Generated API entry-point classes (`DefaultAPI`, `BooksAPI`, …)                                | **none exist** — only support scaffolding was ever emitted |
| App/test references to generated `Configuration` type                                          | **0** (grep hits were the English word "configuration")    |
| App/test references to `RequestTask`, `ErrorResponse`, `RequestBuilder`                        | **0 files each**                                           |

**Empirical confirmation.** Deleting all seven request-layer files and rebuilding produced **exactly
two errors, both inside another generated file** — `Models.swift:115,117` referencing
`URLSessionDataTaskProtocol` from the generated `RequestTask`, which is itself unused. **No app code
broke.**

So this is not "restructure the network path under strict concurrency." It is **stop generating code
we never use.**

---

## 2. Decision

**C3 (remove the unused request layer) — confirmed viable and adopted.**

C1 (fork and patch `URLSessionImplementations.mustache`) and C2 (separate framework target) from the
parent plan are **both withdrawn**. Each would have added permanent cost — an ongoing 3-way merge of a
682-line vendor template, or a module boundary — to keep code that nothing calls.

This is the "correct endstate, not shortest path" answer: the endstate has _less_ code, no vendor
fork, and no structural seam.

---

## 3. The one real complication

`--global-property` can restrict generation to models, but a naive exclusion **will not compile**.

The generated model structs declare conformance to `JSONEncodable`:

```swift
public struct Book: Codable, JSONEncodable, Hashable {   // Book.swift:13
```

…and `JSONEncodable` is declared in **`Models.swift:12`** — the same file that holds the unused
`RequestTask`. A models-only run drops `Models.swift` entirely, so all 100+ model files lose the
protocol they conform to.

**Verified:** a trial `--global-property=models,apis=false,supportingFiles=…` run emitted 103 files
with the request layer correctly gone, but with **no declaration of `JSONEncodable` anywhere**.

`Models.swift` mixes wanted and unwanted declarations:

| Declared in `Models.swift`                                           | Needed?                                                                                      |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `JSONEncodable` (protocol)                                           | **Yes** — every model conforms                                                               |
| `CaseIterableDefaultsLast`                                           | **Yes** — enum models use it                                                                 |
| `NullEncodable`, `Response<T>`                                       | Keep (low cost, `Response` appears in 8 files — verify whether those are the generated type) |
| `ErrorResponse`, `DownloadException`, `DecodableRequestBuilderError` | No app references                                                                            |
| `RequestTask`                                                        | No — and it is the Swift 6 offender via `URLSessionDataTaskProtocol`                         |

So the work is **retain `Models.swift` minus its request-coupled parts**, not exclude it.

---

## 4. Implementation

### Phase 1 — Decide the exclusion mechanism

Two candidates; pick after a short trial.

**Option A — `--global-property` supporting-files allowlist**

```
--global-property=models,modelDocs=false,apis=false,supportingFiles=Models.swift:Validation.swift:Extensions.swift:CodableHelper.swift:OpenISO8601DateFormatter.swift:OpenAPIDateWithoutTime.swift:ModelError.swift
```

Keeps `Models.swift`, drops the seven request-layer files. Then a **`Models.mustache` template
override** (the mechanism A3 already established) strips `RequestTask` and the unused error enums
from it.

- **Pro**: declarative, and reuses the proven template-override path.
- **Con**: a second template override to maintain — though `Models.mustache` is far smaller and more
  stable than `URLSessionImplementations.mustache`.

**Option B — post-generation deletion in `generate-swift.sh`**

Let the generator emit everything, then `rm` the seven request-layer files and patch `Models.swift`.

- **Pro**: no second template override.
- **Con**: the script already does this kind of cleanup (`rm -rf docs`, `git_push.sh`, `.podspec`), so
  it is consistent — but a fragile `sed` on `Models.swift` is worse than a template.

**Recommendation: Option A**, with the `supportingFiles` allowlist doing the bulk of the work and a
`Models.mustache` override for the residue. If the override proves awkward, fall back to keeping
`Models.swift` whole — the only cost is `RequestTask` surviving, which then still blocks A4, so this
fallback is **not** acceptable on its own.

> Also evaluate the **`swift6` generator** (`-g swift6`). The 7.23.0 CLI advertises a swift5→swift6
> migration path. If it emits Swift-6-clean support code, it may subsume this entire plan — check it
> **before** doing Phase 2. Treat as investigation, not a given: it is a different generator with its
> own output shape, so it risks a large diff across all 100+ model files.

### Phase 2 — Trim generation

1. Update `scripts/generate-swift.sh` with the chosen mechanism.
2. Add the `Models.mustache` override if Option A.
3. Regenerate; confirm the seven request-layer files are gone and `JSONEncodable` /
   `CaseIterableDefaultsLast` survive.
4. `cd ios && xcodegen generate` — the source group is directory-based, so removed files leave the
   build automatically.
5. Build **and test** (not just build — A2 taught us the test target fails independently).

### Phase 3 — Flip to Swift 6 (this is A4)

1. `SWIFT_VERSION: '6.0'` + `SWIFT_STRICT_CONCURRENCY: complete` on **both** targets in `project.yml`.
2. `--swiftversion 6.0` in **both** `ios/.swiftformat` and `scripts/generate-swift.sh:99` — held back
   from A3 deliberately, since telling swiftformat 6.0 while the compiler is on 5.0 is incoherent.
3. `xcodegen generate`, then full gate.

Already fixed in A3 and expected to stay clean: `DebugLogger` (lock-backed global) and
`SystemKeychain` (`Sendable`).

---

## 5. Testing

- `npm run validate:full` per PR, per `CLAUDE.md` §2.
- **`api:check-drift:swift` is the critical check**: it regenerates and diffs, proving the trimmed
  generation is deterministic and reproducible on a clean checkout.
- **286 live contract tests + 698 iOS tests** exercise the real network path. If removing the
  generated layer broke anything reachable, these catch it — this is why the change is safe despite
  touching networking-adjacent code.
- Manual smoke: login, browse, stream a book, download, restore request. The removed code is unused,
  so no behavior change is expected; this confirms it.

---

## 6. Risks

| Risk                                                                   | Impact                      | Mitigation                                                                                  |
| ---------------------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------- |
| A model file references a support type not in the allowlist            | Build fails                 | Iterative: regenerate, build, add to allowlist. Fails loudly, not silently                  |
| `Response<T>` (8 file matches) turns out to be the generated type      | Build fails after removal   | Verify before excluding; retain if genuinely used                                           |
| Future spec change makes the generator want a request-layer file again | Drift check fails           | Allowlist is explicit; a new file appearing is visible in review                            |
| Generator upgrade changes `Models.mustache`                            | 3-way merge on the override | Small, stable file — far cheaper than the 682-line URLSession template C1 would have forked |
| `swift6` generator investigation balloons                              | Time sink                   | Time-box it; it is optional upside, not the plan                                            |

---

## 7. Notes carried from the parent plan

- **Generator 7.24.0 is not an upgrade path.** Its `URLSessionImplementations.mustache` is identical to
  7.23.0's except that it **drops `image/` content-type handling** — which this app needs for cover
  art. Same Swift 6 errors, plus a regression. (Moot if C3 lands and the file stops being generated,
  but re-check on future releases.)
- **`SWIFT_VERSION` cannot be set per source group.** It is target-level, and `-swift-version` is
  whole-module in the compiler. The parent plan's original "Option 3" was wrong on this point; a
  separate target was the only real form of that idea, and C3 removes the need for it.
- **Measure by flipping the real build setting and compiling both targets.** The parent plan's §1
  measurement used command-line overrides on the app target only and missed most of the real work.

---

## 8. Open questions

1. ~~**Try `-g swift6` first?**~~ — **evaluated and rejected (July 30, 2026).** It was worth the
   time-box: the swift6 generator emits `Sendable` models and drops `JSONEncodable` and
   `Configuration.swift` outright, and the per-model diff is only ~14 lines. But it also emits **14 API
   entry-point classes** (`BooksAPI`, `AuthenticationAPI`, …) plus new infra (`OpenAPIMutex`,
   `JSONValue`) that this app would never call — _more_ dead code, which is the opposite of this
   plan's goal. Stayed on `swift5` and took the `Sendable` idea via a template override instead.
2. ~~**Retain `NullEncodable` / `Response<T>` / the error enums?**~~ — **resolved: all removed.**
   Measured rather than assumed: `Response<T>` and the error enums have **zero** references from app,
   test, or model code. The 8 `Response` and 9 `Configuration` grep hits flagged in §6 as a risk were
   all false positives — the app's own `BrowseListResponse` / `BrowseListConfiguration`, plus
   `HTTPURLResponse`. `NullEncodable` was kept (harmless, and it costs nothing).
3. **Worth deleting `Package.swift` / `project.yml` from the generated dir?** Moot — the
   `supportingFiles` allowlist means neither is generated any more.

---

## 9. Implementation notes (July 30, 2026)

Phases 1–2 landed. **Phase 3 (A4) did not**, for a reason worth recording.

### What shipped

`generate-swift.sh` now passes `--global-property=models,modelDocs=false,apis=false,supportingFiles=…`
with an explicit three-file allowlist. Generated output went **112 → 102 files**; the support layer
went **11 files → 3** (`Models.swift`, `Validation.swift`, `Extensions.swift`). Four template
overrides back it: `Models`, `Extensions`, `modelObject`, `modelEnum`,
`modelInlineEnumDeclaration` (plus the pre-existing `Validation`).

### Three things the plan got wrong

1. **The `supportingFiles` allowlist alone does not compile — twice over.** §3 correctly predicted the
   `JSONEncodable` problem, but not that `Extensions.swift` **also** depends on the request layer: it
   declares `HTTPURLResponse.isStatusCodeSuccessful`, which reads
   `Configuration.successfulStatusCodeRange`, and its two `encodeToJSON()` bodies call
   `CodableHelper.dateFormatter` / `.jsonEncoder`. Both needed an `Extensions.mustache` override —
   the first deleted (dead code), the second rewritten to use a file-private formatter/encoder.

2. **`Configuration.swift` was never mentioned, and it was the first thing to fail.** §1 lists 6 errors
   in `URLSessionImplementations.swift`. On current code, the first Swift 6 error is
   `Configuration.swift:17` (`static var successfulStatusCodeRange`). Same category, same fix — but a
   plan that enumerates specific files ages badly against a moving generator.

3. **Trimming the request layer was necessary but not sufficient for A4.** With the generated layer
   gone, flipping `SWIFT_VERSION: 6.0` + `SWIFT_STRICT_CONCURRENCY: complete` on all three targets
   surfaced **9 errors, then 2** after further trimming — and the last 2 are **app code**, not
   generated:

   ```
   DownloadManager.swift:564 / :577  sending 'self.apiClient' risks causing data races
   ```

   `APIClientProtocol` is not `Sendable`, so a `@MainActor` class cannot pass its `apiClient` to an
   `await` call. Making it `Sendable` requires isolating `APIClient`'s `accessToken` and its two
   handler closures (`forceLogoutHandler`, `tokenRefreshHandler`) — i.e. real concurrency work on the
   token-refresh path that PR #131 just fixed. **Deliberately deferred to its own PR** rather than
   bundled here, so the trim can be reviewed and reverted independently of an auth-path change.

### Also required, and not anticipated: `Sendable` models

Flipping the language mode rejected every `static let` model fixture in `MockData.swift`
(`static property 'mockStandard' is not concurrency-safe because non-'Sendable' type 'Book' …`).
The generated models are immutable-by-construction value types, so the conformance is sound; three
template overrides (`modelObject`, `modelEnum`, `modelInlineEnumDeclaration`) now add `Sendable`,
matching what the swift6 generator does natively. **These shipped** — they are correct independent of
the language mode, and they are why A4's remaining diff is only the `APIClient` isolation.

### Verification

`validate:ios` green: **706 tests, 0 failures**, SwiftLint clean, and — the check that matters here —
**`api:check-drift:swift` clean**, proving the trimmed generation is deterministic and reproducible
from a clean checkout.
