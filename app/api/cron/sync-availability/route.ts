import { NextRequest, NextResponse } from 'next/server';
import { isAuthorizedCron } from '@/lib/cron-auth';
import { syncAvailability } from '@/lib/sync-availability';
import { logger } from '@/lib/logger';

/**
 * GET /api/cron/sync-availability — internal, EventBridge-scheduled (nightly).
 * Not part of the public API (CRON_SECRET-guarded; excluded from OpenAPI).
 */
export async function GET(request: NextRequest) {
  if (!isAuthorizedCron(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const result = await syncAvailability();
    return NextResponse.json({ success: true, checkedAt: new Date().toISOString(), result });
  } catch (error) {
    logger.error('cron sync-availability failed', { error: String(error) });
    return NextResponse.json({ error: 'Sync failed' }, { status: 500 });
  }
}
