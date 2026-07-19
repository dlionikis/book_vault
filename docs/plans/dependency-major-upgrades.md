# Dependency Major-Version Upgrade Plan

> **Created**: July 19, 2026
> **Status**: In progress — Phases 1 ✅, 2 ✅, 3 ✅ done (July 19, 2026); Phases 4–6 planned
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

| Advisory                                  | Fixed by                                                                                                                             | Surface    |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| Next.js Image Optimizer DoS (high)        | `next` 16 — ✅ CLEARED (Phase 2)                                                                                                     | prod       |
| `postcss` XSS in stringify (moderate)     | NOT cleared by Next 16 — fires on postcss **bundled inside** next (`<8.5.10`); our top-level postcss is 8.5.19. Awaits a Next patch. | build      |
| `axios` CSRF / `openapi-validator` (high) | `jest-openapi` 0.14                                                                                                                  | test       |
| `undici` decompression DoS (moderate)     | `undici` 8 (openapi-typescript 7 alone did **not** clear it — Phase 1)                                                               | build/test |
| `elliptic`/`crypto-browserify` (low)      | `@storybook/*` 10.5                                                                                                                  | dev        |
| `uuid` bounds check (moderate)            | `next-auth` (via Next 16 stack)                                                                                                      | prod (low) |
| OpenTelemetry baggage (moderate)          | `@redocly/cli` 2                                                                                                                     | dev (docs) |

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
- `next.config.js`: `experimental.serverActions` → stable top-level `serverActions`.
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

### Phase 4 — jest-openapi (+ any remaining Storybook/webpack transitive advisories)

- **Note**: Storybook is already on **10.5** (Phase 1's in-semver bumps) and builds clean
  on React 19 (verified in Phase 3), so the "Storybook major" framing is largely moot. What
  remains is whether any `elliptic`/`crypto-browserify`/`node-polyfill-webpack-plugin`
  transitive advisories still surface under `@storybook/nextjs` — check `npm audit` and bump
  only if flagged; a further `@storybook/*` bump may pull those in.
- `jest-openapi` 0.14 — clears the `axios`/`openapi-validator` high. **Watch out**: the
  contract suite depends on `toSatisfyApiSpec`; verify the matcher API is unchanged (it drove
  the verify-endpoint nullable-`user` handling in Phase 1).

**Acceptance**: `build-storybook` green; contract tests green; `npm audit` shows the
axios/openapi-validator highs cleared.

### Phase 5 — Prisma 5 → 7 (data layer, careful)

- Two majors (5 → 6 → 7). Read both upgrade guides.
- Regenerate client (`prisma generate`); run migrations against a scratch DB;
  run the integration suite (real Postgres) hard.
- Watch for query-engine / client API changes and any raw-query usage.
- **While here — silence the build-time Prisma noise** (independent of the version
  bump, can be done anytime): the `/browse/{categories,authors,narrators,series}`
  pages are DB-backed but Next treats them as `○ (Static)` and runs their
  `prisma.*.findMany()` during `next build`, where there is no `DATABASE_URL`. The
  queries throw, the pages' own `try/catch` swallows it, and Next renders them at
  runtime anyway (they work in prod) — but the build log fills with alarming
  `PrismaClientInitializationError: Environment variable not found: DATABASE_URL`.
  Add `export const dynamic = 'force-dynamic'` (or `revalidate`) to those four page
  components so Next never attempts static prerender. Removes the noise and avoids
  shipping an empty build-time snapshot.

**Acceptance**: `prisma migrate` clean on a fresh DB; integration + contract tests
green; the browse-page Prisma errors no longer appear in the build log.

### Phase 6 — Remaining ecosystem majors (evaluate individually)

Lower urgency; some may not be worth it:

- `typescript` 5.9 → 7.x — large; wait until the ecosystem (Next, eslint) supports it.
- `tailwindcss` 3 → 4 — config format overhaul (CSS-first config); notable UI-regression risk.
- `zod` 3 → 4 — used in the api-schemas test helper; check breaking API.
- `eslint` 9 → 10 — flat-config already in use; check plugin compat.
- `node-fetch` 2 → 3 (ESM-only) — only if still used; prefer removing in favor of global `fetch`.
- `sharp` 0.34 → 0.35 — minor within 0.x but native; verify image handling in Docker.
- `undici` — transitively resolved by Phase 1/2; pin only if still flagged.

---

## Runtime / infrastructure (not a package.json dep)

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
