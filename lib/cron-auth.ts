import { NextRequest } from 'next/server';

/**
 * Guard for internal cron routes. They're triggered by EventBridge Scheduler
 * with `Authorization: Bearer $CRON_SECRET` — never by app clients — so they're
 * intentionally outside the OpenAPI spec and the session/bearer user auth.
 *
 * Returns true only when CRON_SECRET is configured AND the header matches.
 * (If CRON_SECRET is unset, every request is rejected — fail closed.)
 */
export function isAuthorizedCron(request: NextRequest): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  return request.headers.get('authorization') === `Bearer ${secret}`;
}
