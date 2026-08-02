/**
 * TLS configuration for Postgres connections.
 *
 * Prisma 7 hands connection handling to the `pg` driver, which — unlike the
 * v6 query engine — attempts no TLS unless it is configured here. RDS rejects
 * unencrypted connections, and Prisma surfaces that rejection as the very
 * misleading `DatabaseAccessDenied`.
 *
 * `sslmode=require` is NOT a fix: as of pg 8.22 it performs full certificate
 * verification against the system trust store, and RDS serves a certificate
 * signed by Amazon's own CA. Verification therefore needs that CA explicitly,
 * which is what `certs/rds-global-bundle.pem` provides.
 */

import fs from 'fs';
import path from 'path';

/** Bundled copy of Amazon's public RDS trust anchors (all regions). */
const RDS_CA_PATH = path.join(process.cwd(), 'certs', 'rds-global-bundle.pem');

/** Hosts served by RDS — the only ones that need the Amazon CA. */
function isRdsHost(connectionString: string): boolean {
  try {
    return new URL(connectionString).hostname.endsWith('.rds.amazonaws.com');
  } catch {
    return false;
  }
}

/**
 * TLS options for a given connection string, or `undefined` to leave the
 * driver's defaults alone.
 *
 * Only RDS connections get TLS forced on. Local development and CI run plain
 * Postgres in Docker with no TLS listener at all, where demanding encryption
 * would fail every connection.
 */
export function getPostgresSslConfig(
  connectionString: string
): { ca: string; rejectUnauthorized: true } | undefined {
  if (!isRdsHost(connectionString)) {
    return undefined;
  }

  // Read eagerly: a missing CA in an RDS environment means every query would
  // fail on an unverifiable certificate, so fail loudly and immediately
  // rather than at the first request.
  const ca = fs.readFileSync(RDS_CA_PATH, 'utf8');

  return { ca, rejectUnauthorized: true };
}
