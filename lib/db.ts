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

import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });

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
