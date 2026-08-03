# Development Process

> **Purpose**: The single source of truth for _how we work_ on Book Vault — every
> check that must pass, when to run it, and the hardening invariants that must
> never silently regress. If you write a test, it belongs in one of the gates
> below; otherwise it will never run.
>
> **Read this** before starting any change, and again before opening a PR.
>
> **Last Updated**: July 19, 2026
> **Related**: [testing.md](testing.md) (command cheat-sheet), [archive/completed-plans/pre-restore-hardening-plan.md](archive/completed-plans/pre-restore-hardening-plan.md) (what the invariants below come from), [CLAUDE.md](../CLAUDE.md)

---

## TL;DR — the one command

```bash
docker-compose up -d          # Postgres on :5433 (once per session)
npm run validate:full         # EVERYTHING — web gate + DB suites + iOS gate (see §2)
```

`validate:full` runs the complete gate: everything CI runs for web/backend, the
DB-dependent suites CI splits across jobs, **and** the iOS gate. It needs Xcode. If it
passes, CI should be green. Do not open a PR until it does.

Two narrower variants when you don't need both halves (see §2):

```bash
npm run validate:web          # web gate + DB suites (no iOS; no Xcode needed)
npm run validate:ios          # iOS gate only (Swift drift + SwiftLint + build + tests)
```

> **Never** claim "all tests pass" after running only `npm test`. `npm test` is unit
> tests **only** — it skips integration, contract, and E2E. See §1 for why the
> distinction matters.

---

## 1. The complete test inventory

Every automated check in the repo, what it covers, what it needs, and where it runs.
"ALL tests" means **all of these** — not just `npm test`.

| #   | Suite                                                | Command                         | Needs                                 | Env / gate                    | CI workflow     |
| --- | ---------------------------------------------------- | ------------------------------- | ------------------------------------- | ----------------------------- | --------------- |
| 1   | **Unit — node** (API handlers, `lib/`, `scripts/`)   | `npm test`                      | nothing                               | always                        | `main.yml`      |
| 2   | **Unit — dom** (components, pages)                   | `npm test`                      | nothing                               | always                        | `main.yml`      |
| 3   | **Integration** (real Postgres: downloads API, seed) | `npm run test:integration`      | Docker DB                             | `JEST_INTEGRATION=true`       | `main.yml`¹     |
| 4   | **Contract** (live server ⇄ `openapi.yaml`)          | `npm run test:contract`         | Docker DB, boots dev server           | `RUN_CONTRACT_TESTS=true`     | `api.yml`       |
| 5   | **E2E web smoke** (Playwright)                       | `npm run test:e2e`              | Docker DB, boots dev server, chromium | seeds fixtures in globalSetup | `e2e.yml`       |
| 6   | **OpenAPI spec lint**                                | `npm run api:validate`          | nothing                               | always                        | `api.yml`       |
| 7   | **TS type drift** (spec ⇄ `lib/api-types.ts`)        | `npm run api:check-drift`       | nothing                               | always                        | `api.yml`       |
| 8   | **Swift model drift** (spec ⇄ generated models)      | `npm run api:check-drift:swift` | openapi-generator                     | always                        | `api.yml`       |
| 9   | **Endpoint coverage** (every route documented)       | `npm run api:check-coverage`    | nothing                               | always                        | `api.yml`       |
| 10  | **Format**                                           | `npm run format:check`          | nothing                               | always                        | `main.yml`      |
| 11  | **Lint** (`--max-warnings 0`)                        | `npm run lint`                  | nothing                               | always                        | `main.yml`      |
| 12  | **Type check**                                       | `npm run type-check`            | nothing                               | always                        | `main.yml`      |
| 13  | **Security audit**                                   | `npm run security:audit`        | nothing                               | non-blocking                  | `main.yml`      |
| 14  | **iOS SwiftLint** (`--strict`)                       | `npm run ios:lint`              | swiftlint                             | always                        | `ios-tests.yml` |
| 15  | **iOS build**                                        | `npm run ios:build`             | Xcode, xcodegen                       | always                        | `ios-tests.yml` |
| 16  | **iOS tests** (XCTest + coverage)                    | `npm run ios:test`              | Xcode, simulator                      | always                        | `ios-tests.yml` |
| 17  | **Storybook build**                                  | `npm run build-storybook`       | nothing                               | always                        | `storybook.yml` |

¹ CI's `main.yml` runs `npm test` against a live Postgres service, so the integration
project runs there too. Locally, `npm test` alone does **not** run it — it's gated
behind `JEST_INTEGRATION=true` so a fresh clone with no Docker stays green. `validate:full`
runs it explicitly.

### Why the split exists (do not undo it)

Hardening **P1-2** partitioned Jest into three projects so a fresh clone with **no
Docker** can run `npm test` and get a fully green unit suite. Integration tests
(which need the real DB) live in `__tests__/integration/**` and only run when
`JEST_INTEGRATION=true`. Contract tests self-skip unless `RUN_CONTRACT_TESTS=true`.

**Consequence you must internalize**: a green `npm test` proves _unit_ correctness
only. The endpoint you changed might still violate the OpenAPI contract, break a
real-DB query, or fail an E2E flow. Those are suites 3–5, and they only run under
`validate:full` (or their dedicated commands). **Run the full gate.**

---

## 2. The `validate:*` family — one gate, three scopes

[`scripts/validate.sh`](../scripts/validate.sh) runs the gates from the shared step
library ([`scripts/lib/validation-steps.sh`](../scripts/lib/validation-steps.sh)),
**stopping at the first failure**. Three npm entry points select the scope:

| Command                 | Web gate | DB suites | iOS gate | Needs             |
| ----------------------- | -------- | --------- | -------- | ----------------- |
| `npm run validate:web`  | ✅       | ✅        | ❌       | Docker DB         |
| `npm run validate:ios`  | ❌       | ❌        | ✅       | Xcode             |
| `npm run validate:full` | ✅       | ✅        | ✅       | Docker DB + Xcode |

Each gate runs its steps in order:

```
Web gate (run_web_gate):
  format:check → lint → type-check → api:validate → api:check-drift
  → api:check-coverage → npm test (unit)
DB suites (require_database, then run_db_suites):
  [hard-stop if Postgres :5433 down] → test:integration → test:contract → test:e2e
iOS gate (run_ios_gate):
  api:check-drift:swift → swiftlint --strict → xcodebuild build → xcodebuild test
```

- **`validate:full` is the true "everything"** — it is what `npm run deploy` runs before
  pushing (§8), from the same library, so validation and deploy cannot diverge.
- **`validate:web`** is the everyday backend-dev command — no Xcode required, so it also
  works on CI Linux runners.
- **`validate:ios`** is the same iOS gate as `npm run ios:validate` (the `ios:*` family —
  `ios:lint` / `ios:build` / `ios:test` — remains for iOS-focused sub-runs).
- Note `api:check-drift:swift` (Swift model drift) lives only in the **iOS** gate. If you
  change `openapi.yaml` but run only `validate:web`, run `npm run validate:ios` (or at
  least `npm run api:check-drift:swift`) before pushing, or `api.yml`'s
  `check-generated-swift` job fails in CI.

Logs: `logs/validate.log`, `logs/ios-validate.log`.

---

## 3. Pre-commit hook — what runs automatically

[`.husky/pre-commit`](../.husky/pre-commit) runs on every `git commit`:

1. **`lint-staged`** — on staged files only:
   - `*.{js,jsx,ts,tsx}` → `eslint --fix` then `prettier --write`
   - `*.{json,md,yml,yaml}` → `prettier --write`
2. **If `docs/api/openapi.yaml` is staged**, it automatically:
   - regenerates `lib/api-types.ts` and `git add`s it
   - regenerates `ios/BookVault/Generated/Models/` and `git add`s them
   - runs `api:validate`; **aborts the commit** if the spec is invalid

**Implications:**

- The hook **mutates your commit** — generated files get folded in. This is expected;
  the working tree stays clean afterward. Do not fight it.
- The hook fixes formatting/lint automatically, so it is **not** a substitute for the
  full gate. It does **not** run tests, type-check, drift, coverage, or contract. A
  commit can succeed and still fail CI. **Run `validate:full` before pushing, not
  just before committing.**
- There is **no pre-push hook**. Nothing stops you from pushing a broken branch except
  discipline and CI. Run the gate.

---

## 4. What CI enforces (and what it doesn't)

Five workflows run on PRs to `main`:

| Workflow        | Runs                                                                                             | Path-filtered?                                                 | Blocking?                          |
| --------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------- | ---------------------------------- |
| `main.yml`      | format, lint, type-check, unit+integration (live PG), `npm audit`                                | no                                                             | yes (audit is `continue-on-error`) |
| `api.yml`       | spec lint, TS drift, **Swift drift**, endpoint coverage, contract tests (builds + boots the app) | no                                                             | yes                                |
| `e2e.yml`       | Playwright smoke                                                                                 | yes — `app/`, `components/`, `lib/`, `e2e/`, `prisma/`, config | yes when triggered                 |
| `ios-tests.yml` | SwiftLint (`continue-on-error`), build, XCTest + coverage                                        | yes — `ios/**`                                                 | build/test yes; lint + coverage no |
| `storybook.yml` | `build-storybook`                                                                                | no                                                             | yes                                |

**Gaps to know about** (so local runs catch what CI won't fail on):

- **`npm audit`** is `continue-on-error` in `main.yml` → a new high-severity advisory
  won't block a PR. Run `npm run security:audit` locally when touching dependencies.
- **SwiftLint** is `continue-on-error` in `ios-tests.yml` → lint violations surface as
  annotations but don't fail the build. `npm run ios:lint` runs `--strict` locally and
  **will** fail — treat local as authoritative.
- **iOS coverage** threshold (70% target) is a warning, never a failure.
- **E2E and iOS** are path-filtered. A change outside their paths won't trigger them.
  If you touch shared code that affects them indirectly, run them locally.
- CI Postgres is on **:5432**; local docker-compose is on **:5433**. Don't hard-code
  ports in tests.

---

## 5. Hardening invariants — MUST NOT regress

These came out of the [pre-restore hardening plan](archive/completed-plans/pre-restore-hardening-plan.md)
(PRs #75–#79) and the [July 2026 architecture review](analysis/architecture-review-2026-07.md).
They are load-bearing security and test-infrastructure properties. Each has a **guard**
(what keeps it true) and a **manual check** (how to verify by hand). When you add code,
do not reintroduce the anti-pattern; when you review, spot-check these.

### 5.1 Auth on every route (P0-1, P1-1)

- **Invariant**: No API route reads `getServerSession` inline. All authenticated routes
  use `requireUser(request)` (dual session/bearer) or `requireAdmin(request)` from
  `lib/api-auth.ts` / `lib/admin-auth.ts`.
- **Guard**: route tests assert 401 unauthenticated; `requireUser` unit tests
  ([`__tests__/lib/api-auth.test.ts`](../__tests__/lib/api-auth.test.ts)) pin the
  four auth combinations plus the deleted-account case.
- **Manual check**:
  ```bash
  grep -rln "getServerSession" app/api --include=route.ts | grep -v nextauth
  # → must be EMPTY
  ```
- **New route checklist**: start the handler with `requireUser`; validate the id with
  `isValidUuid` (see 5.6); add a 401 test.
- **Bearer tokens are re-checked against the DB** (SEC-2, fixed Aug 2026).
  `requireUser` looks up the account on the bearer path, so deleting a user
  revokes access immediately instead of after their access token expires (up to
  `JWT_ACCESS_TOKEN_EXPIRY`, default 1h). Web sessions are exempt — a NextAuth JWT
  carries no DB identity to re-check, and is revoked by rotating
  `NEXTAUTH_SECRET`. **Consequence for tests**: any suite that mocks `@/lib/db`
  and exercises a `requireUser` route must include
  `user: { findUnique: jest.fn() }` and resolve it to a row, or every request 401s.

### 5.2 Images route is authenticated (P0-1)

- **Invariant**: `app/api/images/[...path]/route.ts` requires auth, enforces an image
  extension allowlist, and sets `Cache-Control: private`. It must never stream an
  arbitrary S3 key unauthenticated again.
- **Manual check**: `grep -c "requireUser" "app/api/images/[...path]/route.ts"` → ≥1;
  the route test covers 401 / 200-image / 404-for-`.m4b`.

### 5.3 Chapter re-extraction is admin-only (P0-2, D4)

- **Invariant**: `POST /api/books/[id]/chapters` is gated by `requireAdmin`. `GET` stays
  user-level (lazy extraction is a feature).
- **Manual check**: `grep -c "requireAdmin" "app/api/books/[id]/chapters/route.ts"` → ≥1;
  `chapters-auth.test.ts` asserts 403 for non-admins.

### 5.4 iOS network calls go through the DI seam (P1-7)

- **Invariant**: `DownloadManager` (and all services) make network calls through the
  injected `APIClientProtocol`, never `URLSession.shared` directly. This preserves
  token refresh, consistent errors, and the `MockURLProtocol` test seam.
- **Manual check**: `grep -c "URLSession.shared" ios/BookVault/Services/DownloadManager.swift`
  → `0`.
- **When adding an APIClient method**: add it to `APIClientProtocol`, implement it in
  `APIClient` via the generic `execute` path, and add it to **both** mocks
  (`MockAPIClient` and `MockAPIClientForAuth` — the latter can `fatalError` for methods
  it doesn't exercise). Missing a conformer breaks the test-target build. _(This bit us
  in Phase 0 — the second mock was easy to forget.)_

### 5.5 Real JWT/auth tests, no global crypto stub (P1-4)

- **Invariant**: `jest.config.cjs` has **no `moduleNameMapper` stub for `jose`**. Auth
  tests mock our boundary (`@/lib/jwt`), not the crypto library. Real jose round-trip
  tests live in `__tests__/lib/jwt.test.ts`.
- **Note**: `jose` _does_ appear in `transformIgnorePatterns` (it's ESM-only and must be
  transformed) — that's correct and unrelated. The banned thing is a `moduleNameMapper`
  entry that force-stubs it.
- **Manual check**: `grep -A2 "moduleNameMapper" jest.config.cjs` shows only the `@/` alias.

### 5.6 UUID validation is real, not just normalization

- **Invariant**: `normalizeUuid()` only lowercases — it does **not** validate. Routes
  that accept an id path param must guard with `isValidUuid()` and return 400 on a bad
  id, so malformed input never reaches Prisma.
- **Anti-pattern to avoid**: `const id = normalizeUuid(x); if (!id) …` (a malformed but
  truthy id slips through). Correct: `if (!isValidUuid(id)) return 400`.
- **Known debt**: `app/api/downloads/[bookId]/route.ts` still casts
  `normalizeUuid(...) as string` without validating — clean up when next touched.

### 5.7 Test partitioning stays clean (P1-2)

- **Invariant**: a fresh clone with **no Docker** runs `npm test` fully green. DB-needing
  tests live in `__tests__/integration/**` behind `JEST_INTEGRATION=true`; contract tests
  self-skip without `RUN_CONTRACT_TESTS`.
- **Manual check**: with Docker **down**, `npm test` passes. If a new test needs the DB
  and you put it outside `__tests__/integration/`, you've broken this.

### 5.8 Coverage ratchet (P0-3)

- **Invariant**: `jest.config.cjs` `coverageThreshold.global` is a **ratchet** pinned just
  below the measured floor (currently 37/36/38/37). It only moves **up**. Never lower it
  to make a PR pass — add tests instead.
- **Manual check**: `npm run test:coverage` exits 0 with the table above the thresholds.

### 5.9 `lib/api-schemas.ts` stays test-only (P1-6, D3)

- **Invariant**: the Zod validation suite lives at `__tests__/helpers/api-schemas.ts`,
  imported only by the type-validation test — not back in `lib/`.
- **Manual check**: `ls lib/api-schemas.ts` → not found; `ls __tests__/helpers/api-schemas.ts` → found.

### 5.10 Pre-auth endpoints are rate limited (S-2)

- **Invariant**: every route reachable **without** credentials throttles by client
  IP via `checkIpRateLimit` from `lib/rate-limit.ts`. `checkRateLimit` keys on a
  user id and cannot protect these.
- **Currently covered**: `POST /api/auth/mobile/login` (10/min),
  `POST /api/auth/mobile/refresh` (30/min).
- **Known limitation**: state is an in-process `Map`, so limits are **per ECS
  task** and reset on deploy. It bounds credential stuffing; it is not a
  guarantee. Shared state (Redis/DynamoDB) or an ALB WAF rule is the real fix.
- **Manual check**: `grep -c checkIpRateLimit app/api/auth/mobile/login/route.ts` → ≥1.
- **When adding a public route**: add `checkIpRateLimit`, return **429**, and
  document the 429 in `openapi.yaml` or the contract test will fail.

### 5.11 The security-audit gate can actually fail (S-4)

- **Invariant**: CI's Security Audit job runs `npm run security:audit`
  (`scripts/audit-check.mjs`) with **no `continue-on-error`**. It fails on any
  high/critical advisory not explicitly allowlisted by GHSA id.
- **Why**: the step used to be `npm audit … ` under `continue-on-error: true`, so
  it reported pass with 3 highs outstanding and would have passed a brand-new
  critical CVE too.
- **Never** re-add `continue-on-error`, and never widen the allowlist to silence a
  fixable advisory. Add an entry only when it genuinely cannot be fixed from this
  repo, with a reason, and record it in
  [plans/dependency-deferrals.md](plans/dependency-deferrals.md).
- **Manual check**: `npm run security:audit:list` shows each finding as `accepted`
  or `NEW`; `npm run security:audit` exits 0 only when nothing is `NEW`.

### Quick invariant sweep

Run this before a PR that touches auth, routes, or iOS services:

```bash
# All should print "OK" implicitly (empty greps / expected counts)
grep -rln "getServerSession" app/api --include=route.ts | grep -v nextauth   # empty
grep -c "requireUser" "app/api/images/[...path]/route.ts"                     # >=1
grep -c "requireAdmin" "app/api/books/[id]/chapters/route.ts"                 # >=1
grep -c "URLSession.shared" ios/BookVault/Services/DownloadManager.swift      # 0
test ! -f lib/api-schemas.ts && echo "api-schemas relocated: OK"              # OK
grep -c "checkIpRateLimit" app/api/auth/mobile/login/route.ts                 # >=1
grep -E "^\s+continue-on-error" .github/workflows/main.yml                    # empty
```

---

## 6. OpenAPI-first workflow (contract discipline)

The contract test (`__tests__/api/openapi-contract.test.ts`) is **explicit per-endpoint**,
not auto-discovering. Adding a route without adding a contract case means it has **zero**
contract coverage even though `api:check-coverage` may pass (coverage checks _documentation_,
not _test cases_).

**When you add or change an endpoint:**

1. Edit `docs/api/openapi.yaml` **first** — document _every_ response status the handler
   can return (including `401`/`400`/`404`). A live status the spec doesn't declare
   **fails** the contract test. _(Phase 0 hit exactly this — the handler returned 401 but
   the spec omitted it.)_
2. Regenerate types: `npm run api:generate` (TS + Swift). The pre-commit hook also does
   this, but run it now so you can typecheck.
3. Add a `describe` block for the endpoint in `openapi-contract.test.ts` covering each
   status, each asserting `toSatisfyApiSpec()`.
4. Run `npm run test:contract` (needs Docker + seeded DB).
5. Run `npm run api:check-drift` **and** `api:check-drift:swift` so CI's drift jobs pass.

### When to regenerate — two different artifacts

"Regenerate the contracts" is ambiguous; there are two things, with different triggers:

1. **Generated type artifacts** — `lib/api-types.ts` (TS) and `ios/BookVault/Generated/Models/*.swift`. These are _generated from_ `openapi.yaml`.
2. **Contract _tests_** — `__tests__/api/openapi-contract.test.ts`. These are **hand-written**, never generated. You add/edit cases by hand.

**Generated types — the only trigger is a change to `docs/api/openapi.yaml`.** Not a new handler, not a code change — only the spec itself.

| You changed…                               | Regenerate types? | How                                                                                                 |
| ------------------------------------------ | ----------------- | --------------------------------------------------------------------------------------------------- |
| `docs/api/openapi.yaml`                    | **Yes**           | Pre-commit hook does it on commit; or `npm run api:generate` now to typecheck against the new types |
| A route handler's _logic_ (no spec change) | No                | —                                                                                                   |
| Only TS / Swift / test code                | No                | —                                                                                                   |

- The **pre-commit hook** regenerates both TS + Swift and `git add`s them automatically whenever `openapi.yaml` is staged — so in the normal flow you run nothing by hand.
- Run `npm run api:generate` manually only to typecheck _before_ committing (e.g. to reference a new type in your handler).
- **CI enforces it regardless** (`api.yml` regenerates + `git diff --exit-code`), so even a `--no-verify` commit can't ship stale types.
- Swift drift lives in the **iOS** gate — covered by `validate:full` and `validate:ios`, but **not** `validate:web`. After a spec change, run `validate:full` (or `validate:ios`, or at least `npm run api:check-drift:swift`) before pushing.

**Contract tests are never regenerated** — hand-edit a case whenever you **add or change an endpoint** (per the 5 steps above). The suite is explicit per-endpoint; a new route with no `describe` block has zero contract coverage even though `api:check-coverage` passes.

---

## 7. PR checklist

Before opening a PR:

- [ ] `npm run validate:full` green — web + DB suites + iOS (needs `docker-compose up -d`
      **and** Xcode). Backend-only change with no Xcode handy? `npm run validate:web`, but
      then someone must run `validate:ios` before merge if `ios/**` or `openapi.yaml` changed
      (SwiftLint + Swift drift live only in the iOS gate, and CI does not fail on SwiftLint).
- [ ] New/changed endpoint → spec updated, contract case added, types regenerated (§6)
- [ ] Invariant sweep clean (§5) if you touched auth, routes, or iOS services
- [ ] No AI attribution in commit/PR text (see [CLAUDE.md](../CLAUDE.md) §3.5)
- [ ] Branch off `main`; don't commit generated artifacts by hand — let the hook do it

Before a **deploy**: `npm run deploy:dry-run` green — it runs the complete gate
(web + DB suites + iOS) without deploying (§8).

---

## 8. Deployment (`npm run deploy`)

[`scripts/deploy.sh`](../scripts/deploy.sh) runs a **validation phase** and then a
**deploy phase**, both under `set -eo pipefail` — so **any failing validation step
aborts the whole deploy before a single byte ships**. When a deploy "fails to deploy,"
check the validation phase first; it usually never reached AWS. The log is
`logs/deploy.log`.

### Deploy variants

| Command                  | Web checks | iOS checks | Deploys? |
| ------------------------ | ---------- | ---------- | -------- |
| `npm run deploy`         | yes        | **yes**    | yes      |
| `npm run deploy:web`     | yes        | no         | yes      |
| `npm run deploy:only`    | no         | no         | yes      |
| `npm run deploy:dry-run` | yes        | yes        | no       |

### Deploy validation = `validate:full` + iOS (shared source of truth)

`deploy.sh` and `validate.sh` both source the same step library
([`scripts/lib/validation-steps.sh`](../scripts/lib/validation-steps.sh)), so their
validation **cannot diverge**. Deploy runs the **identical web gate + DB suites** as
`validate:full`, then adds the **iOS gate**:

| Stage                                                      | `validate:full` | `deploy` / `deploy:dry-run` |
| ---------------------------------------------------------- | --------------- | --------------------------- |
| Web gate (format, lint, type-check, api\*, unit)           | ✅              | ✅                          |
| DB suites (integration, contract, E2E)                     | ✅              | ✅                          |
| iOS gate (Swift drift, `swiftlint --strict`, build, tests) | ❌              | ✅                          |

- `deploy` is therefore a **superset** of `validate:full`. `deploy:web` runs the web
  gate + DB suites (no iOS); `deploy:only` skips all validation.
- Because deploy now runs the DB suites, **Postgres must be up** (`docker-compose up -d`)
  for any deploy that runs web validation — the shared `require_database` step hard-stops
  with a clear message otherwise.
- **Why this alignment matters**: `swiftlint --strict` is a **hard gate** in the iOS part,
  but CI's `ios-tests.yml` runs SwiftLint as `continue-on-error`. So a lint violation can
  still pass CI green and block `npm run deploy` — which is exactly what happened once (an
  unused-closure-param from a merged PR). Running the shared gate locally is what catches
  it. (Making SwiftLint blocking in CI would close this gap entirely — a good follow-up.)

**Takeaway**: **`npm run deploy:dry-run`** runs the complete gate (web + DB + iOS) without
deploying — the best single pre-deploy check.

### Validation phase — exact steps (from the shared library)

Web gate (`run_web_gate`): `format:check` → `lint` → `type-check` → `api:validate` →
`api:check-drift` → `api:check-coverage` → `npm test`.

DB suites (`run_db_suites`, after `require_database`): `test:integration` →
`test:contract` → `test:e2e`.

iOS gate (`run_ios_gate`, deploy only): `api:check-drift:swift` → `swiftlint --strict` →
`xcodebuild build` → `xcodebuild test`.

### Deploy phase requirements (what the AWS push needs)

Only reached after validation passes (skipped entirely on `--dry-run`):

- **AWS CLI** authenticated with the **`book_vault` profile** (`AWS_PROFILE=book_vault` /
  `--profile book_vault`), region **us-east-1**, with permission to `sts:GetCallerIdentity`,
  ECR (`get-login-password`, push), and ECS (`update-service`, `wait services-stable`).
- **Docker with `buildx`** — builds `linux/amd64` (cross-build on Apple Silicon) and
  pushes to ECR `book-vault:latest`.
- **`osxkeychain` docker cred helper** — deploy writes a temp `DOCKER_CONFIG` using it.
- Deploys to **both** ECS services `book-vault-spot` and `book-vault-fallback` with
  `--force-new-deployment`, waits for `book-vault-spot` to stabilize, then hard-checks
  `https://bookvault.lionikis.com/api/health` (deploy fails if health check fails).
- A **git safety prompt** (`check_git_status`) warns if you're off `main` or have
  uncommitted/untracked changes, because Docker builds from your **local filesystem**,
  not from git. Confirm intentionally.

Full AWS architecture: [aws-deployment-reference.md](aws-deployment-reference.md).

---

## 9. Environment quick reference

```bash
docker-compose up -d                 # Postgres :5433 (local). CI uses :5432.
npx prisma migrate deploy            # apply migrations
npm run db:seed                      # seed test fixtures (LOCAL ONLY — see §10)
```

`db:seed` creates **two** accounts and pins their admin flags, because the
contract suite asserts both sides of the admin gate on
`POST /api/books/{id}/chapters`:

| Account             | Password      | `isAdmin` | Used for                  |
| ------------------- | ------------- | --------- | ------------------------- |
| `testuser`          | `password123` | **true**  | the 200 case; general dev |
| `testuser-nonadmin` | `password123` | **false** | the 403 case              |

Both flags are rewritten on every run, so a database seeded before this mattered
self-repairs. Overridable via `TEST_USER_USERNAME` / `TEST_USER_PASSWORD` and
`TEST_NONADMIN_USERNAME` / `TEST_NONADMIN_PASSWORD`.

Contract & E2E boot a real dev server and seed fixtures; they need the DB up first.
`validate.sh` hard-stops with a clear message if :5433 is unreachable.

---

## 10. Test accounts in production — clean up when done

`testuser` / `password123` is published in this repository (CLAUDE.md, README,
`.env.example`, this file). **The repo is public**, so any internet-reachable
environment still holding that account is accepting a credential anyone can
read.

This is fine locally. It is not fine in production, and it has happened: on
**August 3, 2026** `testuser` was found live in prod — it authenticated against
`/api/auth/mobile/login`, listed the full catalog, and obtained audio streaming
URLs. It could not reach `/api/admin/*` (403), so there was no privilege
escalation.

`testuser` is legitimately useful in prod for short App Store review and
smoke-test windows. The rule is that it must not outlive the test.

### The process

```bash
npm run user:list prod          # who exists, with admin flag + last login/active
npm run user:cleanup:check      # read-only: is a test account lingering? exit 2 if yes
npm run user:cleanup prod       # delete it (prompts for confirmation)
npm run user:cleanup prod --yes # same, no prompt (for automation)
```

Run `user:cleanup prod` **as the last step of any production test session** that
created or used `testuser`. Verify with `npm run user:list prod`.

`--check` changes nothing and exits **2** when an account is found, so it works
as a CI or cron guard.

### Notes

- Deletion is a **hard delete** and cascades to every user-owned table:
  progress, lists, downloads, device tokens, refresh tokens, restore requests.
  There is **no soft-delete or disabled flag** on `users` — the only columns are
  `id`, `username`, `passwordHash`, `isAdmin`, `createdAt`, `updatedAt`.
- `scripts/cleanup-test-users.sh` targets an **explicit name array** (`testuser`)
  plus one narrow prefix pattern, never a loose `test%` sweep.
- The prefix pattern covers `contract-nonadmin-<digits>`, which is now **legacy
  cleanup only**. The contract suite used to `POST /api/auth/register` for a
  throwaway non-admin on every run and never delete it, leaking one row per run
  (109 had piled up locally by Aug 3, 2026). That endpoint has been removed and
  the suite logs in as the seeded `testuser-nonadmin` instead, so nothing new
  accumulates — the pattern stays only to sweep databases seeded before the fix.
  The trailing-digits anchor is required, so an account named
  `contract-nonadmin-realperson` is **not** matched.
- `app-review-tester` is deliberately **excluded**: it is a real App Store review
  account with its own password. Removing it is a judgement call, not cleanup.
- If a long-lived prod test account is genuinely needed, give it a unique
  generated password (`npm run user:create prod <name>` generates one) and keep
  that password out of the repo. Do not reuse the documented dev password.
