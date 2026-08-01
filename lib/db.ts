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

  return new PrismaClient({
    adapter: new PrismaPg({ connectionString }),
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });
}

export const prisma = globalForPrisma.prisma ?? createPrismaClient();

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}

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
