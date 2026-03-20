import { NextRequest } from 'next/server';

jest.mock('@/lib/admin-auth', () => ({
  requireAdmin: jest.fn(),
}));

jest.mock('@/lib/admin-cache', () => ({
  getCached: jest.fn().mockReturnValue(null),
  setCache: jest.fn(),
  clearCache: jest.fn(),
  CACHE_24H: 86400000,
}));

const mockSend = jest.fn();
jest.mock('@aws-sdk/client-cost-explorer', () => {
  return {
    CostExplorerClient: jest
      .fn()
      .mockImplementation(() => ({ send: (...args: any[]) => mockSend(...args) })),
    GetCostAndUsageCommand: jest.fn().mockImplementation((input) => input),
  };
});

jest.mock('@/lib/logger', () => ({
  withLogging: (handler: any) => handler,
}));

import { GET } from '@/app/api/admin/costs/route';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache } from '@/lib/admin-cache';

const mockRequireAdmin = requireAdmin as jest.MockedFunction<typeof requireAdmin>;

describe('GET /api/admin/costs', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  function makeRequest(months?: number) {
    const url = months
      ? `http://localhost:3000/api/admin/costs?months=${months}`
      : 'http://localhost:3000/api/admin/costs';
    return new NextRequest(url, { method: 'GET' });
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

  it('returns 403 for non-admin users', async () => {
    const { NextResponse } = await import('next/server');
    mockRequireAdmin.mockResolvedValue({
      user: null,
      error: NextResponse.json({ error: 'Forbidden' }, { status: 403 }),
    });

    const response = await GET(makeRequest());
    expect(response.status).toBe(403);
  });

  it('returns cached data when available', async () => {
    mockRequireAdmin.mockResolvedValue({
      user: { id: 'u1', username: 'admin', isAdmin: true },
      error: null,
    });

    const cachedData = { months: [], currency: 'USD' };
    (getCached as jest.Mock).mockReturnValueOnce(cachedData);

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(data).toEqual(cachedData);
    expect(mockSend).not.toHaveBeenCalled();
  });

  it('fetches and returns cost data from AWS', async () => {
    mockRequireAdmin.mockResolvedValue({
      user: { id: 'u1', username: 'admin', isAdmin: true },
      error: null,
    });

    mockSend.mockResolvedValue({
      ResultsByTime: [
        {
          TimePeriod: { Start: '2026-01-01' },
          Groups: [
            {
              Keys: ['Amazon S3'],
              Metrics: { UnblendedCost: { Amount: '12.50', Unit: 'USD' } },
            },
            {
              Keys: ['Amazon ECS'],
              Metrics: { UnblendedCost: { Amount: '8.25', Unit: 'USD' } },
            },
          ],
        },
        {
          TimePeriod: { Start: '2026-02-01' },
          Groups: [
            {
              Keys: ['Amazon S3'],
              Metrics: { UnblendedCost: { Amount: '14.00', Unit: 'USD' } },
            },
          ],
        },
      ],
    });

    mockSend.mockResolvedValueOnce({
      ResultsByTime: [
        {
          TimePeriod: { Start: '2026-01-01' },
          Groups: [
            {
              Keys: ['Amazon S3'],
              Metrics: { UnblendedCost: { Amount: '12.50', Unit: 'USD' } },
            },
            {
              Keys: ['Amazon ECS'],
              Metrics: { UnblendedCost: { Amount: '8.25', Unit: 'USD' } },
            },
          ],
        },
        {
          TimePeriod: { Start: '2026-02-01' },
          Groups: [
            {
              Keys: ['Amazon S3'],
              Metrics: { UnblendedCost: { Amount: '14.00', Unit: 'USD' } },
            },
          ],
        },
      ],
    });
    mockSend.mockResolvedValueOnce({
      ResultsByTime: [
        {
          TimePeriod: { Start: '2026-01-01' },
          Groups: [
            {
              Keys: ['Credit'],
              Metrics: { UnblendedCost: { Amount: '-1.50', Unit: 'USD' } },
            },
          ],
        },
        {
          TimePeriod: { Start: '2026-02-01' },
          Groups: [],
        },
      ],
    });

    const response = await GET(makeRequest(2));
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.currency).toBe('USD');
    expect(data.months).toHaveLength(2);
    expect(data.months[0].month).toBe('2026-01-01');
    expect(data.months[0].total).toBe(20.75);
    expect(data.months[0].creditRefund).toBe(-1.5);
    expect(data.months[0].services).toHaveLength(2);
    // Services sorted by cost descending
    expect(data.months[0].services[0].service).toBe('Amazon S3');
    expect(data.months[0].services[0].cost).toBe(12.5);

    expect(mockSend).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        Filter: {
          Not: {
            Dimensions: {
              Key: 'RECORD_TYPE',
              Values: ['Credit', 'Refund'],
            },
          },
        },
      })
    );
    expect(mockSend).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        GroupBy: [{ Type: 'DIMENSION', Key: 'RECORD_TYPE' }],
        Filter: {
          Dimensions: {
            Key: 'RECORD_TYPE',
            Values: ['Credit', 'Refund'],
          },
        },
      })
    );

    expect(setCache).toHaveBeenCalledWith('admin:costs:v3:2', data, 86400000);
  });

  it('returns 500 with safe error message when AWS call fails', async () => {
    mockRequireAdmin.mockResolvedValue({
      user: { id: 'u1', username: 'admin', isAdmin: true },
      error: null,
    });
    mockSend.mockRejectedValue(new Error('AWS error with secret credentials'));

    const response = await GET(makeRequest());
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.error).toBe('Failed to fetch cost data');
    expect(JSON.stringify(data)).not.toContain('credentials');
  });

  it('defaults to 6 months when no query param', async () => {
    mockRequireAdmin.mockResolvedValue({
      user: { id: 'u1', username: 'admin', isAdmin: true },
      error: null,
    });
    mockSend.mockResolvedValue({ ResultsByTime: [] });

    await GET(makeRequest());

    expect(getCached).toHaveBeenCalledWith('admin:costs:v3:6');
  });

  it('clamps invalid months param to default', async () => {
    mockRequireAdmin.mockResolvedValue({
      user: { id: 'u1', username: 'admin', isAdmin: true },
      error: null,
    });
    mockSend.mockResolvedValue({ ResultsByTime: [] });

    await GET(makeRequest(999));

    expect(getCached).toHaveBeenCalledWith('admin:costs:v3:6');
  });

  it('handles empty Groups array', async () => {
    mockRequireAdmin.mockResolvedValue({
      user: { id: 'u1', username: 'admin', isAdmin: true },
      error: null,
    });

    mockSend.mockResolvedValueOnce({
      ResultsByTime: [
        {
          TimePeriod: { Start: '2026-01-01' },
          Groups: [],
        },
      ],
    });
    mockSend.mockResolvedValueOnce({ ResultsByTime: [] });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.months[0].total).toBe(0);
    expect(data.months[0].services).toHaveLength(0);
  });
});
