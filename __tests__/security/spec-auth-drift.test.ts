/**
 * The OpenAPI spec must agree with the code about which routes are public.
 *
 * ## Why this test exists
 *
 * `GET /api/images/{path}` was declared `security: []` — public — in
 * openapi.yaml, with the description "Public endpoint (no authentication
 * required for better caching)". The code had required `requireUser` since
 * PR #75, because serving that route unauthenticated let anyone stream any
 * object in the media store, audio included. It was a **P0** finding; invariant
 * 5.2 exists solely because of it.
 *
 * So for months the machine-readable contract advertised the exact
 * vulnerability that had already been fixed, with the vulnerability's own
 * rationale attached. The contract tests never noticed: they assert response
 * shapes and status codes, not whether a route declared public actually is.
 *
 * That matters beyond tidiness — openapi.yaml generates the TypeScript and Swift
 * clients and is the document a reviewer reads to answer "what is exposed?". A
 * spec that lies about auth is worse than no spec.
 *
 * ## What it does
 *
 * Cross-checks the spec's `security` declarations against the auth helper each
 * route handler actually calls, and fails on any disagreement in either
 * direction:
 *
 *   - spec says public, code requires auth  → stale/misleading spec (this bug)
 *   - spec says authenticated, code is open → a real hole
 *
 * See also `public-surface.test.ts`, which guards the code side alone.
 */

import fs from 'fs';
import path from 'path';
import yaml from 'yaml';

const REPO_ROOT = process.cwd();
const API_DIR = path.join(REPO_ROOT, 'app', 'api');
const SPEC_PATH = path.join(REPO_ROOT, 'docs', 'api', 'openapi.yaml');

/**
 * Spec paths that are legitimately public. Must stay in step with
 * PUBLIC_ROUTES in public-surface.test.ts.
 */
const SPEC_PUBLIC_PATHS = new Set([
  '/api/auth/mobile/login',
  '/api/auth/mobile/refresh',
  // Its credential is the refresh token in the body, not a bearer header. The
  // spec previously declared `bearerAuth`, which the handler never reads.
  '/api/auth/mobile/logout',
  // Previously declared nothing, so it inherited the global sessionAuth — wrong
  // for a route the ALB health check calls without credentials.
  '/api/health',
]);

// NOTE: /api/auth/mobile/verify is deliberately absent. It declares bearerAuth
// in the spec and does check the token (via verifyAccessToken), so it is not
// public — even though `public-surface.test.ts` lists it, which classifies by
// "does an unauthenticated caller get a useful response" rather than by whether
// a credential is examined.

const AUTH_MARKERS: RegExp[] = [
  /requireAdmin\s*\(/,
  /requireUser\s*\(/,
  /handleEntityDetailWithBooks\s*\(/,
  /isAuthorizedCron\s*\(/,
  // /api/auth/mobile/verify inspects the token itself rather than delegating to
  // requireUser, because its contract is to *report* validity — 200 with
  // `{valid: false}` — not to reject the caller with a 401.
  /verifyAccessToken\s*\(/,
];

/** `/api/books/{id}` -> `app/api/books/[id]/route.ts` */
function handlerFor(specPath: string): string | null {
  const rel = specPath
    .replace(/^\/api\//, '')
    .split('/')
    .map((seg) => seg.replace(/^\{(.+)\}$/, '[$1]'))
    .join(path.sep);

  const direct = path.join(API_DIR, rel, 'route.ts');
  if (fs.existsSync(direct)) return direct;

  // Catch-all routes: the spec writes {path}, the filesystem uses [...path].
  const parts = rel.split(path.sep);
  const last = parts[parts.length - 1];
  if (last?.startsWith('[') && last.endsWith(']')) {
    const spread = [...parts.slice(0, -1), `[...${last.slice(1, -1)}]`].join(path.sep);
    const candidate = path.join(API_DIR, spread, 'route.ts');
    if (fs.existsSync(candidate)) return candidate;
  }

  return null;
}

function codeRequiresAuth(handlerPath: string): boolean {
  const source = fs.readFileSync(handlerPath, 'utf8');
  return AUTH_MARKERS.some((pattern) => pattern.test(source));
}

const spec = yaml.parse(fs.readFileSync(SPEC_PATH, 'utf8'));

/** Operations that override global security with an empty array. */
const declaredPublic: string[] = [];
/** Operations that inherit or set a security requirement. */
const declaredSecured: string[] = [];

for (const [specPath, methods] of Object.entries(spec.paths ?? {})) {
  for (const [method, operation] of Object.entries(methods as Record<string, unknown>)) {
    if (!['get', 'post', 'put', 'patch', 'delete'].includes(method)) continue;
    const security = (operation as { security?: unknown[] }).security;
    // `security: []` means "no auth"; absent means "inherit the global default".
    if (Array.isArray(security) && security.length === 0) {
      declaredPublic.push(specPath);
    } else {
      declaredSecured.push(specPath);
    }
  }
}

describe('spec ↔ code auth agreement', () => {
  it('parses the spec and finds operations', () => {
    // Guards against a silently-passing run if the spec moves or fails to parse.
    expect(declaredPublic.length + declaredSecured.length).toBeGreaterThan(40);
  });

  it('declares public only the routes that really are public', () => {
    const unexpected = [...new Set(declaredPublic)].filter((p) => !SPEC_PUBLIC_PATHS.has(p)).sort();

    expect(unexpected).toEqual([]);
  });

  it('does not declare a route public while the code requires auth', () => {
    // The images bug: spec advertised open access to a route hardened months
    // earlier, keeping the original vulnerable rationale in its description.
    const lying: string[] = [];

    for (const specPath of new Set(declaredPublic)) {
      const handler = handlerFor(specPath);
      if (handler && codeRequiresAuth(handler)) {
        lying.push(specPath);
      }
    }

    expect(lying).toEqual([]);
  });

  it('does not declare a route authenticated while the code leaves it open', () => {
    // The dangerous direction: the spec claims protection the code lacks.
    const unprotected: string[] = [];

    for (const specPath of new Set(declaredSecured)) {
      const handler = handlerFor(specPath);
      if (handler && !codeRequiresAuth(handler)) {
        unprotected.push(specPath);
      }
    }

    expect(unprotected).toEqual([]);
  });

  it('never advertises a shared cache for an authenticated media route', () => {
    // `Cache-Control: public` on a gated route invites a CDN or proxy to hand
    // authenticated bytes to strangers. The spec used to example exactly that
    // for /api/images (invariant 5.2).
    const imageOp = spec.paths?.['/api/images/{path}']?.get;
    expect(imageOp).toBeDefined();

    const example = imageOp.responses?.['200']?.headers?.['Cache-Control']?.schema?.example;
    expect(example).toContain('private');
    expect(example).not.toContain('public');
  });
});
