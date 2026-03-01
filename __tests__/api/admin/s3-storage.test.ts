import { NextRequest } from 'next/server';

jest.mock('@/lib/admin-auth', () => ({
  requireAdmin: jest.fn(),
}));

jest.mock('@/lib/admin-cache', () => ({
  getCached: jest.fn().mockReturnValue(null),
  setCache: jest.fn(),
  CACHE_1H: 3600000,
}));

const mockSend = jest.fn();
jest.mock('@aws-sdk/client-cloudwatch', () => {
  return {
    CloudWatchClient: jest
      .fn()
      .mockImplementation(() => ({ send: (...args: any[]) => mockSend(...args) })),
    GetMetricDataCommand: jest.fn().mockImplementation((input) => input),
  };
});

jest.mock('@/lib/logger', () => ({
  withLogging: (handler: any) => handler,
}));

import { GET } from '@/app/api/admin/s3-storage/route';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache } from '@/lib/admin-cache';

const mockRequireAdmin = requireAdmin as jest.MockedFunction<typeof requireAdmin>;
const adminUser = { id: 'u1', username: 'admin', isAdmin: true as const };

describe('GET /api/admin/s3-storage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  function makeRequest() {
    return new NextRequest('http://localhost:3000/api/admin/s3-storage', { method: 'GET' });
  }

  it('returns 401 for unauthenticated requests', async () => {
    const { NextResponse } = await import('next/server');
    mockRequireAdmin.mockResolvedValue({
      user: null,
      error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }),
    });

    const response = await GET(makeRequest());
    expect(response.status).toBe(401);
  });

  it('returns S3 storage data from CloudWatch', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const ts1 = new Date('2026-02-28T00:00:00Z');
    const ts2 = new Date('2026-03-01T00:00:00Z');

    mockSend.mockResolvedValue({
      MetricDataResults: [
        { Id: 'standard', Values: [10737418240, 11811160064], Timestamps: [ts1, ts2] },
        { Id: 'it_fa', Values: [5368709120, 5368709120], Timestamps: [ts1, ts2] },
        { Id: 'it_ia', Values: [2147483648, 2147483648], Timestamps: [ts1, ts2] },
        { Id: 'it_aa', Values: [1073741824, 1073741824], Timestamps: [ts1, ts2] },
        { Id: 'objects', Values: [1500, 1520], Timestamps: [ts1, ts2] },
      ],
    });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(response.status).toBe(200);

    expect(data.current.standardGB).toBe(10);
    expect(data.current.itFrequentGB).toBe(5);
    expect(data.current.itInfrequentGB).toBe(2);
    expect(data.current.itArchiveGB).toBe(1);
    expect(data.current.totalSizeGB).toBe(18);
    expect(data.current.objectCount).toBe(1500);

    expect(data.trends.totalSize.timestamps).toHaveLength(2);
    expect(data.trends.totalSize.values).toHaveLength(2);
    expect(data.trends.objectCount.timestamps).toHaveLength(2);

    expect(setCache).toHaveBeenCalledWith('admin:s3-storage', data, 3600000);
  });

  it('returns cached data when available', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const cached = { current: { totalSizeGB: 10 }, trends: {} };
    (getCached as jest.Mock).mockReturnValueOnce(cached);

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(data).toEqual(cached);
    expect(mockSend).not.toHaveBeenCalled();
  });

  it('handles empty metrics gracefully', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockSend.mockResolvedValue({ MetricDataResults: [] });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.current.totalSizeGB).toBe(0);
    expect(data.current.objectCount).toBe(0);
  });

  it('returns 500 when CloudWatch call fails', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });
    mockSend.mockRejectedValue(new Error('CloudWatch error'));

    const response = await GET(makeRequest());
    expect(response.status).toBe(500);
  });
});
