# Dependency Deferrals

> **Created**: August 1, 2026
> **Status**: 4 open items. None are blocking; three are blocked upstream, one is ours to schedule.
> **History**: Carried forward from the completed
> [dependency major-upgrade ladder](../archive/completed-plans/dependency-major-upgrades.md)
> (Phases 1–6, Node 20→24, Prisma 7 + ESM, arm64/Graviton). Read that for the migration
> write-ups and for why these four were held back.

This is a **watch list**, not a plan. Each entry says what blocks it and what to re-check.
When one unblocks, give it its own branch, plan and PR — these are majors, not routine bumps.

---

## Ours to schedule

### `tailwindcss` 3 → 4

**Nothing external blocks this.** It is deferred purely on risk appetite.

- Tailwind 4 is a **CSS-first config overhaul**; we use `tailwind.config.ts`, which the new
  model replaces.
- Real UI-regression risk across the whole app. A green `validate:full` is **not** sufficient
  evidence here — this needs visual review (Storybook is the natural harness, plus a pass over
  dark mode, which every component is expected to support).
- Current: we are on 3.4.x; Tailwind is at 4.3.3 (Aug 1, 2026).

**When taken on**: its own plan doc, its own PR, and a deliberate visual diff — not folded into
another dependency pass.

---

## Blocked upstream

### `typescript` 5.9 → 7

**Blocked on typescript-eslint.** TS 7.0 (the Go-native compiler) is GA, but shipped without a
stable programmatic API, and typescript-eslint closed the support issue "not planned" pending
TS 7.1.

- Our lint gate runs `eslint-config-next/typescript`, i.e. typescript-eslint under the hood, so
  TS 7 **breaks `npm run lint`** outright.
- Re-verified Aug 1, 2026: TS is 7.0.2, but the latest `typescript-eslint` (8.65.0) still
  declares `"typescript": ">=4.8.4 <6.1.0"`. The ceiling has not moved.

**Re-check trigger**: TS 7.1 ships (~Oct 2026), or `typescript-eslint` raises its peer range.
Verify with `npm view typescript-eslint peerDependencies`.

### `eslint` 9 → 10

**Not blocked on its own, but coupled to TS 7.** eslint 10.8.0 is out and typescript-eslint 8.65
already accepts `^10.0.0`, so the peer story has improved.

Held back because there is no benefit to taking the plugin churn separately — no advisory
pressure, and the TS 7 work will touch the same surface. Do them together.

**Re-check trigger**: whenever TS 7 unblocks.

### `sharp` 0.34 → 0.35

**Blocked on Next widening its optional-dep range.** There is a **high** advisory on
`sharp <0.35.0` (GHSA-f88m-g3jw-g9cj, inherited libvips CVEs), so this is a real exposure in the
image optimizer — but we cannot clear it from this repo.

Next 16 declares sharp as an **optional dependency** (`^0.34.5`) and npm **dedupes it to our
top-level copy** — there is exactly one `sharp` installed, and it is the one Next's optimizer
loads. `sharp@0.35.3` does **not** satisfy `^0.34.5`, so bumping _un-dedupes_ rather than
upgrading. Verified against a real `--package-lock-only` resolve:

```
node_modules/sharp                   => 0.35.3   (ours, unused)
node_modules/next/node_modules/sharp => 0.34.5   (what Next uses — still vulnerable)
```

The advisory would stay uncleared and we would gain an orphan dependency.

> ⚠️ Note the original plan recorded a **different and incorrect** reason for skipping this
> ("Next uses its own internal copy we don't control"). It does not — see above. If you find that
> older reasoning quoted anywhere, it is wrong.

**Re-check trigger**: **every Next bump.** Check `npm view next optionalDependencies.sharp`; when
it accepts 0.35+, bump both together. Latest Next (16.2.12) still pins `^0.34.5`.

---

## Accepted audit findings

`npm audit` sits at **9 (6 low, 3 high)** and cannot currently go lower. Every remaining item's
"fix" is a downgrade or does not work:

| Finding                                          | Why it stays                                                                                                                                                         |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `next`, `postcss` (2 high)                       | npm's only fix is downgrading to **`next@9.3.3`**, seven majors back. Fires on postcss bundled inside Next. Awaits a Next patch.                                     |
| `sharp` (1 high)                                 | See above — bumping does not clear it.                                                                                                                               |
| `@storybook/nextjs` → `elliptic` cluster (6 low) | Fix is a downgrade to Storybook **7.0.14** (we're on 10.5), and the later `elliptic@*` advisory means no forward version clears it. Dev-only, not runtime-reachable. |

**Expect this count to drift upward** as new advisories publish against existing dependencies.
That is not a regression. Before treating a rise as one, compare against `main` — during the
Prisma 7 work the count had gone 0 → 9 highs purely from newly-published advisories, and a clean
`main` worktree reported the identical numbers.

Routine `npm audit fix` (in-semver, lockfile-only) is still worth running periodically; the
August 2026 pass cleared 6 of 9 highs that way.
