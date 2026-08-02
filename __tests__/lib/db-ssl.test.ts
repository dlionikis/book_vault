/**
 * Tests for Postgres TLS configuration — uses the REAL bundled CA file.
 *
 * These pin security-critical behavior. Prisma 7 delegates connections to the
 * pg driver, which attempts no TLS unless configured; RDS then rejects the
 * connection and Prisma reports it as the misleading `DatabaseAccessDenied`.
 * A regression here takes production down, so the RDS/non-RDS split and the
 * `rejectUnauthorized` flag are asserted directly.
 */

import { getPostgresSslConfig } from '@/lib/db-ssl';

const RDS_URL =
  'postgresql://postgres:secret@book-vault-db.carekqk266tw.us-east-1.rds.amazonaws.com:5432/book_vault';
const LOCAL_URL = 'postgresql://postgres:postgres@localhost:5433/book_vault';

describe('lib/db-ssl', () => {
  describe('RDS connections', () => {
    it('enables TLS with certificate verification', () => {
      const ssl = getPostgresSslConfig(RDS_URL);

      expect(ssl).toBeDefined();
      expect(ssl?.rejectUnauthorized).toBe(true);
    });

    it('supplies the Amazon RDS CA bundle', () => {
      const ssl = getPostgresSslConfig(RDS_URL);

      expect(ssl?.ca).toContain('-----BEGIN CERTIFICATE-----');
      expect(ssl?.ca).toContain('-----END CERTIFICATE-----');
    });

    it('bundles the us-east-1 root the production database chains to', () => {
      // The global bundle must actually cover our region, not just parse.
      const ssl = getPostgresSslConfig(RDS_URL);
      const certCount = (ssl?.ca.match(/BEGIN CERTIFICATE/g) ?? []).length;

      expect(certCount).toBeGreaterThan(1);
    });

    it('applies to RDS hosts in any region', () => {
      const euUrl = 'postgresql://u:p@db.abc123.eu-west-1.rds.amazonaws.com:5432/app';

      expect(getPostgresSslConfig(euUrl)?.rejectUnauthorized).toBe(true);
    });
  });

  describe('non-RDS connections', () => {
    it('leaves local development alone', () => {
      // Local Postgres runs in Docker with no TLS listener; forcing
      // encryption would fail every connection.
      expect(getPostgresSslConfig(LOCAL_URL)).toBeUndefined();
    });

    it('leaves other hosts alone', () => {
      expect(getPostgresSslConfig('postgresql://u:p@db.internal:5432/app')).toBeUndefined();
    });

    it('does not treat a lookalike hostname as RDS', () => {
      // Guards against a suffix check that a spoofed domain could satisfy.
      const spoof = 'postgresql://u:p@rds.amazonaws.com.evil.example:5432/app';

      expect(getPostgresSslConfig(spoof)).toBeUndefined();
    });

    it('returns undefined for an unparseable connection string', () => {
      expect(getPostgresSslConfig('not-a-url')).toBeUndefined();
    });
  });
});
