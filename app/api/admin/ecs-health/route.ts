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

const CLUSTER = process.env.ECS_CLUSTER_NAME || 'book-vault';
const SERVICES = (process.env.ECS_SERVICE_NAMES || 'book-vault-spot,book-vault-fallback')
  .split(',')
  .map((s) => s.trim());

const ALLOWED_HOURS = [24, 48, 168];

interface TaskInfo {
  taskId: string;
  service: string;
  stoppedAt: string | null;
  durationMinutes: number | null;
  stopCode: string | null;
  stoppedReason: string | null;
}

interface ServiceStatus {
  name: string;
  running: number;
  desired: number;
  pending: number;
}

interface EcsHealthResponse {
  cluster: string;
  services: ServiceStatus[];
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
  const { error } = await requireAdmin(request);
  if (error) return error;

  const rawHours = parseInt(request.nextUrl.searchParams.get('hours') || '24');
  const hours = ALLOWED_HOURS.includes(rawHours) ? rawHours : 24;
  const cacheKey = `admin:ecs-health:${hours}`;

  const cached = getCached<EcsHealthResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  try {
    // Fetch all services info + stopped tasks for each service in parallel
    const [serviceResult, ...stoppedTaskResults] = await Promise.all([
      ecsClient.send(new DescribeServicesCommand({ cluster: CLUSTER, services: SERVICES })),
      ...SERVICES.map((svc) =>
        ecsClient.send(
          new ListTasksCommand({
            cluster: CLUSTER,
            serviceName: svc,
            desiredStatus: 'STOPPED',
            maxResults: 10,
          })
        )
      ),
    ]);

    // Aggregate service counts
    const serviceStatuses: ServiceStatus[] = (serviceResult.services || []).map((svc) => ({
      name: svc.serviceName || 'unknown',
      running: svc.runningCount ?? 0,
      desired: svc.desiredCount ?? 0,
      pending: svc.pendingCount ?? 0,
    }));

    const totalRunning = serviceStatuses.reduce((sum, s) => sum + s.running, 0);
    const totalDesired = serviceStatuses.reduce((sum, s) => sum + s.desired, 0);
    const totalPending = serviceStatuses.reduce((sum, s) => sum + s.pending, 0);

    // Collect all stopped task ARNs
    const allStoppedArns = stoppedTaskResults.flatMap((r) => r.taskArns || []);

    // Describe stopped tasks if any
    let stoppedTasks: TaskInfo[] = [];
    let spotInterruptions = 0;
    let crashes = 0;
    let deploymentStops = 0;

    if (allStoppedArns.length) {
      const described = await ecsClient.send(
        new DescribeTasksCommand({
          cluster: CLUSTER,
          tasks: allStoppedArns,
        })
      );

      stoppedTasks = (described.tasks || []).map((task) => {
        const startedAt = task.startedAt ? new Date(task.startedAt).getTime() : null;
        const stoppedAt = task.stoppedAt ? new Date(task.stoppedAt).getTime() : null;
        const durationMinutes =
          startedAt && stoppedAt ? Math.round((stoppedAt - startedAt) / 60000) : null;

        const stopCode = task.stopCode || null;
        const reason = task.stoppedReason || null;

        if (stopCode === 'SpotInterruption' || reason?.toLowerCase().includes('spot')) {
          spotInterruptions++;
        } else if (stopCode === 'ServiceSchedulerInitiated') {
          deploymentStops++;
        } else if (stopCode === 'TaskFailedToStart' || stopCode === 'EssentialContainerExited') {
          crashes++;
        }

        // Extract service name from task group (e.g., "service:book-vault-spot")
        const serviceName = task.group?.replace('service:', '') || '';

        return {
          taskId: task.taskArn?.split('/').pop() || '',
          service: serviceName,
          stoppedAt: task.stoppedAt?.toISOString() || null,
          durationMinutes,
          stopCode,
          stoppedReason: reason,
        };
      });
    }

    // Fetch CloudWatch metrics for the primary service (book-vault-spot)
    const primaryService = SERVICES[0];
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
                  { Name: 'ServiceName', Value: primaryService },
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
                  { Name: 'ServiceName', Value: primaryService },
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
      cluster: CLUSTER,
      services: serviceStatuses,
      tasks: {
        running: totalRunning,
        desired: totalDesired,
        pending: totalPending,
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
