/**
 * The public attack surface is an explicit allowlist.
 *
 * ## Why this test exists
 *
 * `POST /api/auth/register` shipped on 2025-12-23 in the first auth commit and
 * survived until 2026-08-03 — roughly seven months — on a public production
 * site. Anyone could create an account and stream the whole library.
 *
 * Nothing was broken in the usual sense, which is the point. The endpoint was
 * catalogued in docs/API_SECURITY.md with a green check, under a heading that
 * read "All critical endpoints properly secured", next to a description of a
 * "private library model where users must log in to access any content".
 *
 * It passed review because the question being asked was **"is this endpoint
 * authenticated?"** and registration is *supposed* to be unauthenticated. The
 * question nobody asked was **"should a private library have a public signup
 * endpoint at all?"**
 *
 * Invariants 5.1–5.9 all encode "auth is present where required". None of them
 * encoded "the set of intentionally-public routes is small, deliberate, and
 * justified". This test is that missing invariant.
 *
 * ## What it does
 *
 * Walks every `app/api/**\/route.ts`, classifies it by the auth helper it calls,
 * and fails if the set of unauthenticated routes differs from PUBLIC_ROUTES
 * below — in either direction.
 *
 * Adding a public route therefore cannot be silent: it turns this suite red, and
 * going green requires editing the allowlist, which shows up in the diff as a
 * deliberate decision someone has to defend in review.
 *
 * ## If this test fails
 *
 * **A route you added appears as unexpectedly public** — that is the intended
 * catch. Add `requireUser` / `requireAdmin`. Only add it to PUBLIC_ROUTES if it
 * genuinely must serve unauthenticated callers, and write down why. "It's easier
 * for testing" is not a reason.
 *
 * **An allowlisted route no longer appears** — you secured or deleted it. Remove
 * the entry. (Deleting `auth/register` is exactly this case.)
 */

import fs from 'fs';
import path from 'path';

const API_DIR = path.join(process.cwd(), 'app', 'api');

/**
 * Routes permitted to serve unauthenticated requests.
 *
 * Every entry needs a reason that survives the question "could an anonymous
 * caller abuse this?" — not merely "does it need to work before login?".
 */
const PUBLIC_ROUTES: Record<string, string> = {
  'auth/[...nextauth]':
    'NextAuth handler. Owns the login/session flow itself, so it cannot sit behind it.',
  'auth/mobile/login':
    'Issues tokens from a username + password. Credentials ARE the authentication. ' +
    'IP rate limited (invariant 5.10) because it is otherwise brute-forceable.',
  'auth/mobile/refresh':
    'Exchanges a refresh token for an access token. The refresh token is the credential, ' +
    'is checked against the DB, and is rotated on use. IP rate limited.',
  'auth/mobile/logout':
    'Revokes a refresh token. Possession of the token is the only authority needed, and the ' +
    'sole effect is deleting it — an anonymous caller can at worst log someone out by ' +
    'guessing a uuid.',
  'auth/mobile/verify':
    'Reachable without credentials, but it does examine the token it is given (via ' +
    'verifyAccessToken) and returns nothing beyond that verdict. Listed here because an ' +
    'anonymous caller gets a 200 — the contract is to REPORT validity, not to reject.',
  health:
    'Liveness probe for the ALB and CI. Returns exactly {"status":"ok"} — no version, no ' +
    'dependency status, no environment detail. Keep it that way.',
};

/**
 * Auth mechanisms that REJECT an unauthenticated caller. Order matters: first
 * match wins.
 *
 * Deliberately narrower than the marker list in `spec-auth-drift.test.ts`, which
 * also counts `verifyAccessToken`. The two tests ask different questions:
 *
 *   here                  — "can an anonymous caller get a useful response?"
 *   spec-auth-drift.test  — "does the handler examine a credential at all?"
 *
 * `/api/auth/mobile/verify` answers yes to both, so it is public *here* (it
 * returns 200 to anyone) while counting as credential-checking *there* (it
 * validates the token before answering). Keeping the lists separate is
 * intentional; collapsing them would hide one of the two properties.
 */
const AUTH_MARKERS: Array<{ kind: string; pattern: RegExp }> = [
  { kind: 'admin', pattern: /requireAdmin\s*\(/ },
  { kind: 'user', pattern: /requireUser\s*\(/ },
  // Shared helper in lib/api-helpers.ts; calls requireUser internally.
  { kind: 'user', pattern: /handleEntityDetailWithBooks\s*\(/ },
  { kind: 'cron', pattern: /isAuthorizedCron\s*\(/ },
];

function findRouteFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...findRouteFiles(full));
    } else if (entry.name === 'route.ts') {
      out.push(full);
    }
  }
  return out;
}

/** `app/api/books/[id]/route.ts` -> `books/[id]` */
function routeName(file: string): string {
  return path.relative(API_DIR, path.dirname(file)).split(path.sep).join('/');
}

function classify(file: string): string {
  const source = fs.readFileSync(file, 'utf8');
  for (const { kind, pattern } of AUTH_MARKERS) {
    if (pattern.test(source)) return kind;
  }
  return 'public';
}

describe('public API surface', () => {
  const routes = findRouteFiles(API_DIR).map((file) => ({
    name: routeName(file),
    kind: classify(file),
  }));

  it('finds the route tree (guards against a silently-passing empty scan)', () => {
    // Without this, a bad API_DIR would yield zero routes and every assertion
    // below would trivially pass.
    expect(routes.length).toBeGreaterThan(40);
  });

  it('exposes exactly the allowlisted routes without authentication', () => {
    const actual = routes
      .filter((r) => r.kind === 'public')
      .map((r) => r.name)
      .sort();
    const allowed = Object.keys(PUBLIC_ROUTES).sort();

    // A single comparison so the diff names both directions at once.
    expect(actual).toEqual(allowed);
  });

  it('has no unexpectedly public route', () => {
    const unexpected = routes
      .filter((r) => r.kind === 'public' && !PUBLIC_ROUTES[r.name])
      .map((r) => r.name);

    expect(unexpected).toEqual([]);
  });

  it('has no stale allowlist entry', () => {
    const present = new Set(routes.map((r) => r.name));
    const stale = Object.keys(PUBLIC_ROUTES).filter((name) => !present.has(name));

    expect(stale).toEqual([]);
  });

  it('documents a reason for every public route', () => {
    // An entry with no justification is how this decays back into a rubber stamp.
    const undocumented = Object.entries(PUBLIC_ROUTES)
      .filter(([, reason]) => reason.trim().length < 40)
      .map(([name]) => name);

    expect(undocumented).toEqual([]);
  });

  it('keeps registration off the public surface', () => {
    // Explicit regression guard for the finding that motivated this file.
    // Accounts are created with `npm run user:create`.
    const registration = routes.filter(
      (r) => r.name === 'auth/register' || r.name.endsWith('/register')
    );

    for (const route of registration) {
      // /api/notifications/register (APNs device tokens) is a different thing
      // and must stay authenticated.
      expect(route.kind).not.toBe('public');
    }
  });

  it('rate limits every public route that accepts credentials', () => {
    // Invariant 5.10. Login and refresh are the brute-forceable ones; a new
    // credential-accepting public route must not skip this.
    const credentialRoutes = ['auth/mobile/login', 'auth/mobile/refresh'];

    for (const name of credentialRoutes) {
      const source = fs.readFileSync(path.join(API_DIR, name, 'route.ts'), 'utf8');
      expect(source).toContain('checkIpRateLimit');
    }
  });
});
