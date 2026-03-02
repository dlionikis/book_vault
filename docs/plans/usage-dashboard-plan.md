# Usage & AWS Monitoring Dashboard - Implementation Plan

> **Created**: March 1, 2026
> **Status**: Planned
> **Priority**: Medium
> **Dependencies**: None (can be built independently of Glacier restore project)

---

## Overview

A two-tier monitoring solution for Book Vault:

1. **CloudWatch Dashboard** — Real-time operational health visible in AWS Console ($3/month)
2. **Admin Page** (`/admin/dashboard`) — Cost analytics, ECS task history, S3 storage breakdown, and user activity built into the Book Vault web app

### V1 Scope (This Plan)

- AWS costs by service with budget tracking
- ECS task health, turnover, and Fargate Spot interruptions
- S3 storage distribution by class and size trends

### V2 (Future)

- API response times and error rates
- User listening analytics
- RDS database health
- Restore activity tracking (after Glacier project ships)

---

## Table of Contents

1. [Architecture](#architecture)
2. [Phase 1: Database & Auth (Admin Role)](#phase-1-database--auth-admin-role)
3. [Phase 2: CloudWatch Dashboard (AWS Console)](#phase-2-cloudwatch-dashboard-aws-console)
4. [Phase 3: Backend API Routes](#phase-3-backend-api-routes)
5. [Phase 4: Admin Frontend](#phase-4-admin-frontend)
6. [Phase 5: AWS Budgets & Alerts](#phase-5-aws-budgets--alerts)
7. [Cost of the Dashboard Itself](#cost-of-the-dashboard-itself)
8. [Implementation Checklist](#implementation-checklist)

---

## Architecture

```
/admin/dashboard (Next.js client component)
  │
  ├── GET /api/admin/costs          → AWS Cost Explorer API (cached 24h)
  ├── GET /api/admin/ecs-health     → CloudWatch GetMetricData API
  ├── GET /api/admin/ecs-events     → ECS DescribeServices + CloudWatch Logs
  ├── GET /api/admin/s3-storage     → S3 ListBuckets + CloudWatch S3 metrics
  └── GET /api/admin/budgets        → AWS Budgets API

All /api/admin/* routes:
  → Check auth (session or JWT)
  → Check user.isAdmin === true
  → Return 403 if not admin
  → Cache responses server-side where appropriate
```

### IAM Permissions Required

The ECS task role (`book-vault-ecs-task`) needs additional permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DashboardReadAccess",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "budgets:ViewBudget",
        "budgets:DescribeBudgetPerformanceHistory",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "ecs:DescribeServices",
        "ecs:ListTasks",
        "ecs:DescribeTasks",
        "logs:FilterLogEvents",
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Note**: `ce:GetCostAndUsage` requires `Resource: "*"` — Cost Explorer doesn't support resource-level permissions.

---

## Phase 1: Database & Auth (Admin Role)

**Time estimate**: 1-2 hours

### Add `isAdmin` to User Model

```prisma
model User {
  // ... existing fields ...
  isAdmin   Boolean  @default(false) @map("is_admin")
}
```

Migration:

```sql
ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT false;

-- Set yourself as admin
UPDATE users SET is_admin = true WHERE username = 'YOUR_USERNAME';
```

### Admin Middleware

Reusable auth check for all admin routes:

```typescript
// lib/admin-auth.ts
import { getServerSession } from 'next-auth';
import { authOptions } from '@/app/api/auth/[...nextauth]/route';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

export async function requireAdmin(request: NextRequest): Promise<{
  user: { id: string; username: string } | null;
  error: Response | null;
}> {
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const authUser = session?.user || mobileUser;

  if (!authUser) {
    return { user: null, error: new Response('Unauthorized', { status: 401 }) };
  }

  const user = await prisma.user.findUnique({
    where: { id: authUser.id },
    select: { id: true, username: true, isAdmin: true },
  });

  if (!user?.isAdmin) {
    return { user: null, error: new Response('Forbidden', { status: 403 }) };
  }

  return { user, error: null };
}
```

### Admin Page Protection

```typescript
// app/admin/dashboard/page.tsx
import { getServerSession } from 'next-auth';
import { redirect } from 'next/navigation';
import { prisma } from '@/lib/db';

export default async function AdminDashboardPage() {
  const session = await getServerSession(authOptions);
  if (!session?.user?.id) redirect('/auth/login');

  const user = await prisma.user.findUnique({
    where: { id: session.user.id },
    select: { isAdmin: true },
  });

  if (!user?.isAdmin) redirect('/');

  return <DashboardClient />;
}
```

---

## Phase 2: CloudWatch Dashboard (AWS Console)

**Time estimate**: 1-2 hours (manual setup via AWS Console or CLI)

This is the real-time ops dashboard you check when something feels off. Create it via the AWS Console or with a CloudFormation/CLI template.

### Widgets to Include

**Row 1 — ECS Compute**

| Widget                 | Metric                                                | Period |
| ---------------------- | ----------------------------------------------------- | ------ |
| ECS CPU Utilization    | `AWS/ECS` → `CPUUtilization` (cluster: book-vault)    | 5 min  |
| ECS Memory Utilization | `AWS/ECS` → `MemoryUtilization` (cluster: book-vault) | 5 min  |
| Running Task Count     | `AWS/ECS` → `RunningTaskCount`                        | 1 min  |

**Row 2 — ALB & API**

| Widget               | Metric                                                      | Period |
| -------------------- | ----------------------------------------------------------- | ------ |
| Request Count        | `AWS/ApplicationELB` → `RequestCount`                       | 5 min  |
| Target Response Time | `AWS/ApplicationELB` → `TargetResponseTime` (p50, p95, p99) | 5 min  |
| HTTP 5xx Count       | `AWS/ApplicationELB` → `HTTPCode_Target_5XX_Count`          | 5 min  |
| HTTP 4xx Count       | `AWS/ApplicationELB` → `HTTPCode_Target_4XX_Count`          | 5 min  |
| Healthy Host Count   | `AWS/ApplicationELB` → `HealthyHostCount`                   | 1 min  |

**Row 3 — RDS**

| Widget             | Metric                                                 | Period |
| ------------------ | ------------------------------------------------------ | ------ |
| DB CPU Utilization | `AWS/RDS` → `CPUUtilization` (instance: book-vault-db) | 5 min  |
| DB Connections     | `AWS/RDS` → `DatabaseConnections`                      | 5 min  |
| Free Storage Space | `AWS/RDS` → `FreeStorageSpace`                         | 5 min  |

**Row 4 — S3**

| Widget              | Metric                                                  | Period |
| ------------------- | ------------------------------------------------------- | ------ |
| Bucket Size (bytes) | `AWS/S3` → `BucketSizeBytes` (bucket: book-vault-media) | 1 day  |
| Number of Objects   | `AWS/S3` → `NumberOfObjects`                            | 1 day  |

### CLI Creation (Optional)

```bash
aws cloudwatch put-dashboard \
  --dashboard-name BookVault-Production \
  --dashboard-body file://cloudwatch-dashboard.json \
  --profile book_vault \
  --region us-east-1
```

The JSON body can be exported from the console after visual configuration — easier to build visually first, then export for version control.

---

## Phase 3: Backend API Routes

**Time estimate**: 4-6 hours

All routes under `/api/admin/*` with the `requireAdmin()` check.

### 3.1 Cost Breakdown by Service

```typescript
// app/api/admin/costs/route.ts
import { CostExplorerClient, GetCostAndUsageCommand } from '@aws-sdk/client-cost-explorer';

export async function GET(request: NextRequest) {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const searchParams = request.nextUrl.searchParams;
  const months = parseInt(searchParams.get('months') || '6');

  const client = new CostExplorerClient({ region: 'us-east-1' });

  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - months, 1);

  const result = await client.send(
    new GetCostAndUsageCommand({
      TimePeriod: {
        Start: start.toISOString().slice(0, 10),
        End: now.toISOString().slice(0, 10),
      },
      Granularity: 'MONTHLY',
      Metrics: ['UnblendedCost'],
      GroupBy: [{ Type: 'DIMENSION', Key: 'SERVICE' }],
    })
  );

  // Transform into dashboard-friendly format
  const months_data = result.ResultsByTime?.map((period) => ({
    month: period.TimePeriod?.Start,
    services: period.Groups?.map((group) => ({
      service: group.Keys?.[0],
      cost: parseFloat(group.Metrics?.UnblendedCost?.Amount || '0'),
    })).sort((a, b) => b.cost - a.cost),
    total: period.Groups?.reduce(
      (sum, g) => sum + parseFloat(g.Metrics?.UnblendedCost?.Amount || '0'),
      0
    ),
  }));

  return Response.json({
    months: months_data,
    currency: 'USD',
    cached_at: new Date().toISOString(),
  });
}
```

**Caching strategy**: Cost data updates ~3 times per day. Cache responses in memory or a simple JSON file for 24 hours to keep API costs at $0.01/day max.

```typescript
// Simple in-memory cache
const cache = new Map<string, { data: any; expiry: number }>();
const CACHE_TTL = 24 * 60 * 60 * 1000; // 24 hours

function getCached(key: string) {
  const entry = cache.get(key);
  if (entry && Date.now() < entry.expiry) return entry.data;
  return null;
}

function setCache(key: string, data: any) {
  cache.set(key, { data, expiry: Date.now() + CACHE_TTL });
}
```

### 3.2 Budget Status

```typescript
// app/api/admin/budgets/route.ts
import { BudgetsClient, DescribeBudgetsCommand } from '@aws-sdk/client-budgets';

export async function GET(request: NextRequest) {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const client = new BudgetsClient({ region: 'us-east-1' });

  // Need account ID for Budgets API
  const accountId = process.env.AWS_ACCOUNT_ID;

  const result = await client.send(
    new DescribeBudgetsCommand({
      AccountId: accountId,
    })
  );

  const budgets = result.Budgets?.map((budget) => ({
    name: budget.BudgetName,
    type: budget.BudgetType,
    limit: parseFloat(budget.BudgetLimit?.Amount || '0'),
    actualSpend: parseFloat(budget.CalculatedSpend?.ActualSpend?.Amount || '0'),
    forecastedSpend: parseFloat(budget.CalculatedSpend?.ForecastedSpend?.Amount || '0'),
    period: budget.TimePeriod,
    percentUsed:
      budget.CalculatedSpend?.ActualSpend?.Amount && budget.BudgetLimit?.Amount
        ? (parseFloat(budget.CalculatedSpend.ActualSpend.Amount) /
            parseFloat(budget.BudgetLimit.Amount)) *
          100
        : 0,
  }));

  return Response.json({ budgets });
}
```

### 3.3 ECS Health & Task Turnover

This is the most complex endpoint — combines multiple AWS APIs to give a full picture.

```typescript
// app/api/admin/ecs-health/route.ts
import {
  ECSClient,
  DescribeServicesCommand,
  ListTasksCommand,
  DescribeTasksCommand,
} from '@aws-sdk/client-ecs';
import { CloudWatchClient, GetMetricDataCommand } from '@aws-sdk/client-cloudwatch';

export async function GET(request: NextRequest) {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const searchParams = request.nextUrl.searchParams;
  const hours = parseInt(searchParams.get('hours') || '24');

  const ecsClient = new ECSClient({ region: 'us-east-1' });
  const cwClient = new CloudWatchClient({ region: 'us-east-1' });

  // 1. Current service status
  const serviceResult = await ecsClient.send(
    new DescribeServicesCommand({
      cluster: 'book-vault',
      services: ['book-vault-service'],
    })
  );

  const service = serviceResult.services?.[0];

  // 2. Current tasks with stop reasons
  const taskArns = await ecsClient.send(
    new ListTasksCommand({
      cluster: 'book-vault',
      serviceName: 'book-vault-service',
    })
  );

  let tasks: any[] = [];
  if (taskArns.taskArns?.length) {
    const taskDetails = await ecsClient.send(
      new DescribeTasksCommand({
        cluster: 'book-vault',
        tasks: taskArns.taskArns,
      })
    );
    tasks = taskDetails.tasks || [];
  }

  // 3. Also get recently stopped tasks (for turnover tracking)
  const stoppedTaskArns = await ecsClient.send(
    new ListTasksCommand({
      cluster: 'book-vault',
      serviceName: 'book-vault-service',
      desiredStatus: 'STOPPED',
    })
  );

  let stoppedTasks: any[] = [];
  if (stoppedTaskArns.taskArns?.length) {
    const stoppedDetails = await ecsClient.send(
      new DescribeTasksCommand({
        cluster: 'book-vault',
        tasks: stoppedTaskArns.taskArns.slice(0, 20), // Last 20
      })
    );
    stoppedTasks = stoppedDetails.tasks || [];
  }

  // 4. CloudWatch metrics (CPU, memory, task count)
  const now = new Date();
  const start = new Date(now.getTime() - hours * 3600_000);

  const metricsResult = await cwClient.send(
    new GetMetricDataCommand({
      StartTime: start,
      EndTime: now,
      MetricDataQueries: [
        {
          Id: 'cpu',
          MetricStat: {
            Metric: {
              Namespace: 'AWS/ECS',
              MetricName: 'CPUUtilization',
              Dimensions: [
                { Name: 'ClusterName', Value: 'book-vault' },
                { Name: 'ServiceName', Value: 'book-vault-service' },
              ],
            },
            Period: 300, // 5 minute intervals
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
                { Name: 'ClusterName', Value: 'book-vault' },
                { Name: 'ServiceName', Value: 'book-vault-service' },
              ],
            },
            Period: 300,
            Stat: 'Average',
          },
        },
      ],
    })
  );

  // Transform task data
  const formatTask = (task: any) => ({
    taskId: task.taskArn?.split('/').pop(),
    status: task.lastStatus,
    desiredStatus: task.desiredStatus,
    startedAt: task.startedAt,
    stoppedAt: task.stoppedAt,
    stoppedReason: task.stoppedReason,
    stopCode: task.stopCode, // e.g., 'SpotInterruption', 'EssentialContainerExited'
    capacityProvider: task.capacityProviderName,
    healthStatus: task.healthStatus,
    cpu: task.cpu,
    memory: task.memory,
  });

  return Response.json({
    service: {
      status: service?.status,
      desiredCount: service?.desiredCount,
      runningCount: service?.runningCount,
      pendingCount: service?.pendingCount,
      deployments: service?.deployments?.map((d) => ({
        status: d.status,
        desiredCount: d.desiredCount,
        runningCount: d.runningCount,
        rolloutState: d.rolloutState,
        taskDefinition: d.taskDefinition?.split('/').pop(),
        updatedAt: d.updatedAt,
      })),
    },
    tasks: {
      running: tasks.map(formatTask),
      recentlyStopped: stoppedTasks
        .map(formatTask)
        .sort((a, b) => new Date(b.stoppedAt).getTime() - new Date(a.stoppedAt).getTime()),
    },
    metrics: {
      cpu: metricsResult.MetricDataResults?.find((m) => m.Id === 'cpu')?.Values || [],
      memory: metricsResult.MetricDataResults?.find((m) => m.Id === 'memory')?.Values || [],
      timestamps: metricsResult.MetricDataResults?.[0]?.Timestamps || [],
    },
    // Summary stats
    summary: {
      spotInterruptions: stoppedTasks.filter((t) => t.stopCode === 'SpotInterruption').length,
      crashes: stoppedTasks.filter((t) => t.stopCode === 'EssentialContainerExited').length,
      deploymentStops: stoppedTasks.filter(
        (t) => t.stoppedReason?.includes('deployment') || t.stopCode === 'ServiceSchedulerInitiated'
      ).length,
      totalStops: stoppedTasks.length,
    },
  });
}
```

### 3.4 S3 Storage Breakdown

```typescript
// app/api/admin/s3-storage/route.ts
import { CloudWatchClient, GetMetricDataCommand } from '@aws-sdk/client-cloudwatch';

export async function GET(request: NextRequest) {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const cwClient = new CloudWatchClient({ region: 'us-east-1' });

  const now = new Date();
  const start = new Date(now.getTime() - 90 * 24 * 3600_000); // 90 days

  // S3 bucket metrics are reported once daily
  const result = await cwClient.send(
    new GetMetricDataCommand({
      StartTime: start,
      EndTime: now,
      MetricDataQueries: [
        {
          Id: 'total_size',
          MetricStat: {
            Metric: {
              Namespace: 'AWS/S3',
              MetricName: 'BucketSizeBytes',
              Dimensions: [
                { Name: 'BucketName', Value: 'book-vault-media' },
                { Name: 'StorageType', Value: 'StandardStorage' },
              ],
            },
            Period: 86400, // 1 day
            Stat: 'Average',
          },
        },
        {
          Id: 'ia_size',
          MetricStat: {
            Metric: {
              Namespace: 'AWS/S3',
              MetricName: 'BucketSizeBytes',
              Dimensions: [
                { Name: 'BucketName', Value: 'book-vault-media' },
                { Name: 'StorageType', Value: 'IntelligentTieringFAStorage' },
              ],
            },
            Period: 86400,
            Stat: 'Average',
          },
        },
        {
          Id: 'ia_infrequent',
          MetricStat: {
            Metric: {
              Namespace: 'AWS/S3',
              MetricName: 'BucketSizeBytes',
              Dimensions: [
                { Name: 'BucketName', Value: 'book-vault-media' },
                { Name: 'StorageType', Value: 'IntelligentTieringIAStorage' },
              ],
            },
            Period: 86400,
            Stat: 'Average',
          },
        },
        {
          Id: 'archive_size',
          MetricStat: {
            Metric: {
              Namespace: 'AWS/S3',
              MetricName: 'BucketSizeBytes',
              Dimensions: [
                { Name: 'BucketName', Value: 'book-vault-media' },
                { Name: 'StorageType', Value: 'IntelligentTieringAAStorage' },
              ],
            },
            Period: 86400,
            Stat: 'Average',
          },
        },
        {
          Id: 'object_count',
          MetricStat: {
            Metric: {
              Namespace: 'AWS/S3',
              MetricName: 'NumberOfObjects',
              Dimensions: [
                { Name: 'BucketName', Value: 'book-vault-media' },
                { Name: 'StorageType', Value: 'AllStorageTypes' },
              ],
            },
            Period: 86400,
            Stat: 'Average',
          },
        },
      ],
    })
  );

  const getLatest = (id: string) => {
    const metric = result.MetricDataResults?.find((m) => m.Id === id);
    return metric?.Values?.[0] || 0;
  };

  const getTimeSeries = (id: string) => {
    const metric = result.MetricDataResults?.find((m) => m.Id === id);
    return {
      values: metric?.Values || [],
      timestamps: metric?.Timestamps || [],
    };
  };

  const toGB = (bytes: number) => Math.round((bytes / 1024 ** 3) * 100) / 100;

  return Response.json({
    current: {
      totalSizeGB: toGB(
        getLatest('total_size') +
          getLatest('ia_size') +
          getLatest('ia_infrequent') +
          getLatest('archive_size')
      ),
      standardGB: toGB(getLatest('total_size')),
      frequentAccessGB: toGB(getLatest('ia_size')),
      infrequentAccessGB: toGB(getLatest('ia_infrequent')),
      archiveGB: toGB(getLatest('archive_size')),
      objectCount: Math.round(getLatest('object_count')),
    },
    trends: {
      totalSize: getTimeSeries('total_size'),
      archiveSize: getTimeSeries('archive_size'),
      objectCount: getTimeSeries('object_count'),
    },
  });
}
```

### 3.5 OpenAPI Spec Additions

```yaml
# Add to paths section
/api/admin/costs:
  get:
    operationId: getAdminCosts
    tags: [Admin]
    summary: Get AWS cost breakdown by service
    security:
      - sessionAuth: []
      - bearerAuth: []
    parameters:
      - name: months
        in: query
        schema:
          type: integer
          minimum: 1
          maximum: 12
          default: 6
    responses:
      '200':
        description: Cost breakdown
      '403':
        description: Not an admin user

/api/admin/ecs-health:
  get:
    operationId: getAdminEcsHealth
    tags: [Admin]
    summary: Get ECS service health and task turnover
    security:
      - sessionAuth: []
      - bearerAuth: []
    parameters:
      - name: hours
        in: query
        schema:
          type: integer
          minimum: 1
          maximum: 168
          default: 24
    responses:
      '200':
        description: ECS health data
      '403':
        description: Not an admin user

/api/admin/s3-storage:
  get:
    operationId: getAdminS3Storage
    tags: [Admin]
    summary: Get S3 storage breakdown by class
    security:
      - sessionAuth: []
      - bearerAuth: []
    responses:
      '200':
        description: S3 storage data
      '403':
        description: Not an admin user

/api/admin/budgets:
  get:
    operationId: getAdminBudgets
    tags: [Admin]
    summary: Get AWS budget status
    security:
      - sessionAuth: []
      - bearerAuth: []
    responses:
      '200':
        description: Budget data
      '403':
        description: Not an admin user
```

---

## Phase 4: Admin Frontend

**Time estimate**: 4-6 hours

### Page Structure

```
/admin/dashboard
├── Header: "Book Vault Admin" + last refreshed timestamp
├── Budget Summary Bar (top — always visible)
│   └── Monthly budget: $X / $75 (progress bar, green/yellow/red)
│
├── Tab: Costs
│   ├── Monthly cost trend (line chart, 6 months)
│   ├── Current month cost by service (bar chart)
│   └── Cost table: service | this month | last month | change
│
├── Tab: ECS Health
│   ├── Current status: running/desired/pending task counts
│   ├── CPU + Memory utilization (line chart, 24h)
│   ├── Task turnover summary: spot interruptions / crashes / deployments
│   └── Recent task stops (table: task ID, stopped at, reason, stop code)
│
└── Tab: S3 Storage
    ├── Storage by class (donut chart: Standard, IA, Archive)
    ├── Total size trend (line chart, 90 days)
    ├── Object count
    └── Archive % (ties into Glacier restore project)
```

### Tech Choices

- **Charts**: Recharts (already available in your React stack for artifacts)
- **Layout**: Tailwind CSS (existing)
- **Data fetching**: Client-side with `useEffect` + `useState` (no SSR needed for charts)
- **Refresh**: Manual refresh button + auto-refresh every 5 minutes for ECS tab

### Key Component: DashboardClient

```typescript
// app/admin/dashboard/DashboardClient.tsx
'use client';

import { useState, useEffect } from 'react';
import { CostsTab } from './tabs/CostsTab';
import { EcsHealthTab } from './tabs/EcsHealthTab';
import { S3StorageTab } from './tabs/S3StorageTab';
import { BudgetBar } from './components/BudgetBar';

type Tab = 'costs' | 'ecs' | 's3';

export function DashboardClient() {
  const [activeTab, setActiveTab] = useState<Tab>('costs');
  const [budgetData, setBudgetData] = useState(null);

  useEffect(() => {
    fetch('/api/admin/budgets')
      .then(r => r.json())
      .then(setBudgetData);
  }, []);

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold mb-6">Admin Dashboard</h1>

      {budgetData && <BudgetBar budgets={budgetData.budgets} />}

      <div className="flex gap-4 border-b mb-6">
        {(['costs', 'ecs', 's3'] as Tab[]).map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`pb-2 px-4 ${activeTab === tab
              ? 'border-b-2 border-blue-600 font-semibold'
              : 'text-gray-500'}`}
          >
            {tab === 'costs' ? 'AWS Costs' : tab === 'ecs' ? 'ECS Health' : 'S3 Storage'}
          </button>
        ))}
      </div>

      {activeTab === 'costs' && <CostsTab />}
      {activeTab === 'ecs' && <EcsHealthTab />}
      {activeTab === 's3' && <S3StorageTab />}
    </div>
  );
}
```

### Budget Summary Bar

Always visible at top. Color-coded:

- **Green** (< 80% of budget): On track
- **Yellow** (80-100%): Approaching limit
- **Red** (> 100%): Over budget

```typescript
// components/BudgetBar.tsx
function getColor(percent: number) {
  if (percent >= 100) return 'bg-red-500';
  if (percent >= 80) return 'bg-yellow-500';
  return 'bg-green-500';
}
```

### ECS Task Turnover Table

Key table showing why tasks stopped — important for understanding Fargate Spot behavior:

```
| Task ID    | Stopped At       | Duration | Stop Code              | Reason              |
|------------|------------------|----------|------------------------|---------------------|
| abc123...  | 2026-03-01 14:22 | 18h 43m  | SpotInterruption       | Spot capacity claim |
| def456...  | 2026-02-28 03:15 | 2d 7h    | ServiceSchedulerInit   | Deployment rollout  |
| ghi789...  | 2026-02-27 22:01 | 0h 3m    | EssentialContainerExit | Exit code 137 (OOM) |
```

This tells you at a glance whether tasks are stopping due to normal operations (spot reclaim, deployments) or actual problems (crashes, OOM kills).

---

## Phase 5: AWS Budgets & Alerts

**Time estimate**: 1 hour (manual setup)

### Create Budgets

```bash
# Budget 1: Total monthly spend
aws budgets create-budget \
  --account-id YOUR_ACCOUNT_ID \
  --budget '{
    "BudgetName": "BookVault-Monthly-Total",
    "BudgetLimit": {"Amount": "80", "Unit": "USD"},
    "BudgetType": "COST",
    "TimeUnit": "MONTHLY",
    "CostTypes": {
      "IncludeTax": true,
      "IncludeSubscription": true
    }
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "YOUR_EMAIL"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "YOUR_EMAIL"}
      ]
    }
  ]' \
  --profile book_vault

# Budget 2: S3 specifically (largest variable cost)
aws budgets create-budget \
  --account-id YOUR_ACCOUNT_ID \
  --budget '{
    "BudgetName": "BookVault-S3-Storage",
    "BudgetLimit": {"Amount": "15", "Unit": "USD"},
    "BudgetType": "COST",
    "TimeUnit": "MONTHLY",
    "CostFilters": {
      "Service": ["Amazon Simple Storage Service"]
    }
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "YOUR_EMAIL"}
      ]
    }
  ]' \
  --profile book_vault
```

Alerts trigger:

- Email when actual spend hits 80% of total budget
- Email when forecasted spend exceeds 100% of total budget
- Email when S3 costs exceed their sub-budget

First two budgets are free. You'll pay nothing for this.

---

## Cost of the Dashboard Itself

| Component                                        | Monthly Cost     |
| ------------------------------------------------ | ---------------- |
| CloudWatch Dashboard (1)                         | $3.00            |
| Cost Explorer API (~30 requests/month, cached)   | $0.30            |
| CloudWatch GetMetricData (well within free tier) | $0.00            |
| AWS Budgets (2 budgets)                          | $0.00            |
| ECS DescribeTasks API calls                      | $0.00            |
| **Total**                                        | **~$3.30/month** |

---

## Implementation Checklist

### Phase 1: Database & Auth (1-2 hours)

- [ ] Add `isAdmin` column to User model
- [ ] Create Prisma migration
- [ ] Set admin flag for your user
- [ ] Create `requireAdmin()` middleware
- [ ] Test admin check works (returns 403 for non-admins)

### Phase 2: CloudWatch Dashboard (1-2 hours)

- [ ] Create dashboard in AWS Console with ECS, ALB, RDS, S3 widgets
- [ ] Verify metrics are populating
- [ ] Export dashboard JSON for version control
- [ ] Save to `infra/cloudwatch-dashboard.json` in repo

### Phase 3: Backend API Routes (4-6 hours)

- [ ] Add IAM permissions to `book-vault-ecs-task` role
- [ ] Install `@aws-sdk/client-cost-explorer` and `@aws-sdk/client-budgets`
- [ ] Implement `GET /api/admin/costs` with 24h caching
- [ ] Implement `GET /api/admin/budgets`
- [ ] Implement `GET /api/admin/ecs-health`
- [ ] Implement `GET /api/admin/s3-storage`
- [ ] Update OpenAPI spec with admin endpoints
- [ ] Add tests for admin auth (403 for non-admin, 401 for unauth)

### Phase 4: Admin Frontend (4-6 hours)

- [ ] Create `/admin/dashboard` page with server-side admin check
- [ ] Create `DashboardClient` component with tab navigation
- [ ] Build `BudgetBar` component (progress bar with color coding)
- [ ] Build `CostsTab` with monthly trend chart + service breakdown
- [ ] Build `EcsHealthTab` with metrics charts + task turnover table
- [ ] Build `S3StorageTab` with storage class donut chart + trend
- [ ] Add auto-refresh on ECS tab (5 min interval)
- [ ] Test on mobile (responsive layout)

### Phase 5: AWS Budgets & Alerts (1 hour)

- [ ] Create total monthly budget ($80)
- [ ] Create S3 sub-budget ($15)
- [ ] Configure email alerts at 80% and 100% thresholds
- [ ] Verify alert email delivery

### Post-Implementation

- [ ] Add link to admin dashboard in user menu (admin-only)
- [ ] Update CLAUDE.md with admin route patterns
- [ ] Document admin setup in README

---

## V2 Enhancements (Future)

1. **API Performance Tab**: Response time by endpoint (p50/p95/p99), error rates, slowest endpoints. Data from your existing `withLogging` middleware — would need to persist metrics to DB or CloudWatch custom metrics.

2. **User Analytics Tab**: Active users, listening hours, most popular books, library growth. Derived from existing `UserProgress` and `UserDownload` tables.

3. **RDS Health Tab**: Query latency, connection pool usage, storage growth forecast. From CloudWatch RDS metrics + Performance Insights.

4. **Restore Activity Tab** (after Glacier project): Restore requests/completions/failures, average restore time, monthly restore costs. From `media_restore_requests` table.

5. **Cost Forecasting**: Use `GetCostForecast` API to show predicted end-of-month spend.

6. **iOS Admin View**: Surface key metrics (budget status, system health) in the iOS app for admin users.

---

## Related Documents

- [aws-deployment-reference.md](./aws-deployment-reference.md) - Current AWS setup
- [infra/production.md](./infra/production.md) - Infrastructure inventory
- [archive/aws-deployment-plan-full.md](./archive/aws-deployment-plan-full.md) - Full deployment history
