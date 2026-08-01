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
    url: process.env.DATABASE_URL ?? '',
  },
});
