/**
 * Real-database integration tests for the routes that use `prisma.$transaction`.
 *
 * The unit tests for these routes mock `@/lib/db`, so they never exercise the
 * real transaction behavior — a mocked `$transaction` can't prove the writes
 * commit atomically, that compound-unique upserts resolve, or that ordering
 * persists. These tests run the handlers against a real Postgres (the same DB
 * the integration suite uses) so a Prisma major bump that changed
 * `$transaction` semantics would actually fail here.
 *
 * Covers all three `$transaction` forms in the app:
 *   1. interactive callback  — POST /api/progress/batch
 *   2. array (delete+create) — POST /api/auth/mobile/refresh
 *   3. array (updateMany[])  — PUT  /api/library/lists/[id]/reorder
 *
 * Gated behind JEST_INTEGRATION=true (run via `npm run test:integration`).
 */

import { NextRequest } from 'next/server';
import { prisma } from '@/lib/db';
import * as apiAuth from '@/lib/api-auth';

import { POST as batchProgress } from '@/app/api/progress/batch/route';
import { POST as refreshToken } from '@/app/api/auth/mobile/refresh/route';
import { PUT as reorderList } from '@/app/api/library/lists/[id]/reorder/route';

// requireUser wraps getServerSession + mobile-token auth; stub it directly so
// these tests focus on the transaction behavior, not the auth plumbing (which
// has its own coverage). The refresh route does NOT use requireUser — it
// validates the refresh token itself — so it exercises the real auth path.
jest.mock('@/lib/api-auth');
const mockRequireUser = apiAuth.requireUser as jest.MockedFunction<typeof apiAuth.requireUser>;

// Every fixture is namespaced with this prefix so setup/teardown can wipe them
// with a single `startsWith`, and each test mints its own unique username/ASIN
// (via `uid()`) so tests never collide on the `username`/`asin` unique
// constraints — the download integration suite follows the same convention.
const PREFIX = 'txtest-';
let counter = 0;
const uid = () => `${PREFIX}${Date.now().toString(36)}-${counter++}`;
// ASINs have a fixed width; keep them unique but bounded.
const asin = () => `BTX${(counter++).toString().padStart(7, '0')}`;

async function cleanup() {
  // Books/users cascade to progress, refresh tokens, lists, and list books.
  await prisma.user.deleteMany({ where: { username: { startsWith: PREFIX } } });
  await prisma.book.deleteMany({ where: { asin: { startsWith: 'BTX' } } });
}

describe('$transaction routes (real DB)', () => {
  beforeAll(cleanup);
  afterAll(cleanup);

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('POST /api/progress/batch — interactive $transaction with conflict resolution', () => {
    it('commits new progress rows and reports them as updated', async () => {
      const user = await prisma.user.create({
        data: { username: uid(), passwordHash: 'hash' },
      });
      const bookA = await prisma.book.create({
        data: { asin: asin(), title: 'Batch Book A' },
      });
      const bookB = await prisma.book.create({
        data: { asin: asin(), title: 'Batch Book B' },
      });
      mockRequireUser.mockResolvedValue({ user: { id: user.id, username: user.username } });

      const request = new NextRequest('http://localhost:3000/api/progress/batch', {
        method: 'POST',
        body: JSON.stringify({
          updates: [
            { bookId: bookA.id, positionSeconds: 120, timestamp: '2026-01-01T00:00:00.000Z' },
            { bookId: bookB.id, positionSeconds: 300, timestamp: '2026-01-01T00:00:00.000Z' },
          ],
        }),
      });

      const response = await batchProgress(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.updated).toBe(2);
      expect(data.conflicts).toBe(0);

      // The transaction actually committed both upserts.
      const rows = await prisma.userProgress.findMany({
        where: { userId: user.id },
        orderBy: { positionSeconds: 'asc' },
      });
      expect(rows).toHaveLength(2);
      expect(rows[0].positionSeconds).toBe(120);
      expect(rows[1].positionSeconds).toBe(300);
    });

    it('skips a stale update (older timestamp) as a conflict, keeping the newer position', async () => {
      const user = await prisma.user.create({
        data: { username: uid(), passwordHash: 'hash' },
      });
      const book = await prisma.book.create({
        data: { asin: asin(), title: 'Batch Conflict Book' },
      });
      mockRequireUser.mockResolvedValue({ user: { id: user.id, username: user.username } });

      // Seed existing progress at a NEWER lastPlayed than the incoming update.
      await prisma.userProgress.create({
        data: {
          userId: user.id,
          bookId: book.id,
          positionSeconds: 500,
          lastPlayed: new Date('2026-02-01T00:00:00.000Z'),
        },
      });

      const request = new NextRequest('http://localhost:3000/api/progress/batch', {
        method: 'POST',
        body: JSON.stringify({
          updates: [
            // Older than the stored lastPlayed → should be treated as a conflict.
            { bookId: book.id, positionSeconds: 10, timestamp: '2026-01-01T00:00:00.000Z' },
          ],
        }),
      });

      const response = await batchProgress(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.updated).toBe(0);
      expect(data.conflicts).toBe(1);

      // The stale write must NOT have overwritten the newer position.
      const row = await prisma.userProgress.findUnique({
        where: { userId_bookId: { userId: user.id, bookId: book.id } },
      });
      expect(row?.positionSeconds).toBe(500);
    });
  });

  describe('POST /api/auth/mobile/refresh — array $transaction (delete old + create new)', () => {
    it('atomically rotates the refresh token: old gone, exactly one new token', async () => {
      const user = await prisma.user.create({
        data: { username: uid(), passwordHash: 'hash' },
      });
      const oldToken = `${PREFIX}old-refresh-token-000000000001`;
      await prisma.refreshToken.create({
        data: {
          userId: user.id,
          token: oldToken,
          expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000), // valid
        },
      });

      const request = new NextRequest('http://localhost:3000/api/auth/mobile/refresh', {
        method: 'POST',
        body: JSON.stringify({ refreshToken: oldToken }),
      });

      const response = await refreshToken(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.refreshToken).toBeDefined();
      expect(data.refreshToken).not.toBe(oldToken);
      expect(data.accessToken).toBeDefined();

      // The old token was deleted and exactly one (new) token remains — proving
      // the delete+create ran as one committed transaction.
      const remaining = await prisma.refreshToken.findMany({ where: { userId: user.id } });
      expect(remaining).toHaveLength(1);
      expect(remaining[0].token).toBe(data.refreshToken);

      const old = await prisma.refreshToken.findUnique({ where: { token: oldToken } });
      expect(old).toBeNull();
    });
  });

  describe('PUT /api/library/lists/[id]/reorder — array $transaction (updateMany[])', () => {
    it('persists the new book ordering across all rows', async () => {
      const user = await prisma.user.create({
        data: { username: uid(), passwordHash: 'hash' },
      });
      const b1 = await prisma.book.create({
        data: { asin: asin(), title: 'Reorder 1' },
      });
      const b2 = await prisma.book.create({
        data: { asin: asin(), title: 'Reorder 2' },
      });
      const b3 = await prisma.book.create({
        data: { asin: asin(), title: 'Reorder 3' },
      });
      const list = await prisma.userList.create({
        data: { userId: user.id, name: 'Reorder List' },
      });
      // Initial order: b1=0, b2=1, b3=2
      await prisma.userListBook.create({ data: { listId: list.id, bookId: b1.id, position: 0 } });
      await prisma.userListBook.create({ data: { listId: list.id, bookId: b2.id, position: 1 } });
      await prisma.userListBook.create({ data: { listId: list.id, bookId: b3.id, position: 2 } });

      mockRequireUser.mockResolvedValue({ user: { id: user.id, username: user.username } });

      // Reverse the order.
      const request = new NextRequest(
        `http://localhost:3000/api/library/lists/${list.id}/reorder`,
        {
          method: 'PUT',
          body: JSON.stringify({ bookIds: [b3.id, b2.id, b1.id] }),
        }
      );

      const response = await reorderList(request, { params: Promise.resolve({ id: list.id }) });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.updated).toBe(3);

      // Every position was rewritten by the transaction.
      const rows = await prisma.userListBook.findMany({
        where: { listId: list.id },
        select: { bookId: true, position: true },
      });
      const positionByBook = Object.fromEntries(rows.map((r) => [r.bookId, r.position]));
      expect(positionByBook[b3.id]).toBe(0);
      expect(positionByBook[b2.id]).toBe(1);
      expect(positionByBook[b1.id]).toBe(2);
    });
  });
});
