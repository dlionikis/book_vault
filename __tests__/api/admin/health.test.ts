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

  it('flags the poller as error when an OLD restore has never been polled', async () => {
    mockAllHealthy();
    // Requested 10m ago, never polled → past the 6m grace window.
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: new Date(Date.now() - 10 * 60 * 1000), lastCheckedAt: null },
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('error');
  });

  it('stays ok for a just-requested restore not yet polled (grace period)', async () => {
    mockAllHealthy();
    // Requested 1m ago, never polled → within the grace window; not an alarm.
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: new Date(Date.now() - 1 * 60 * 1000), lastCheckedAt: null },
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('ok');
    expect(byName(data, 'Restore poller').detail).toContain('awaiting first poll');
  });

  it('flags the poller as error when the last poll is stale', async () => {
    mockAllHealthy();
    const stale = new Date(Date.now() - 30 * 60 * 1000); // 30m ago
    mockRestoreFindMany.mockResolvedValue([
      { requestedAt: new Date(Date.now() - 60 * 60 * 1000), lastCheckedAt: stale },
    ]);

    const res = await GET(req());
    const data = await res.json();
    expect(byName(data, 'Restore poller').status).toBe('error');
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
