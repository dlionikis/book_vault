import { NextRequest, NextResponse } from 'next/server';
import { isAuthorizedCron } from '@/lib/cron-auth';
import { pollRestoreStatus } from '@/lib/poll-restore-status';
import { logger } from '@/lib/logger';

/**
 * GET /api/cron/poll-restores — internal, EventBridge-scheduled (every 5 min).
 * Not part of the public API (CRON_SECRET-guarded; excluded from OpenAPI).
 */
export async function GET(request: NextRequest) {
  if (!isAuthorizedCron(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const result = await pollRestoreStatus();
    return NextResponse.json({ success: true, checkedAt: new Date().toISOString(), result });
  } catch (error) {
    logger.error('cron poll-restores failed', { error: String(error) });
    return NextResponse.json({ error: 'Poll failed' }, { status: 500 });
  }
}
