import { NextRequest } from 'next/server';

jest.mock('@/lib/admin-auth', () => ({ requireAdmin: jest.fn() }));
jest.mock('@/lib/admin-cache', () => ({
  getCached: jest.fn().mockReturnValue(null),
  setCache: jest.fn(),
  CACHE_1M: 60000,
}));
jest.mock('@/lib/logger', () => ({ withLogging: (h: any) => h }));

// Prisma
const mockQueryRaw = jest.fn();
const mockRestoreFindMany = jest.fn();
const mockRestoreCount = jest.fn();
const mockBookGroupBy = jest.fn();
const mockTokenCount = jest.fn();
jest.mock('@/lib/db', () => ({
  prisma: {
    $queryRaw: (...a: any[]) => mockQueryRaw(...a),
    mediaRestoreRequest: {
      findMany: (...a: any[]) => mockRestoreFindMany(...a),
      count: (...a: any[]) => mockRestoreCount(...a),
    },
    book: { groupBy: (...a: any[]) => mockBookGroupBy(...a) },
    userDeviceToken: { count: (...a: any[]) => mockTokenCount(...a) },
  },
}));

// S3
const mockS3Send = jest.fn();
jest.mock('@/lib/s3', () => ({
  getS3Client: () => ({ send: (...a: any[]) => mockS3Send(...a) }),
  getS3Bucket: () => 'book-vault-media',
  isS3Enabled: jest.fn(() => true),
}));
jest.mock('@aws-sdk/client-s3', () => ({
  HeadBucketCommand: jest.fn().mockImplementation((i) => i),
}));

// Push
jest.mock('@/lib/notification-service', () => ({ isPushEnabled: jest.fn(() => true) }));

// EventBridge
const mockEbSend = jest.fn();
jest.mock('@aws-sdk/client-eventbridge', () => ({
  EventBridgeClient: jest
    .fn()
    .mockImplementation(() => ({ send: (...a: any[]) => mockEbSend(...a) })),
  DescribeConnectionCommand: jest.fn().mockImplementation((i) => ({ __t: 'conn', ...i })),
  DescribeApiDestinationCommand: jest.fn().mockImplementation((i) => ({ __t: 'dest', ...i })),
  DescribeRuleCommand: jest.fn().mockImplementation((i) => ({ __t: 'rule', ...i })),
}));

jest.mock('@/lib/restore', () => ({
  AVAILABILITY: { AVAILABLE: 'AVAILABLE', ARCHIVED: 'ARCHIVED', RESTORING: 'RESTORING' },
}));

import { GET } from '@/app/api/admin/health/route';
import { requireAdmin } from '@/lib/admin-auth';

const mockRequireAdmin = requireAdmin as jest.MockedFunction<typeof requireAdmin>;
const adminUser = { id: 'u1', username: 'admin', isAdmin: true as const };
const req = () => new NextRequest('http://localhost:3000/api/admin/health', { method: 'GET' });

// Healthy defaults for every dependency.
function mockAllHealthy() {
  mockQueryRaw.mockResolvedValue([{ '1': 1 }]);
  mockS3Send.mockResolvedValue({});
  mockTokenCount.mockResolvedValue(2);
  mockRestoreFindMany.mockResolvedValue([]); // no active restores
  mockRestoreCount.mockResolvedValue(0); // no stuck
  mockBookGroupBy.mockResolvedValue([
    { audioAvailability: 'AVAILABLE', _count: { _all: 69 } },
    { audioAvailability: 'ARCHIVED', _count: { _all: 695 } },
  ]);
  mockEbSend.mockImplementation((cmd: any) => {
    if (cmd.__t === 'conn') return Promise.resolve({ ConnectionState: 'AUTHORIZED' });
    if (cmd.__t === 'dest') return Promise.resolve({ ApiDestinationState: 'ACTIVE' });
    if (cmd.__t === 'rule') return Promise.resolve({ State: 'ENABLED' });
    return Promise.resolve({});
  });
}

const byName = (data: any, name: string) => data.checks.find((c: any) => c.name === name);

beforeEach(() => {
  jest.clearAllMocks();
  mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });
});

describe('GET /api/admin/health', () => {
  it('returns 401 unauthenticated', async () => {
    const { NextResponse } = await import('next/server');
    mockRequireAdmin.mockResolvedValue({
      user: null,
      error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }),
    });
    const res = await GET(req());
    expect(res.status).toBe(401);
  });

  it('reports all ok when every dependency is healthy', async () => {
    mockAllHealthy();
    const res = await GET(req());
    const data = await res.json();

    expect(res.status).toBe(200);
    expect(byName(data, 'Database').status).toBe('ok');
    expect(byName(data, 'S3').status).toBe('ok');
    expect(byName(data, 'EventBridge cron').status).toBe('ok');
    expect(data.checks.every((c: any) => c.status !== 'error')).toBe(true);
  });

  it('flags EventBridge as error when the connection is DEAUTHORIZED', async () => {
    mockAllHealthy();
    mockEbSend.mockImplementation((cmd: any) => {
      if (cmd.__t === 'conn') return Promise.resolve({ ConnectionState: 'DEAUTHORIZED' });
      return Promise.resolve({});
    });

    const res = await GET(req());
    const data = await res.json();
    const eb = byName(data, 'EventBridge cron');
    expect(eb.status).toBe('error');
    expect(eb.detail).toContain('DEAUTHORIZED');
  });

  const min = (n: number) => new Date(Date.now() - n * 60 * 1000);

  it('errors when the latest ripe (>5m old) restore has never been polled', async () => {
    mockAllHealthy();
    // findMany is ordered requestedAt desc; newest first. Newest is 10m old + unpolled.
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: min(10), lastCheckedAt: null },
      { requestedAt: min(40), lastCheckedAt: null },
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('error');
    expect(byName(data, 'Restore poller').detail).toContain('never been polled');
  });

  it('stays ok for just-requested restores not yet ripe (all <5m old)', async () => {
    mockAllHealthy();
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: min(1), lastCheckedAt: null },
      { requestedAt: min(2), lastCheckedAt: null },
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('ok');
    expect(byName(data, 'Restore poller').detail).toContain('awaiting first poll');
  });

  it('stays ok when the latest ripe restore has been polled recently', async () => {
    mockAllHealthy();
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: min(1), lastCheckedAt: null }, // fresh, not ripe — ignored
      { requestedAt: min(20), lastCheckedAt: min(2) }, // ripe + recently polled
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('ok');
    expect(byName(data, 'Restore poller').detail).toContain('Last poll');
  });

  it('errors (staleness floor) when the poller died after polling and new restores pile up', async () => {
    mockAllHealthy();
    // Newest ripe restore WAS polled long ago; a brand-new one arrived since.
    // Your primary rule alone would pass (newest-ripe has non-null lastCheckedAt),
    // but the freshest poll across all is 40m stale → still caught.
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: min(2), lastCheckedAt: null }, // new, not ripe
      { requestedAt: min(90), lastCheckedAt: min(40) }, // ripe, but last poll 40m ago
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('error');
    expect(byName(data, 'Restore poller').detail).toContain('Last poll');
  });

  it('degrades a failing check to an error card without 500-ing the panel', async () => {
    mockAllHealthy();
    mockEbSend.mockRejectedValue(new Error('AccessDenied: events:DescribeConnection'));

    const res = await GET(req());
    const data = await res.json();
    expect(res.status).toBe(200); // panel still renders
    const eb = byName(data, 'EventBridge cron');
    expect(eb.status).toBe('error');
    expect(eb.detail).toContain('Check failed');
  });

  it('warns (not errors) when push is not configured', async () => {
    mockAllHealthy();
    const { isPushEnabled } = await import('@/lib/notification-service');
    (isPushEnabled as jest.Mock).mockReturnValue(false);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Push (APNs/SNS)').status).toBe('warn');
  });
});
