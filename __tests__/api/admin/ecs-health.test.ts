import { NextRequest } from 'next/server';

jest.mock('@/lib/admin-auth', () => ({
  requireAdmin: jest.fn(),
}));

jest.mock('@/lib/admin-cache', () => ({
  getCached: jest.fn().mockReturnValue(null),
  setCache: jest.fn(),
  clearCache: jest.fn(),
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

  // Helper to mock a successful response with no stopped tasks
  function mockBasicEcsResponse(
    services: { running: number; desired: number; pending: number; name: string }[]
  ) {
    // DescribeServices (1 call) + ListTasks for each service (2 calls for spot + fallback)
    mockEcsSend
      .mockResolvedValueOnce({
        services: services.map((s) => ({
          serviceName: s.name,
          runningCount: s.running,
          desiredCount: s.desired,
          pendingCount: s.pending,
        })),
      })
      .mockResolvedValueOnce({ taskArns: [] }) // stopped tasks for service 1
      .mockResolvedValueOnce({ taskArns: [] }); // stopped tasks for service 2
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

  it('returns ECS health data with both services', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockBasicEcsResponse([
      { name: 'book-vault-spot', running: 2, desired: 2, pending: 0 },
      { name: 'book-vault-fallback', running: 0, desired: 0, pending: 0 },
    ]);

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
    expect(data.cluster).toBe('book-vault');
    expect(data.services).toHaveLength(2);
    expect(data.services[0].name).toBe('book-vault-spot');
    expect(data.services[0].running).toBe(2);
    expect(data.services[1].name).toBe('book-vault-fallback');
    expect(data.services[1].running).toBe(0);
    expect(data.tasks.running).toBe(2); // aggregated
    expect(data.tasks.desired).toBe(2);
    expect(data.tasks.pending).toBe(0);
    expect(data.tasks.recentlyStopped).toHaveLength(0);
    expect(data.metrics.cpu).toEqual([25.5, 30.2]);
    expect(data.summary.spotInterruptions).toBe(0);

    expect(setCache).toHaveBeenCalledWith('admin:ecs-health:24', data, 300000);
  });

  it('classifies stopped tasks correctly', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const now = new Date();
    const fiveMinAgo = new Date(now.getTime() - 5 * 60000);

    // DescribeServices
    mockEcsSend.mockResolvedValueOnce({
      services: [
        { serviceName: 'book-vault-spot', runningCount: 1, desiredCount: 2, pendingCount: 0 },
        { serviceName: 'book-vault-fallback', runningCount: 0, desiredCount: 0, pendingCount: 0 },
      ],
    });

    // ListTasks for spot service - has stopped tasks
    mockEcsSend.mockResolvedValueOnce({
      taskArns: [
        'arn:aws:ecs:us-east-1:123:task/book-vault/abc123',
        'arn:aws:ecs:us-east-1:123:task/book-vault/def456',
      ],
    });
    // ListTasks for fallback service - no stopped tasks
    mockEcsSend.mockResolvedValueOnce({ taskArns: [] });

    // DescribeTasks
    mockEcsSend.mockResolvedValueOnce({
      tasks: [
        {
          taskArn: 'arn:aws:ecs:us-east-1:123:task/book-vault/abc123',
          group: 'service:book-vault-spot',
          startedAt: fiveMinAgo,
          stoppedAt: now,
          stopCode: 'UserInitiated',
          stoppedReason: 'Spot instance interruption',
        },
        {
          taskArn: 'arn:aws:ecs:us-east-1:123:task/book-vault/def456',
          group: 'service:book-vault-spot',
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
    expect(data.tasks.recentlyStopped[0].service).toBe('book-vault-spot');
    expect(data.tasks.recentlyStopped[0].durationMinutes).toBe(5);
    expect(data.summary.spotInterruptions).toBe(1);
    expect(data.summary.crashes).toBe(1);
  });

  it('classifies deployment stops correctly', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    const now = new Date();
    const fiveMinAgo = new Date(now.getTime() - 5 * 60000);

    mockEcsSend.mockResolvedValueOnce({
      services: [
        { serviceName: 'book-vault-spot', runningCount: 1, desiredCount: 1, pendingCount: 0 },
        { serviceName: 'book-vault-fallback', runningCount: 0, desiredCount: 0, pendingCount: 0 },
      ],
    });
    mockEcsSend.mockResolvedValueOnce({
      taskArns: ['arn:aws:ecs:us-east-1:123:task/book-vault/deploy123'],
    });
    mockEcsSend.mockResolvedValueOnce({ taskArns: [] });

    mockEcsSend.mockResolvedValueOnce({
      tasks: [
        {
          taskArn: 'arn:aws:ecs:us-east-1:123:task/book-vault/deploy123',
          group: 'service:book-vault-spot',
          startedAt: fiveMinAgo,
          stoppedAt: now,
          stopCode: 'ServiceSchedulerInitiated',
          stoppedReason: 'Deployment triggered',
        },
      ],
    });

    mockCwSend.mockResolvedValue({ MetricDataResults: [] });

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(data.summary.deploymentStops).toBe(1);
    expect(data.summary.spotInterruptions).toBe(0);
    expect(data.summary.crashes).toBe(0);
  });

  it('uses custom hours parameter', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockBasicEcsResponse([
      { name: 'book-vault-spot', running: 0, desired: 0, pending: 0 },
      { name: 'book-vault-fallback', running: 0, desired: 0, pending: 0 },
    ]);
    mockCwSend.mockResolvedValue({ MetricDataResults: [] });

    await GET(makeRequest(48));

    expect(setCache).toHaveBeenCalledWith('admin:ecs-health:48', expect.any(Object), 300000);
  });

  it('clamps invalid hours param to default 24', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockBasicEcsResponse([
      { name: 'book-vault-spot', running: 0, desired: 0, pending: 0 },
      { name: 'book-vault-fallback', running: 0, desired: 0, pending: 0 },
    ]);
    mockCwSend.mockResolvedValue({ MetricDataResults: [] });

    await GET(makeRequest(999));

    expect(setCache).toHaveBeenCalledWith('admin:ecs-health:24', expect.any(Object), 300000);
  });

  it('returns 500 with safe error message when ECS call fails', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });
    mockEcsSend.mockRejectedValue(new Error('ECS API error with credentials'));

    const response = await GET(makeRequest());
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.error).toBe('Failed to fetch ECS health data');
    expect(JSON.stringify(data)).not.toContain('credentials');
  });

  it('handles null MetricDataResults', async () => {
    mockRequireAdmin.mockResolvedValue({ user: adminUser, error: null });

    mockBasicEcsResponse([
      { name: 'book-vault-spot', running: 1, desired: 1, pending: 0 },
      { name: 'book-vault-fallback', running: 0, desired: 0, pending: 0 },
    ]);
    mockCwSend.mockResolvedValue({});

    const response = await GET(makeRequest());
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.metrics.cpu).toEqual([]);
    expect(data.metrics.memory).toEqual([]);
    expect(data.metrics.timestamps).toEqual([]);
  });
});
