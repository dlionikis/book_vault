import { NextRequest, NextResponse } from 'next/server';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_1M } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { isPushEnabled } from '@/lib/notification-service';

/**
 * GET /api/admin/restores — restore-request observability for the admin dashboard.
 *
 * Pure DB (no AWS calls / no extra IAM). Surfaces the restore-request lifecycle
 * (in-progress + recently completed/failed) with all timestamps, a status
 * summary, and DB-derived push health. Auth: admin only.
 */

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const STUCK_RESTORE_MS = 6 * 60 * 60 * 1000; // past the 3-5h Standard-tier SLA
const MAX_REQUESTS = 50;

interface RestoreRequestRow {
  id: string;
  bookId: string;
  bookTitle: string;
  status: string;
  requestedByUsername: string | null;
  errorMessage: string | null;
  // All timestamps as ISO strings (null when not yet set).
  requestedAt: string;
  lastCheckedAt: string | null;
  completedAt: string | null;
}

interface RestoresResponse {
  summary: {
    inProgress: number;
    completedLast7d: number;
    failedLast7d: number;
    stuck: number; // in_progress past the SLA
    lastPolledAt: string | null; // newest lastCheckedAt across in_progress
  };
  requests: RestoreRequestRow[];
  push: {
    configured: boolean;
    activeTokens: number;
    inactiveTokens: number;
  };
  generatedAt: string;
}

export const GET = withLogging(async (request: NextRequest) => {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const cacheKey = 'admin:restores';
  const cached = getCached<RestoresResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  const now = Date.now();
  const sevenDaysAgo = new Date(now - SEVEN_DAYS_MS);
  const stuckCutoff = new Date(now - STUCK_RESTORE_MS);

  const [
    inProgress,
    completedLast7d,
    failedLast7d,
    stuck,
    freshest,
    rows,
    activeTokens,
    inactiveTokens,
  ] = await Promise.all([
    prisma.mediaRestoreRequest.count({ where: { status: 'in_progress' } }),
    prisma.mediaRestoreRequest.count({
      where: { status: 'completed', completedAt: { gte: sevenDaysAgo } },
    }),
    prisma.mediaRestoreRequest.count({
      where: { status: 'failed', requestedAt: { gte: sevenDaysAgo } },
    }),
    prisma.mediaRestoreRequest.count({
      where: { status: 'in_progress', requestedAt: { lt: stuckCutoff } },
    }),
    prisma.mediaRestoreRequest.findFirst({
      where: { status: 'in_progress', lastCheckedAt: { not: null } },
      orderBy: { lastCheckedAt: 'desc' },
      select: { lastCheckedAt: true },
    }),
    // Active + recently-finished, newest first.
    prisma.mediaRestoreRequest.findMany({
      where: {
        OR: [
          { status: 'in_progress' },
          { status: 'completed', completedAt: { gte: sevenDaysAgo } },
          { status: 'failed', requestedAt: { gte: sevenDaysAgo } },
        ],
      },
      orderBy: { requestedAt: 'desc' },
      take: MAX_REQUESTS,
      select: {
        id: true,
        bookId: true,
        status: true,
        errorMessage: true,
        requestedAt: true,
        lastCheckedAt: true,
        completedAt: true,
        book: { select: { title: true } },
        requestedBy: { select: { username: true } },
      },
    }),
    prisma.userDeviceToken.count({ where: { isActive: true } }),
    prisma.userDeviceToken.count({ where: { isActive: false } }),
  ]);

  const requests: RestoreRequestRow[] = rows.map((r) => ({
    id: r.id,
    bookId: r.bookId,
    bookTitle: r.book?.title ?? '(unknown)',
    status: r.status,
    requestedByUsername: r.requestedBy?.username ?? null,
    errorMessage: r.errorMessage,
    requestedAt: r.requestedAt.toISOString(),
    lastCheckedAt: r.lastCheckedAt ? r.lastCheckedAt.toISOString() : null,
    completedAt: r.completedAt ? r.completedAt.toISOString() : null,
  }));

  const response: RestoresResponse = {
    summary: {
      inProgress,
      completedLast7d,
      failedLast7d,
      stuck,
      lastPolledAt: freshest?.lastCheckedAt ? freshest.lastCheckedAt.toISOString() : null,
    },
    requests,
    push: {
      configured: isPushEnabled(),
      activeTokens,
      inactiveTokens,
    },
    generatedAt: new Date().toISOString(),
  };

  setCache(cacheKey, response, CACHE_1M);
  return NextResponse.json(response);
});
