# Dependency Major-Version Upgrade Plan

> **Created**: July 19, 2026
> **Status**: In progress — Phases 1 ✅, 2 ✅, 3 ✅, 4 ✅, 5 ✅ done (July 19, 2026); Phase 5b
> (Prisma 7) + Phase 6 planned. **`npm audit`: 0 high/critical** as of Phase 4.
> **Context**: The safe, in-semver dependency updates + `npm audit fix` already landed
> (26 → residual vulnerabilities, all remaining ones require the breaking upgrades below).
> This plan covers the **major-version** jumps deliberately deferred from that pass.
> **Related**: [development-process.md](../development-process.md) (run `validate:full` after each phase), the residual `npm audit` items.

---

## Why these are separate from routine updates

`npm audit fix` and `npm update` handle everything within the current major ranges.
What remains are major bumps that change APIs, break builds, or shift framework behavior —
each needs its own branch, migration guide, and a full `validate:full` + Docker build +
on-device iOS check. **Do not `npm audit fix --force`** — it would apply all of these at
once and almost certainly break the build.

Everything here is currently **mitigated or non-exploitable in production**:

- The one prod-facing high (Next.js Image Optimizer DoS, GHSA-9g9p-9gw9-jx7f) is
  **mitigated** by tightening `images.remotePatterns` off `**` to the S3 hosts
  ([next.config.js](../../next.config.js)). The full fix ships in Next 16 (Phase 2).
- The rest are dev/test/build tooling (Storybook, jest-openapi/axios, redocly,
  eslint, openapi-typescript) — real advisories, but not attacker-reachable at runtime.

---

## Residual advisories these upgrades clear

| Advisory                                  | Fixed by                                                                                                                                                                                                                           | Surface    |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Next.js Image Optimizer DoS (high)        | `next` 16 — ✅ CLEARED (Phase 2)                                                                                                                                                                                                   | prod       |
| `postcss` XSS in stringify (moderate)     | NOT cleared by Next 16 — fires on postcss **bundled inside** next (`<8.5.10`); our top-level postcss is 8.5.19. Awaits a Next patch.                                                                                               | build      |
| `axios` CSRF / `openapi-validator` (high) | **npm `overrides`** (openapi-validator → axios ^1.12) — ✅ CLEARED (Phase 4). `jest-openapi` 0.14.2 is the latest and still pins `openapi-validator` → `axios@0.21`, so a version bump alone did NOT clear it.                     | test       |
| `undici` decompression DoS (high)         | `undici` **7** — ✅ CLEARED (Phase 4). Direct devDep bump 5→7 (NOT 8 — undici 8 requires Node ≥22.19 and crashes on the Node 20 CI/prod runtime; 7 feature-detects `markAsUncloneable`). Needed a jest.setup Web-Streams polyfill. | build/test |
| `elliptic`/`crypto-browserify` (low)      | `@storybook/*` 10.5                                                                                                                                                                                                                | dev        |
| `uuid` bounds check (moderate)            | `next-auth` (via Next 16 stack)                                                                                                                                                                                                    | prod (low) |
| OpenTelemetry baggage (moderate)          | `@redocly/cli` 2                                                                                                                                                                                                                   | dev (docs) |

Re-run `npm audit` after each phase; the goal is **zero high/critical**, moderates as low
as the toolchain allows.

---

## Phased plan (independent branches, low-risk → high-risk)

Each phase: branch off `main` → upgrade → follow the migration notes → `npm run validate:full`
→ Docker build → (if iOS touched) on-device smoke → PR. Land one before starting the next.

### Phase 1 — Tooling-only majors (low risk, no runtime impact) — ✅ DONE (July 19, 2026)

Landed in `deps/phase-1-tooling-majors`. Cleared the **OpenTelemetry advisory cluster**
(via redocly v2). `@types/node` was pinned to **^22** (not 26) to match the Node 20 ECS
runtime. `openapi-typescript` 7's stricter internal redocly validation forced resolving
the verify endpoint's nullable `user` field: the `allOf`+`nullable` form was replaced with
an **inline `type: object` + `nullable: true`** schema — the only 3.0 shape redocly v2,
openapi-typescript 7, AND jest-openapi's runtime validator all accept (keep it in sync with
the `User` component). The now-redundant `.redocly.lint-ignore.yaml` was removed.
Verified: `validate:full` (web 369/13/218 + E2E, iOS build+test) + Docker build all green.
`undici` did **not** clear here (openapi-typescript 7 still pulls a flagged transitive) —
reassigned to a later phase.

Bundle these; none touch shipped code.

| Package              | 5.x/current → target  | Notes                                                                                                                                                                   |
| -------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@redocly/cli`       | 1.34 → 2.x            | New lint defaults; may need `redocly.yaml` tweaks (we already have one). Clears the OpenTelemetry advisories.                                                           |
| `openapi-typescript` | 6.7 → 7.x             | Output reformatted (4-space, inline objects) — regenerated + reviewed (semantically identical); forced the verify `user` inline-schema rewrite. Did NOT clear `undici`. |
| `concurrently`       | 8 → 10                | CLI flags stable; used in `test:contract`.                                                                                                                              |
| `lint-staged`        | 16 → 17               | Config format stable.                                                                                                                                                   |
| `wait-on`            | 7 → 9                 | Used in `test:contract:wait`.                                                                                                                                           |
| `@types/node`        | 22 → **^22 (pinned)** | Type-only. Pinned to ^22 to match the Node 20 ECS runtime — NOT 26 (local is 26).                                                                                       |

**Acceptance**: `validate:full` green; generated types reviewed; contract tests pass.

### Phase 2 — Next.js 14 → 16 (highest impact) — ✅ DONE (July 19, 2026)

Landed in `deps/phase-2-next-16`. **Cleared the prod Image Optimizer high** (GHSA-9g9p-9gw9-jx7f).

What it took:

- `next` 14.2.35 → **16.2.10**, `eslint-config-next` → 16. **Kept next-auth v4** (compatible
  with Next 16 / React 18 App Router) and **React 18** — no v5 auth rewrite needed, keeping
  this phase focused on Next itself.
- **Async request APIs**: ran `npx @next/codemod next-async-request-api` (20 files). It
  converted `params`/`searchParams` to `Promise` + `await` correctly in pages and route
  handlers (including routes that pass `params` into shared helpers). **Two things it got
  wrong / didn't cover**: (1) it wrote `await searchParams` instead of `await
props.searchParams` in 4 entity pages — fixed by hand; (2) all test call sites still
  passed sync `{ params: {...} }` — updated to `Promise.resolve({...})`.
- `next.config.js`: `serverActions` **stays under `experimental`** in Next 16.
  (Phase 2 initially moved it to a top-level key; Next 16 rejects that as an
  unrecognized key and silently drops `bodySizeLimit`. Corrected in the deploy
  hotfix — see the arm64/deploy section below.)
- **ESLint**: `eslint-config-next` 16 is flat-config-only; the old `FlatCompat`/`.eslintrc`
  shim crashed. Rewrote `eslint.config.mjs` to import `eslint-config-next/core-web-vitals`
  and `eslint-plugin-storybook`'s `flat/recommended` natively. Its new
  `react-hooks/set-state-in-effect` error flagged 4 known-good SSR patterns (hydration
  `mounted` guards, one initial fetch) — scoped that rule `off` for those 4 files only
  (stays an error everywhere else; reviewed each).
- **Jest**: `next/jest` 16 restructured `transformIgnorePatterns` (no longer a plain
  `/node_modules/` string), which silently dropped our ESM allowlist and broke jose/@aws-sdk
  transform. Rewrote `allowEsmPackages` to inject the allowlist into whatever the first
  node_modules pattern is — now resilient to Next's pattern shape.
- Next 16 auto-updated `next-env.d.ts` (typed routes) and `tsconfig.json` (`jsx: react-jsx`,
  `.next/dev/types` include) — kept as generated.

Verified: `validate:full` green — web (unit 369, integration 13, contract 218/218, E2E 1
passed) + iOS (SwiftLint 0, build + test) — and Docker build clean. E2E exercised the real
login → search → detail → play → add-to-library flow on Next 16.

**Residual after Phase 2** (all dev/build/Next-internal, mapped to later phases): `postcss`
XSS advisory now fires on a copy **bundled inside Next 16** (`<8.5.10`); our top-level
`postcss` is already 8.5.19. `undici`, `axios`/`jest-openapi`/`openapi-validator` unchanged
(Phase 4 / later).

**Rollout note**: `images.remotePatterns` stays tightened (defense in depth). Do a real
canary/staging deploy before prod — this is a framework major.

### Phase 3 — React 18 → 19 (+ @types/react 19, react-dom 19) — ✅ DONE (July 19, 2026)

Landed in `deps/phase-3-react-19`. Turned out **near-mechanical** — a pre-flight scan found
**none** of the React 19 breaking-change patterns in the codebase (no `forwardRef`,
`useFormState`, `propTypes`, `ReactDOM.render`, or `defaultProps`), so no codemod was needed.

- `react`/`react-dom` 18.3.1 → **19.2.7**, `@types/react`/`@types/react-dom` → 19.
  **Did NOT need to bundle Phase 4** — verified Next 16, Storybook 10.5 (already on 10.5 from
  Phase 1's minor bumps), and Testing Library 16.3 all list `^19.0.0` in their react peer deps.
- **One type fix**: React 19 removed the global `JSX` namespace. `admin-dashboard.test.tsx`
  used `Promise<JSX.Element>` → added `import type { JSX } from 'react'`.
- **`.prettierignore`**: added `next-env.d.ts`. Next regenerates it with double quotes on
  every build; prettier kept reformatting it to single quotes (a permanent tug-of-war). The
  file says "should not be edited" — now correctly left to Next.

Verified: `validate:full` green — web (unit 369, integration 13, contract 218/218, E2E 1
passed; component/page tests exercise React 19 via Testing Library 16) + iOS (build + test) —
plus **`build-storybook` clean** (Storybook 10.5 + React 19) and Docker production build clean.

React 19 clears no advisories (expected); none regressed.

**Acceptance**: ✅ all component/page tests green; Storybook builds; app builds & renders.

### Phase 4 — Storybook pin + clear the axios & undici highs — ✅ DONE (July 19, 2026)

Landed in `deps/phase-4-storybook-jest-openapi`. **Cleared all remaining high advisories —
`npm audit` now reports 0 high/critical.** This phase turned out different from the original
framing (recorded here so the reasoning survives):

- **Storybook**: already running **10.5.2**, but `package.json` still pinned `^10.1.10` (the
  caret had floated up on install). Pinned the four `@storybook/*` + `storybook` +
  `eslint-plugin-storybook` to `^10.5.2` so the manifest matches reality. This already cleared
  the `elliptic`/`crypto-browserify` cluster.
- **axios high — NOT fixable by a version bump.** The plan assumed `jest-openapi` 0.14 clears
  it; it does not. `jest-openapi@0.14.2` is the **latest** release and still depends on
  `openapi-validator@^0.14.2`, which pins the ancient `axios@0.21.4` (the vulnerable one).
  There is no newer jest-openapi. Fixed with a scoped npm **`override`**
  (`openapi-validator` → `axios: ^1.12.0`), resolving to 1.18.1. Safe because our contract
  suite calls `jestOpenAPI(localFilePath)` — it never exercises openapi-validator's remote
  (axios) spec-fetch path. **Consequence**: axios 1.x removed the internal
  `require('axios/lib/adapters/http')`; two contract test files used it to force the Node
  adapter under jsdom — switched both to the supported `axios.defaults.adapter = 'http'`.
- **undici high — pulled forward from "deferred".** `undici` was a direct devDep pinned
  `^5.29.0` (the last remaining high, `<=6.26.0`). It's only a **test-only Fetch polyfill** in
  `jest.setup.js` (`Request`/`Response`/`Headers`/`FormData`), so bumped it to **`^7.16.0`**
  (resolves 7.28.0). **Not 8**: undici 8 requires Node **≥22.19** and calls
  `webidl.util.markAsUncloneable` unconditionally, which throws on the **Node 20** CI/prod
  runtime (`TypeError: markAsUncloneable is not a function` — caught by CI, not by local Node
  26). undici 7 feature-detects that API, so it runs on Node 20 and still clears the advisory
  (fix range is `<=6.26.0`). Verified undici 7 loading under a real `node:20-alpine` container.
  undici 8's fetch reads the Web-Streams globals off `global`, which jsdom doesn't define →
  added a `ReadableStream`/`WritableStream`/`TransformStream` + `MessagePort` polyfill (from
  `node:stream/web` / `node:worker_threads`) in `jest.setup.js` before requiring undici (undici
  7 benefits from the same polyfill). **undici 8 becomes available once the Node 20→22 base-image
  move lands** (see Runtime/infrastructure below).

Verified: contract suite **218/218** with axios 1.18.1; `build-storybook` clean; `validate:web`
green (unit, integration, contract, E2E smoke); `npm audit` **0 high/critical** (4 moderates
remain: `next`/`next-auth`/`postcss`/`uuid` — all framework-internal, awaiting Next patches /
next-auth v5). No iOS files touched.

**Acceptance**: ✅ `build-storybook` green; contract tests green; `npm audit` shows the
axios/openapi-validator **and** undici highs cleared.

### Phase 5 — Prisma 5 → **6** + browse-page `force-dynamic` — ✅ DONE (July 19, 2026)

Landed in `deps/phase-5-prisma-6`. **Scope changed from the original "5 → 7".** Prisma 7 turned
out to be a data-layer overhaul, not a routine bump — it forces ESM (`"type": "module"` +
`tsconfig` module changes), a required **`prisma.config.ts`**, a **driver adapter** in the
`PrismaClient` constructor (a real `lib/db.ts` rewrite), env vars no longer auto-loaded, and CLI
changes that ripple into our `db:migrate`/`db:seed` scripts and the Dockerfile's
`node_modules/.prisma` COPYs. Per the "if a phase balloons, split it" guardrail, **Prisma 7 is
carved into its own plan** (see below) and best sequenced with the Node 20→22 move (v7 wants Node
≥20.19; we're on 20.20).

Prisma **6** is a clean, low-risk stop for this codebase:

- `prisma` + `@prisma/client` 5.22.0 → **6.19.3**. Kept the `prisma-client-js` generator, so the
  client still generates to `node_modules/.prisma` — the Dockerfile COPYs and every
  `@prisma/client` type import (`Prisma.BookSelect` in `lib/api-utils.ts`, `Prisma.BookGetPayload`
  in `lib/book-transformer.ts`) are unchanged. `tsc` clean, no code changes needed.
- **None of Prisma 6's breaking changes apply**: no `Bytes` fields (so no `Buffer`→`Uint8Array`),
  no implicit m-n relations (we use explicit join tables — no relation-table migration), no
  `NotFoundError` catches / `findUniqueOrThrow`, no `fullTextSearch`/preview features. `P2002` is
  matched as a raw code string, unaffected.
- **Browse-page build noise fixed**: added `export const dynamic = 'force-dynamic'` to the four
  `/browse/{categories,authors,narrators,series}` pages. They were DB-backed but Next tried to
  statically prerender them during `next build` (no `DATABASE_URL`), the query threw, the
  `try/catch` swallowed it, and the build log filled with
  `PrismaClientInitializationError: Environment variable not found: DATABASE_URL`. Now Next renders
  them per-request (as it already did in prod) and the build log is clean.

Verified: `prisma migrate status` clean (3 migrations, schema up to date); integration **13/13**
(real Postgres, exercises `$transaction` both forms + `mode:'insensitive'`); contract **218/218**;
unit green; Docker native-arm64 build clean with no browse-page Prisma noise. (E2E smoke flaked
once on a transient JWT/session timing issue during the combined gate, then passed **3/3** in
isolation — unrelated to Prisma/the browse change.)

**Acceptance**: ✅ `prisma migrate status` clean; integration + contract green; browse-page Prisma
errors gone from the build log.

### Phase 5b — Prisma 6 → 7 (own plan; do with / after Node 22) — planned

Not a routine bump. Required before/with this work:

- **Node 20 → 22** first (v7 needs Node ≥20.19; pairs naturally with the base-image move below).
- **ESM**: `"type": "module"` + `tsconfig` (`module: ESNext`, `moduleResolution: bundler`).
  Verify Next 16 build + jest (`next/jest`) still work — this is the biggest unknown.
- **New `prisma-client` generator** with a **required `output`** path (client leaves
  `node_modules/.prisma`). Update: the two type-import sites, `lib/db.ts`, the Dockerfile COPYs
  (`node_modules/.prisma` + `@prisma`), `.dockerignore`, and the inline `require('@prisma/client')`
  shell scripts (`db-migrate.sh`, `create-user.sh`, `delete-user.sh`, `reset-password.sh`,
  `db-connect.sh`).
- **`prisma.config.ts`** at project root; **explicit env loading** (`import 'dotenv/config'`).
- **Driver adapter** required in the `PrismaClient` constructor → rewrite `lib/db.ts`.
- **CLI**: `generate` no longer auto-runs with `migrate`; seeding is manual — update
  `db:migrate`/`db:seed`, `scripts/db-migrate.sh`, and the CI/Docker `prisma generate` steps.
- The one deep-mock test (`__tests__/scripts/import-libation.test.ts`, `mockDeep<PrismaClient>()`)
  is the most likely type-shape casualty.

**Acceptance**: `prisma migrate` clean on a fresh DB; integration + contract green; Docker build +
a real deploy; the new generated-client path resolves in the standalone runtime.

### Phase 6 — Remaining ecosystem majors (evaluate individually)

Lower urgency; some may not be worth it:

- `typescript` 5.9 → 7.x — large; wait until the ecosystem (Next, eslint) supports it.
- `tailwindcss` 3 → 4 — config format overhaul (CSS-first config); notable UI-regression risk.
- `zod` 3 → 4 — used in the api-schemas test helper; check breaking API.
- `eslint` 9 → 10 — flat-config already in use; check plugin compat.
- `node-fetch` 2 → 3 (ESM-only) — only if still used; prefer removing in favor of global `fetch`.
- `sharp` 0.34 → 0.35 — minor within 0.x but native; verify image handling in Docker.
- ~~`undici`~~ — ✅ done in Phase 4 (direct devDep 5→8, test-only Fetch polyfill).

---

## Runtime / infrastructure (not a package.json dep)

### Deploy build: cross-arch amd64 → native arm64 (Graviton) — ✅ DONE (July 19, 2026)

**Why this changed.** After the Next 16 upgrade (Phase 2) merged, `npm run deploy`
failed at the Docker build. The build cross-compiled to amd64 via
`docker buildx build --platform linux/amd64` on the Apple-Silicon build host, and
Next 16's SWC compiler (a native Rust binary) **segfaults under qemu emulation**:

```
#20 [builder 6/6] RUN npm run build
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
```

Refreshing binfmt + a fresh buildx builder does **not** fix it — qemu itself
mis-executes the SWC binary. (Verified: reproduced the segfault after a full
`tonistiigi/binfmt --install all` + new builder.)

**Fix.** Build **natively arm64** (no emulation) and run ECS on **Graviton**:

- [scripts/deploy.sh](../../scripts/deploy.sh) `run_deploy()`: `docker buildx build
--platform linux/amd64` → plain `docker build` (native arm64), with an arch guard
  that aborts if the built image isn't arm64.
- ECS task definition **`book-vault:5`** registered from `:4` with
  `runtimePlatform={cpuArchitecture: ARM64, operatingSystemFamily: LINUX}`.
  `update-service` now passes `--task-definition book-vault:5` explicitly (force-new
  alone keeps the service's current revision, so it's required to move off the old
  x86_64 `:4`).
- Fargate **Spot supports ARM64** (since Oct 2024), so both `book-vault-spot` and
  `book-vault-fallback` run it. Graviton is also ~20% cheaper.

Verified: native `docker build` succeeds in ~50s; the arm64 image boots
(`process.arch === 'arm64'`, Next 16 "Ready"); all native deps (bcrypt, prisma
engines, sharp, ffmpeg) work on arm64. The **first** arm64 rollout is a real prod
cutover — watch the `book-vault-fallback` (on-demand) task come healthy before
trusting Spot capacity.

**Consequence for the Node bump below:** the base image is now effectively arm64 —
`node:22-alpine` is multi-arch, so no extra change is needed there.

### Node 20 → 22 on the Docker base image

**Real deadline, harmless today.** The AWS SDK bump in #90 (3.958 → 3.1090) surfaced a
build-log warning:

```
NodeVersionSupportWarning: The AWS SDK for JavaScript (v3) versions published after the
first week of January 2027 will require node >=22. You are running node v20.20.2.
```

Our Docker image is `node:20-alpine` (deps/builder/runner stages in [Dockerfile](../../Dockerfile)).
Node 20 also reaches EOL **April 2026**. So this move is warranted regardless of the SDK.

- Change all three `FROM node:20-alpine` stages to `node:22-alpine`.
- Keep `@types/node` in step (it's pinned to `^22` — see Phase 1 — which already matches 22).
- Verify the Docker build + a real deploy; confirm the SDK warning is gone.
- **Best paired with a future AWS SDK bump** (so the runtime and SDK move together), but
  can be done standalone anytime before the 2027 cutoff.

---

## Guardrails

- **One phase per PR.** Never combine framework majors.
- After each phase, update this file's status and re-run `npm audit` + `validate:full`.
- Keep the `images.remotePatterns` tightening and the `redocly.yaml` / Jest ESM-allowlist
  entries — they were added to survive the safe-update pass and remain correct.
- If a phase balloons (e.g. NextAuth v5, Tailwind 4), split it into its own plan.
