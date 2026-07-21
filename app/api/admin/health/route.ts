import { NextRequest, NextResponse } from 'next/server';
import { HeadBucketCommand } from '@aws-sdk/client-s3';
import {
  EventBridgeClient,
  DescribeConnectionCommand,
  DescribeApiDestinationCommand,
  DescribeRuleCommand,
} from '@aws-sdk/client-eventbridge';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_1M } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { getS3Client, getS3Bucket, isS3Enabled } from '@/lib/s3';
import { isPushEnabled } from '@/lib/notification-service';
import { AVAILABILITY } from '@/lib/restore';

/**
 * GET /api/admin/health — infrastructure health snapshot for the admin dashboard.
 *
 * Checks the always-on parts the restore workflow depends on (DB, S3, SNS push,
 * and the EventBridge poller/sync connection). Motivated by a silent outage
 * where the EventBridge connection went DEAUTHORIZED and the poller failed every
 * invocation for hours with nothing surfacing it.
 *
 * Every check is individually try/caught and the whole set runs via
 * allSettled, so one failing check (or missing IAM before it's granted) shows a
 * red card rather than 500-ing the panel. Auth: admin only.
 */

const region = process.env.AWS_REGION || 'us-east-1';
const ebClient = new EventBridgeClient({ region });

// EventBridge resource names (defaults match the deployed infra).
const CRON_CONNECTION = process.env.CRON_CONNECTION_NAME || 'book-vault-cron';
const CRON_DESTINATIONS = (
  process.env.CRON_API_DESTINATIONS || 'book-vault-poll-restores,book-vault-sync-availability'
)
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const CRON_RULES = (
  process.env.CRON_RULE_NAMES || 'book-vault-poll-restores,book-vault-sync-availability'
)
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

// The poller runs every 5 min; flag if the newest in-progress restore hasn't
// been checked within this window (a dead poller reveals itself here).
const POLLER_STALE_MS = 15 * 60 * 1000;
// A just-requested restore hasn't hit its first 5-min poll yet, so don't call
// the poller "down" for a never-polled restore until it's older than one cycle
// plus slack. Prevents a false alarm right after requesting a (series) restore.
const POLLER_GRACE_MS = 6 * 60 * 1000;
// Standard-tier restores finish in 3-5h; anything in-progress past this is stuck.
const STUCK_RESTORE_MS = 6 * 60 * 60 * 1000;

type HealthStatus = 'ok' | 'warn' | 'error';

interface HealthCheck {
  name: string;
  status: HealthStatus;
  detail: string;
  meta?: Record<string, unknown>;
}

interface HealthResponse {
  checks: HealthCheck[];
  generatedAt: string;
}

/** Run one check, converting any throw into an `error` card (never propagates). */
async function runCheck(name: string, fn: () => Promise<HealthCheck>): Promise<HealthCheck> {
  try {
    return await fn();
  } catch (error) {
    return { name, status: 'error', detail: `Check failed: ${String(error)}` };
  }
}

async function checkDatabase(): Promise<HealthCheck> {
  await prisma.$queryRaw`SELECT 1`;
  return { name: 'Database', status: 'ok', detail: 'Connected' };
}

async function checkS3(): Promise<HealthCheck> {
  if (!isS3Enabled()) {
    return { name: 'S3', status: 'warn', detail: 'S3 disabled (local/dev mode)' };
  }
  const bucket = getS3Bucket();
  if (!bucket) {
    return { name: 'S3', status: 'error', detail: 'AWS_S3_BUCKET not configured' };
  }
  await getS3Client().send(new HeadBucketCommand({ Bucket: bucket }));
  return { name: 'S3', status: 'ok', detail: `Bucket reachable: ${bucket}` };
}

async function checkPush(): Promise<HealthCheck> {
  const enabled = isPushEnabled();
  const activeTokens = await prisma.userDeviceToken.count({ where: { isActive: true } });
  if (!enabled) {
    return {
      name: 'Push (APNs/SNS)',
      status: 'warn',
      detail: 'Push not configured (no SNS platform ARN)',
      meta: { activeTokens },
    };
  }
  return {
    name: 'Push (APNs/SNS)',
    status: 'ok',
    detail: `Configured; ${activeTokens} active device token${activeTokens === 1 ? '' : 's'}`,
    meta: { activeTokens },
  };
}

async function checkPollerFreshness(): Promise<HealthCheck> {
  const active = await prisma.mediaRestoreRequest.findMany({
    where: { status: 'in_progress' },
    select: { requestedAt: true, lastCheckedAt: true },
  });
  if (active.length === 0) {
    return { name: 'Restore poller', status: 'ok', detail: 'No active restores to poll' };
  }

  const now = Date.now();
  const checkedTimes = active
    .map((r) => r.lastCheckedAt)
    .filter((t): t is Date => t != null)
    .map((t) => new Date(t).getTime());

  // If nothing has been polled yet, only alarm once a never-polled restore has
  // outlived the grace window (one poll cycle + slack). Freshly-requested
  // restores are expected to be unpolled for a few minutes.
  if (checkedTimes.length === 0) {
    const oldestRequestedMs = Math.min(...active.map((r) => new Date(r.requestedAt).getTime()));
    if (now - oldestRequestedMs > POLLER_GRACE_MS) {
      return {
        name: 'Restore poller',
        status: 'error',
        detail: 'Active restores exist but none have been polled (poller not running?)',
      };
    }
    return {
      name: 'Restore poller',
      status: 'ok',
      detail: `${active.length} active restore${active.length === 1 ? '' : 's'} awaiting first poll`,
    };
  }

  // At least one restore has been polled → the poller is running. Judge freshness
  // by the most recent poll across all active restores.
  const lastChecked = Math.max(...checkedTimes);
  const ageMin = Math.round((now - lastChecked) / 60000);
  if (now - lastChecked > POLLER_STALE_MS) {
    return {
      name: 'Restore poller',
      status: 'error',
      detail: `Last poll ${ageMin}m ago — poller may be down (expected every 5m)`,
      meta: { lastCheckedAt: new Date(lastChecked).toISOString() },
    };
  }
  return {
    name: 'Restore poller',
    status: 'ok',
    detail: `Last poll ${ageMin}m ago`,
    meta: { lastCheckedAt: new Date(lastChecked).toISOString() },
  };
}

async function checkStuckRestores(): Promise<HealthCheck> {
  const cutoff = new Date(Date.now() - STUCK_RESTORE_MS);
  const stuck = await prisma.mediaRestoreRequest.count({
    where: { status: 'in_progress', requestedAt: { lt: cutoff } },
  });
  if (stuck > 0) {
    return {
      name: 'Stuck restores',
      status: 'warn',
      detail: `${stuck} restore${stuck === 1 ? '' : 's'} in progress > 6h (past the 3-5h SLA)`,
      meta: { count: stuck },
    };
  }
  return { name: 'Stuck restores', status: 'ok', detail: 'None past SLA' };
}

async function checkAvailability(): Promise<HealthCheck> {
  const grouped = await prisma.book.groupBy({
    by: ['audioAvailability'],
    _count: { _all: true },
  });
  const counts: Record<string, number> = {};
  for (const g of grouped) {
    counts[g.audioAvailability ?? 'UNKNOWN'] = g._count._all;
  }
  const available = counts[AVAILABILITY.AVAILABLE] ?? 0;
  const archived = counts[AVAILABILITY.ARCHIVED] ?? 0;
  const restoring = counts[AVAILABILITY.RESTORING] ?? 0;
  return {
    name: 'Audio availability',
    status: 'ok',
    detail: `${available} available · ${archived} archived · ${restoring} restoring`,
    meta: { available, archived, restoring },
  };
}

async function checkEventBridge(): Promise<HealthCheck> {
  // Connection must be AUTHORIZED, destinations ACTIVE, rules ENABLED. A
  // DEAUTHORIZED connection is exactly the silent failure this whole panel exists
  // to surface.
  const conn = await ebClient.send(new DescribeConnectionCommand({ Name: CRON_CONNECTION }));
  const connState = conn.ConnectionState;
  if (connState !== 'AUTHORIZED') {
    return {
      name: 'EventBridge cron',
      status: 'error',
      detail: `Connection "${CRON_CONNECTION}" is ${connState} (expected AUTHORIZED) — poller/sync will fail`,
      meta: { connectionState: connState },
    };
  }

  const destStates = await Promise.all(
    CRON_DESTINATIONS.map(async (name) => {
      const d = await ebClient.send(new DescribeApiDestinationCommand({ Name: name }));
      return { name, state: d.ApiDestinationState };
    })
  );
  const ruleStates = await Promise.all(
    CRON_RULES.map(async (name) => {
      const r = await ebClient.send(new DescribeRuleCommand({ Name: name }));
      return { name, state: r.State };
    })
  );

  const badDest = destStates.find((d) => d.state !== 'ACTIVE');
  const badRule = ruleStates.find((r) => r.state !== 'ENABLED');
  if (badDest) {
    return {
      name: 'EventBridge cron',
      status: 'error',
      detail: `API destination "${badDest.name}" is ${badDest.state} (expected ACTIVE)`,
      meta: { connectionState: connState, destinations: destStates, rules: ruleStates },
    };
  }
  if (badRule) {
    return {
      name: 'EventBridge cron',
      status: 'warn',
      detail: `Rule "${badRule.name}" is ${badRule.state} (expected ENABLED)`,
      meta: { connectionState: connState, destinations: destStates, rules: ruleStates },
    };
  }

  return {
    name: 'EventBridge cron',
    status: 'ok',
    detail: `Connection AUTHORIZED; ${destStates.length} destinations ACTIVE, ${ruleStates.length} rules ENABLED`,
    meta: { connectionState: connState, destinations: destStates, rules: ruleStates },
  };
}

export const GET = withLogging(async (request: NextRequest) => {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const cacheKey = 'admin:health';
  const cached = getCached<HealthResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  const checks = await Promise.all([
    runCheck('Database', checkDatabase),
    runCheck('S3', checkS3),
    runCheck('Push (APNs/SNS)', checkPush),
    runCheck('Restore poller', checkPollerFreshness),
    runCheck('Stuck restores', checkStuckRestores),
    runCheck('Audio availability', checkAvailability),
    runCheck('EventBridge cron', checkEventBridge),
  ]);

  const response: HealthResponse = { checks, generatedAt: new Date().toISOString() };
  setCache(cacheKey, response, CACHE_1M);
  return NextResponse.json(response);
});
