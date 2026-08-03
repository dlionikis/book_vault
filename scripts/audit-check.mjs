#!/usr/bin/env node
/**
 * Fail CI on NEW high/critical advisories, while accepting the ones we have
 * already analyzed and cannot fix from this repo.
 *
 * Why this exists: the workflow step used to be
 *
 *   run: npm audit --production --audit-level=high
 *   continue-on-error: true
 *
 * which can never fail, so a brand-new critical CVE would go unnoticed —
 * exactly the gap the Aug 3, 2026 audit flagged (S-4). Simply dropping
 * `continue-on-error` is not an option either: three high advisories are
 * currently unfixable (see docs/plans/dependency-deferrals.md), so the job would
 * fail permanently and be ignored, which is the same problem wearing a different
 * hat.
 *
 * So: allowlist the known ones by GHSA id, fail on everything else.
 *
 * Usage:
 *   node scripts/audit-check.mjs          # fail if an unaccepted high/critical exists
 *   node scripts/audit-check.mjs --list   # print what's currently found, exit 0
 *
 * When an accepted advisory becomes fixable, upgrade and delete its entry.
 * Entries that no longer appear are reported as stale so this list gets pruned
 * rather than growing forever.
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

/**
 * Advisories we have consciously accepted. Each needs a reason and, ideally, the
 * condition that would let us drop it.
 *
 * All five trace to two root causes, both analyzed in
 * docs/plans/dependency-deferrals.md:
 *
 *   postcss — npm's only "fix" is next@9.3.3, seven majors back. Our top-level
 *             postcss is already newer than the advisory range; these fire on
 *             the copy bundled inside Next. Clears when Next ships a patched
 *             bundle.
 *   sharp   — Next declares sharp as an optional dep (^0.34.5) and npm dedupes
 *             to it, so bumping our copy un-dedupes instead of upgrading.
 *             Clears when Next widens the range.
 */
const ACCEPTED = {
  'GHSA-qx2v-qp2m-jg93': 'postcss XSS via unescaped </style> — bundled inside Next',
  'GHSA-6g55-p6wh-862q': 'postcss arbitrary file read — bundled inside Next',
  'GHSA-r28c-9q8g-f849': 'postcss path traversal in source-map auto-load — bundled inside Next',
  'GHSA-fxqj-rqcc-2cmp': 'postcss incomplete fix of GHSA-6g55-p6wh-862q — bundled inside Next',
  'GHSA-f88m-g3jw-g9cj': 'sharp inherited libvips CVEs — Next pins ^0.34.5 and dedupes to it',
};

const BLOCKING = new Set(['high', 'critical']);

/** `npm audit` exits non-zero when it finds anything, so tolerate that. */
async function runAudit() {
  try {
    const { stdout } = await execFileAsync('npm', ['audit', '--production', '--json'], {
      maxBuffer: 32 * 1024 * 1024,
    });
    return JSON.parse(stdout);
  } catch (error) {
    if (error.stdout) return JSON.parse(error.stdout);
    throw error;
  }
}

/** Collect blocking advisories as `{ id, severity, module, title }`. */
function collectFindings(report) {
  const found = new Map();

  for (const vuln of Object.values(report.vulnerabilities ?? {})) {
    if (!BLOCKING.has(vuln.severity)) continue;

    for (const via of vuln.via ?? []) {
      // String entries are transitive pointers to another package's advisory;
      // the object entries carry the actual GHSA.
      if (typeof via !== 'object' || !via.url) continue;

      const id = via.url.split('/').pop();
      if (!found.has(id)) {
        found.set(id, {
          id,
          severity: via.severity ?? vuln.severity,
          module: via.name ?? vuln.name,
          title: via.title ?? '(no title)',
        });
      }
    }
  }

  return [...found.values()].sort((a, b) => a.id.localeCompare(b.id));
}

const findings = collectFindings(await runAudit());
const listOnly = process.argv.includes('--list');

if (listOnly) {
  if (findings.length === 0) {
    console.log('No high/critical advisories.');
  }
  for (const f of findings) {
    const mark = ACCEPTED[f.id] ? 'accepted' : 'NEW';
    console.log(`[${mark}] ${f.id} ${f.severity} ${f.module} — ${f.title}`);
  }
  process.exit(0);
}

const unaccepted = findings.filter((f) => !ACCEPTED[f.id]);
const seen = new Set(findings.map((f) => f.id));
const stale = Object.keys(ACCEPTED).filter((id) => !seen.has(id));

for (const f of findings.filter((f) => ACCEPTED[f.id])) {
  console.log(`✔ accepted  ${f.id}  ${f.module} — ${ACCEPTED[f.id]}`);
}

if (stale.length > 0) {
  // Not a failure: a fixed advisory should not break the build. But the entry is
  // now dead weight and should be deleted.
  console.log('');
  console.log('ℹ️  These allowlist entries no longer appear and can be removed:');
  for (const id of stale) console.log(`   ${id}  (${ACCEPTED[id]})`);
}

if (unaccepted.length > 0) {
  console.error('');
  console.error(`❌ ${unaccepted.length} unaccepted high/critical advisory(ies):`);
  for (const f of unaccepted) {
    console.error(`   ${f.id}  ${f.severity}  ${f.module} — ${f.title}`);
    console.error(`   https://github.com/advisories/${f.id}`);
  }
  console.error('');
  console.error('Fix it, or — if it is genuinely unfixable — add it to ACCEPTED in');
  console.error('scripts/audit-check.mjs with a reason, and document it in');
  console.error('docs/plans/dependency-deferrals.md.');
  process.exit(1);
}

console.log('');
console.log('✅ No new high/critical advisories.');
