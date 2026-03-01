import { NextRequest, NextResponse } from 'next/server';
import {
  ECSClient,
  DescribeServicesCommand,
  ListTasksCommand,
  DescribeTasksCommand,
} from '@aws-sdk/client-ecs';
import { CloudWatchClient, GetMetricDataCommand } from '@aws-sdk/client-cloudwatch';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_5M } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';

const region = process.env.AWS_REGION || 'us-east-1';
const ecsClient = new ECSClient({ region });
const cwClient = new CloudWatchClient({ region });

const CLUSTER = 'book-vault';
const SERVICE = 'book-vault-service';

interface TaskInfo {
  taskId: string;
  stoppedAt: string | null;
  durationMinutes: number | null;
  stopCode: string | null;
  stoppedReason: string | null;
}

interface EcsHealthResponse {
  service: string;
  tasks: {
    running: number;
    desired: number;
    pending: number;
    recentlyStopped: TaskInfo[];
  };
  metrics: {
    cpu: number[];
    memory: number[];
    timestamps: string[];
  };
  summary: {
    spotInterruptions: number;
    crashes: number;
    deploymentStops: number;
  };
}

export const GET = withLogging(async (request: NextRequest) => {
  const { user, error } = await requireAdmin(request);
  if (error) return error;

  const hours = parseInt(request.nextUrl.searchParams.get('hours') || '24');
  const cacheKey = `admin:ecs-health:${hours}`;

  const cached = getCached<EcsHealthResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  try {
    // Fetch service info and stopped tasks in parallel
    const [serviceResult, stoppedTaskArns] = await Promise.all([
      ecsClient.send(new DescribeServicesCommand({ cluster: CLUSTER, services: [SERVICE] })),
      ecsClient.send(
        new ListTasksCommand({
          cluster: CLUSTER,
          serviceName: SERVICE,
          desiredStatus: 'STOPPED',
          maxResults: 20,
        })
      ),
    ]);

    const svc = serviceResult.services?.[0];
    const running = svc?.runningCount ?? 0;
    const desired = svc?.desiredCount ?? 0;
    const pending = svc?.pendingCount ?? 0;

    // Describe stopped tasks if any
    let stoppedTasks: TaskInfo[] = [];
    let spotInterruptions = 0;
    let crashes = 0;
    let deploymentStops = 0;

    if (stoppedTaskArns.taskArns?.length) {
      const described = await ecsClient.send(
        new DescribeTasksCommand({
          cluster: CLUSTER,
          tasks: stoppedTaskArns.taskArns,
        })
      );

      stoppedTasks = (described.tasks || []).map((task) => {
        const startedAt = task.startedAt ? new Date(task.startedAt).getTime() : null;
        const stoppedAt = task.stoppedAt ? new Date(task.stoppedAt).getTime() : null;
        const durationMinutes =
          startedAt && stoppedAt ? Math.round((stoppedAt - startedAt) / 60000) : null;

        const stopCode = task.stopCode || null;
        const reason = task.stoppedReason || null;

        if (reason?.includes('spot') || reason?.includes('Spot')) spotInterruptions++;
        else if (stopCode === 'ServiceSchedulerInitiated') deploymentStops++;
        else if (stopCode === 'TaskFailedToStart' || stopCode === 'EssentialContainerExited')
          crashes++;

        return {
          taskId: task.taskArn?.split('/').pop() || '',
          stoppedAt: task.stoppedAt?.toISOString() || null,
          durationMinutes,
          stopCode,
          stoppedReason: reason,
        };
      });
    }

    // Fetch CloudWatch metrics
    const now = new Date();
    const startTime = new Date(now.getTime() - hours * 60 * 60 * 1000);

    const metricsResult = await cwClient.send(
      new GetMetricDataCommand({
        StartTime: startTime,
        EndTime: now,
        MetricDataQueries: [
          {
            Id: 'cpu',
            MetricStat: {
              Metric: {
                Namespace: 'AWS/ECS',
                MetricName: 'CPUUtilization',
                Dimensions: [
                  { Name: 'ClusterName', Value: CLUSTER },
                  { Name: 'ServiceName', Value: SERVICE },
                ],
              },
              Period: 300,
              Stat: 'Average',
            },
          },
          {
            Id: 'memory',
            MetricStat: {
              Metric: {
                Namespace: 'AWS/ECS',
                MetricName: 'MemoryUtilization',
                Dimensions: [
                  { Name: 'ClusterName', Value: CLUSTER },
                  { Name: 'ServiceName', Value: SERVICE },
                ],
              },
              Period: 300,
              Stat: 'Average',
            },
          },
        ],
      })
    );

    const cpuData = metricsResult.MetricDataResults?.find((m) => m.Id === 'cpu');
    const memData = metricsResult.MetricDataResults?.find((m) => m.Id === 'memory');

    const response: EcsHealthResponse = {
      service: SERVICE,
      tasks: {
        running,
        desired,
        pending,
        recentlyStopped: stoppedTasks,
      },
      metrics: {
        cpu: (cpuData?.Values || []).map((v) => Math.round(v * 100) / 100),
        memory: (memData?.Values || []).map((v) => Math.round(v * 100) / 100),
        timestamps: (cpuData?.Timestamps || []).map((t) => t.toISOString()),
      },
      summary: {
        spotInterruptions,
        crashes,
        deploymentStops,
      },
    };

    setCache(cacheKey, response, CACHE_5M);
    return NextResponse.json(response);
  } catch (err) {
    console.error('Failed to fetch ECS health:', err);
    return NextResponse.json({ error: 'Failed to fetch ECS health data' }, { status: 500 });
  }
});
