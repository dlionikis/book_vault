import { defineConfig } from 'prisma/config';

// Prisma 7 no longer auto-loads .env, so load it here for local/CI use.
// Wrapped because production (ECS Exec running `prisma migrate deploy` inside
// the container) gets DATABASE_URL from the task definition and ships no
// dotenv — a hard `import 'dotenv/config'` would break migrations there.
try {
  const { config } = await import('dotenv');
  config();
} catch {
  // No dotenv available: rely on the ambient environment.
}

/**
 * The CLI takes a URL string, not the driver options object the app uses, so
 * TLS has to be expressed as an `sslmode` parameter here.
 *
 * `verify-full` is the goal, but it can only verify with Amazon's CA in the
 * trust store — which `NODE_EXTRA_CA_CERTS` (set in the Dockerfile) supplies
 * for the container where `migrate deploy` actually runs. Local and CI
 * databases have no TLS listener, so they are left untouched.
 */
function withRdsSslMode(url: string): string {
  if (!url) return url;
  try {
    const parsed = new URL(url);
    if (!parsed.hostname.endsWith('.rds.amazonaws.com')) return url;
    if (!parsed.searchParams.has('sslmode')) {
      parsed.searchParams.set('sslmode', 'verify-full');
    }
    return parsed.toString();
  } catch {
    return url;
  }
}

/**
 * Prisma CLI configuration (Prisma 7+).
 *
 * In v7 the CLI no longer reads `url` from the datasource block in
 * schema.prisma, and it no longer auto-loads .env — hence the dotenv load
 * above and the `datasource.url` below.
 *
 * Runtime connections do NOT come through here: the app builds its own
 * driver adapter in lib/db.ts. This file is only for CLI commands
 * (migrate, db push, studio, db seed).
 *
 * The URL is read lazily rather than via prisma/config's `env()` helper,
 * which throws at config-load time when the variable is missing. `prisma
 * generate` needs no database, and it runs during the Docker build where
 * DATABASE_URL is deliberately absent — an eager read breaks the image build.
 */
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    // `prisma db seed`. v7 no longer runs this automatically after migrate.
    seed: 'tsx scripts/seed-test-user.ts',
  },
  datasource: {
    url: withRdsSslMode(process.env.DATABASE_URL ?? ''),
  },
});
