import { NextRequest } from 'next/server';

jest.mock('@/lib/admin-auth', () => ({
  requireAdmin: jest.fn(),
}));

jest.mock('@/lib/admin-cache', () => ({
  getCached: jest.fn().mockReturnValue(null),
  setCache: jest.fn(),
  CACHE_5M: 300000,
}));

const mockEcsSend = jest.fn();
const mockCwSend = jest.fn();

jest.mock('@aws-sdk/client-ecs', () => {
  return {
    ECSClient: jest
      .fn()
      .mockImplementation(() => ({ send: (...args: any[]) => mockEcsSend(...args) })),
    DescribeServicesCommand: jest.fn().mockImplementation((input) => input),
    ListTasksCommand: jest.fn().mockImplementation((input) => input),
    DescribeTasksCommand: jest.fn().mockImplementation((input) => input),
  };
});

jest.mock('@aws-sdk/client-cloudwatch', () => {
  return {
    CloudWatchClient: jest
      .fn()
      .mockImplementation(() => ({ send: (...args: any[]) => mockCwSend(...args) })),
    GetMetricDataCommand: jest.fn().mockImplementation((input) => input),
  };
});

jest.mock('@/lib/logger', () => ({
  withLogging: (handler: any) => handler,
}));

import { GET } from '@/app/api/admin/ecs-health/route';
import { requireAdmin } from '@/lib/admin-auth';
import { setCache } from '@/lib/admin-cache';

const mockRequireAdmin = requireAdmin as jest.MockedFunction<typeof requireAdmin>;
const adminUser = { id: 'u1', username: 'admin', isAdmin: true as const };

describe('GET /api/admin/ecs-health', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  function makeRequest(hours?: number) {
    const url = hours
      ? `http://localhost:3000/api/admin/ecs-health?hours=${hours}`
      : 'http://localhost:3000/api/admin/ecs-health';
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

  it('returns ECS health data with no stopped tasks', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    // DescribeServices + ListTasks run in parallel via Promise.all
    mockEcsSend
      .mockResolvedValueOnce({
        services: [{ runningCount: 1, desiredCount: 1, pendingCount: 0 }],
      })
      .mockResolvedValueOnce({ taskArns: [] });

    // CloudWatch metrics
    const ts = new Date('2026-03-01T12:00:00Z');
    mockCwSend.mockResolvedValue({
      MetricDataResults: [
        { Id: 'cpu', Values: [25.5, 30.2], Timestamps: [ts, new Date('2026-03-01T12:05:00Z')] },
        { Id: 'memory', Values: [60.1, 62.3], Timestamps: [ts, new Date('2026-03-01T12:05:00Z')] },
      ],
    });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.service).toBe('book-vault-service');
    expect(data.tasks.running).toBe(1);
    expect(data.tasks.desired).toBe(1);
    expect(data.tasks.pending).toBe(0);
    expect(data.tasks.recentlyStopped).toHaveLength(0);
    expect(data.metrics.cpu).toEqual([25.5, 30.2]);
    expect(data.metrics.memory).toEqual([60.1, 62.3]);
    expect(data.metrics.timestamps).toHaveLength(2);
    expect(data.summary.spotInterruptions).toBe(0);
    expect(data.summary.crashes).toBe(0);
    expect(data.summary.deploymentStops).toBe(0);

    expect(setCache).toHaveBeenCalledWith('admin:ecs-health:24', data, 300000);
  });

  it('classifies stopped tasks correctly', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const now = new Date();
    const fiveMinAgo = new Date(now.getTime() - 5 * 60000);

    // DescribeServices + ListTasks
    mockEcsSend
      .mockResolvedValueOnce({
        services: [{ runningCount: 1, desiredCount: 1, pendingCount: 0 }],
      })
      .mockResolvedValueOnce({
        taskArns: [
          'arn:aws:ecs:us-east-1:123:task/book-vault/abc123',
          'arn:aws:ecs:us-east-1:123:task/book-vault/def456',
        ],
      });

    // DescribeTasks
    mockEcsSend.mockResolvedValueOnce({
      tasks: [
        {
          taskArn: 'arn:aws:ecs:us-east-1:123:task/book-vault/abc123',
          startedAt: fiveMinAgo,
          stoppedAt: now,
          stopCode: 'UserInitiated',
          stoppedReason: 'Spot instance interruption',
        },
        {
          taskArn: 'arn:aws:ecs:us-east-1:123:task/book-vault/def456',
          startedAt: fiveMinAgo,
          stoppedAt: now,
          stopCode: 'EssentialContainerExited',
          stoppedReason: 'Container exited with code 1',
        },
      ],
    });

    mockCwSend.mockResolvedValue({ MetricDataResults: [] });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(data.tasks.recentlyStopped).toHaveLength(2);
    expect(data.tasks.recentlyStopped[0].taskId).toBe('abc123');
    expect(data.tasks.recentlyStopped[0].durationMinutes).toBe(5);
    expect(data.summary.spotInterruptions).toBe(1);
    expect(data.summary.crashes).toBe(1);
  });

  it('uses custom hours parameter', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockEcsSend
      .mockResolvedValueOnce({
        services: [{ runningCount: 0, desiredCount: 0, pendingCount: 0 }],
      })
      .mockResolvedValueOnce({ taskArns: [] });
    mockCwSend.mockResolvedValue({ MetricDataResults: [] });

    await GET(makeRequest(48));

    expect(setCache).toHaveBeenCalledWith('admin:ecs-health:48', expect.any(Object), 300000);
  });

  it('returns 500 when ECS call fails', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });
    mockEcsSend.mockRejectedValue(new Error('ECS API error'));

    const response = await GET(makeRequest());
    expect(response.status).toBe(500);
  });
});
