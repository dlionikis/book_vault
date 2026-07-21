import { NextRequest } from 'next/server';

jest.mock('@/lib/admin-auth', () => ({ requireAdmin: jest.fn() }));
jest.mock('@/lib/admin-cache', () => ({
  getCached: jest.fn().mockReturnValue(null),
  setCache: jest.fn(),
  CACHE_1M: 60000,
}));
jest.mock('@/lib/logger', () => ({ withLogging: (h: any) => h }));
jest.mock('@/lib/notification-service', () => ({ isPushEnabled: jest.fn(() => true) }));

const mockRestoreCount = jest.fn();
const mockRestoreFindFirst = jest.fn();
const mockRestoreFindMany = jest.fn();
const mockTokenCount = jest.fn();
jest.mock('@/lib/db', () => ({
  prisma: {
    mediaRestoreRequest: {
      count: (...a: any[]) => mockRestoreCount(...a),
      findFirst: (...a: any[]) => mockRestoreFindFirst(...a),
      findMany: (...a: any[]) => mockRestoreFindMany(...a),
    },
    userDeviceToken: { count: (...a: any[]) => mockTokenCount(...a) },
  },
}));

import { GET } from '@/app/api/admin/restores/route';
import { requireAdmin } from '@/lib/admin-auth';

const mockRequireAdmin = requireAdmin as jest.MockedFunction<typeof requireAdmin>;
const adminUser = { id: 'u1', username: 'admin', isAdmin: true as const };
const req = () => new NextRequest('http://localhost:3000/api/admin/restores', { method: 'GET' });

beforeEach(() => {
  jest.clearAllMocks();
  mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });
  // count() is called 5×: inProgress, completed7d, failed7d, stuck, activeTokens, inactiveTokens.
  // Distinguish token counts from restore counts by which model's mock is hit.
  mockRestoreCount
    .mockResolvedValueOnce(1) // inProgress
    .mockResolvedValueOnce(3) // completedLast7d
    .mockResolvedValueOnce(1) // failedLast7d
    .mockResolvedValueOnce(0); // stuck
  mockTokenCount
    .mockResolvedValueOnce(2) // active
    .mockResolvedValueOnce(1); // inactive
  mockRestoreFindFirst.mockResolvedValue({ lastCheckedAt: new Date('2026-07-20T21:55:00Z') });
});

describe('GET /api/admin/restores', () => {
  it('returns 401 unauthenticated', async () => {
    const { NextResponse } = await import('next/server');
    mockRequireAdmin.mockResolvedValue({
      user: null,
      error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }),
    });
    const res = await GET(req());
    expect(res.status).toBe(401);
  });

  it('returns summary, requests with ISO timestamps, and push health', async () => {
    const requestedAt = new Date('2026-07-20T17:19:36Z');
    const lastCheckedAt = new Date('2026-07-20T21:55:00Z');
    mockRestoreFindMany.mockResolvedValue([
      {
        id: 'req-1',
        bookId: 'book-1',
        status: 'in_progress',
        errorMessage: null,
        requestedAt,
        lastCheckedAt,
        completedAt: null,
        book: { title: "A Scion's Duty" },
        requestedBy: { username: 'dlionikis' },
      },
    ]);

    const res = await GET(req());
    const data = await res.json();

    expect(res.status).toBe(200);
    // summary
    expect(data.summary.inProgress).toBe(1);
    expect(data.summary.completedLast7d).toBe(3);
    expect(data.summary.failedLast7d).toBe(1);
    expect(data.summary.stuck).toBe(0);
    expect(data.summary.lastPolledAt).toBe(lastCheckedAt.toISOString());
    // requests + timestamps as ISO strings
    expect(data.requests).toHaveLength(1);
    const r = data.requests[0];
    expect(r.bookTitle).toBe("A Scion's Duty");
    expect(r.requestedByUsername).toBe('dlionikis');
    expect(r.requestedAt).toBe(requestedAt.toISOString());
    expect(r.lastCheckedAt).toBe(lastCheckedAt.toISOString());
    expect(r.completedAt).toBeNull();
    // push health
    expect(data.push).toEqual({ configured: true, activeTokens: 2, inactiveTokens: 1 });
  });

  it('handles a system-initiated request with no user and empty list', async () => {
    mockRestoreFindFirst.mockResolvedValue(null); // never polled
    mockRestoreFindMany.mockResolvedValue([
      {
        id: 'req-2',
        bookId: 'book-2',
        status: 'completed',
        errorMessage: null,
        requestedAt: new Date('2026-07-19T00:00:00Z'),
        lastCheckedAt: null,
        completedAt: new Date('2026-07-19T04:00:00Z'),
        book: { title: 'Brief Cases' },
        requestedBy: null,
      },
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(data.summary.lastPolledAt).toBeNull();
    expect(data.requests[0].requestedByUsername).toBeNull();
    expect(data.requests[0].completedAt).toBe(new Date('2026-07-19T04:00:00Z').toISOString());
  });
});
