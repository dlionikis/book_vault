/**
 * Centralized Prisma Client
 *
 * This module provides a singleton PrismaClient instance to prevent
 * connection pool exhaustion in serverless/production environments.
 *
 * USAGE:
 *   import { prisma } from '@/lib/db';
 *
 * DO NOT create new PrismaClient() instances directly in your code.
 */

import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@/lib/generated/prisma/client';
import { getPostgresSslConfig } from '@/lib/db-ssl';

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

// Prisma 7 requires a driver adapter — the client no longer opens its own
// connection, so the URL is passed here rather than read from schema.prisma.
// The adapter owns the pg connection pool, which is why the singleton below
// matters more than ever: a new client per request would leak pools.
function createPrismaClient(): PrismaClient {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error('DATABASE_URL is not set — cannot initialize the Prisma client.');
  }

  // RDS requires TLS; pg attempts none by default. See lib/db-ssl.ts.
  const ssl = getPostgresSslConfig(connectionString);

  return new PrismaClient({
    adapter: new PrismaPg({ connectionString, ...(ssl ? { ssl } : {}) }),
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });
}

/**
 * The client is constructed on first property access, not at import time.
 *
 * `next build` imports these modules to collect page data with no DATABASE_URL
 * set (the Docker build has no database), so constructing eagerly would fail
 * the image build. Deferring keeps the "missing DATABASE_URL" error where it
 * belongs — on the first actual query — while callers still see a plain
 * `prisma.<model>` API.
 *
 * The instance is cached on globalThis in every environment (pre-v7 this was
 * dev-only). The pg pool now lives in the adapter, so re-creating the client —
 * e.g. across hot reloads or module-graph duplicates — would leak connections.
 */
function getClient(): PrismaClient {
  if (!globalForPrisma.prisma) {
    globalForPrisma.prisma = createPrismaClient();
  }
  return globalForPrisma.prisma;
}

export const prisma = new Proxy({} as PrismaClient, {
  get(_target, prop, receiver) {
    return Reflect.get(getClient(), prop, receiver);
  },
  has(_target, prop) {
    return Reflect.has(getClient(), prop);
  },
  set(_target, prop, value) {
    return Reflect.set(getClient(), prop, value);
  },
});

/**
 * Best Practices:
 *
 * 1. Import the singleton:
 *    import { prisma } from '@/lib/db';
 *
 * 2. Use in API routes:
 *    export async function GET() {
 *      const books = await prisma.book.findMany();
 *      return NextResponse.json(books);
 *    }
 *
 * 3. Use in Server Components:
 *    async function MyPage() {
 *      const books = await prisma.book.findMany();
 *      return <div>...</div>;
 *    }
 *
 * 4. No manual disconnect needed:
 *    Next.js handles cleanup automatically. Only disconnect
 *    in standalone scripts (import scripts, CLI tools, etc.)
 */
