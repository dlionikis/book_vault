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
jest.mock('@aws-sdk/client-budgets', () => {
  return {
    BudgetsClient: jest
      .fn()
      .mockImplementation(() => ({ send: (...args: any[]) => mockSend(...args) })),
    DescribeBudgetsCommand: jest.fn().mockImplementation((input) => input),
  };
});

jest.mock('@/lib/logger', () => ({
  withLogging: (handler: any) => handler,
}));

import { GET } from '@/app/api/admin/budgets/route';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache } from '@/lib/admin-cache';

const mockRequireAdmin = requireAdmin as jest.MockedFunction<typeof requireAdmin>;
const adminUser = { id: 'u1', username: 'admin', isAdmin: true as const };

describe('GET /api/admin/budgets', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env = { ...originalEnv, AWS_ACCOUNT_ID: '123456789012' };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  function makeRequest() {
    return new NextRequest('http://localhost:3000/api/admin/budgets', { method: 'GET' });
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

  it('returns 500 when AWS_ACCOUNT_ID is not set', async () => {
    delete process.env.AWS_ACCOUNT_ID;
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const response = await GET(makeRequest());
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.error).toContain('AWS_ACCOUNT_ID');
  });

  it('returns budget data from AWS', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockSend.mockResolvedValue({
      Budgets: [
        {
          BudgetName: 'Monthly Total',
          BudgetLimit: { Amount: '80' },
          CalculatedSpend: {
            ActualSpend: { Amount: '45.50' },
            ForecastedSpend: { Amount: '72.00' },
          },
        },
        {
          BudgetName: 'S3 Storage',
          BudgetLimit: { Amount: '15' },
          CalculatedSpend: {
            ActualSpend: { Amount: '13.20' },
            ForecastedSpend: { Amount: '16.00' },
          },
        },
      ],
    });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.budgets).toHaveLength(2);

    expect(data.budgets[0].name).toBe('Monthly Total');
    expect(data.budgets[0].limit).toBe(80);
    expect(data.budgets[0].actualSpend).toBe(45.5);
    expect(data.budgets[0].forecastedSpend).toBe(72);
    expect(data.budgets[0].percentUsed).toBe(57);

    expect(data.budgets[1].name).toBe('S3 Storage');
    expect(data.budgets[1].percentUsed).toBe(88);

    expect(setCache).toHaveBeenCalledWith('admin:budgets', data, 3600000);
  });

  it('returns cached data when available', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const cached = { budgets: [{ name: 'cached', limit: 100 }] };
    (getCached as jest.Mock).mockReturnValueOnce(cached);

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(data).toEqual(cached);
    expect(mockSend).not.toHaveBeenCalled();
  });

  it('returns 500 when AWS call fails', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });
    mockSend.mockRejectedValue(new Error('Budgets API error'));

    const response = await GET(makeRequest());
    expect(response.status).toBe(500);
  });

  it('handles zero budget limit without division by zero', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockSend.mockResolvedValue({
      Budgets: [
        {
          BudgetName: 'Zero Budget',
          BudgetLimit: { Amount: '0' },
          CalculatedSpend: {
            ActualSpend: { Amount: '5' },
            ForecastedSpend: { Amount: '10' },
          },
        },
      ],
    });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(data.budgets[0].percentUsed).toBe(0);
  });
});
