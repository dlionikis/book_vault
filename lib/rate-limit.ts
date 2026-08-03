/**
 * Simple in-memory rate limiter for API endpoints
 * Uses a Map-based approach with sliding window
 *
 * ## Scope and limitations
 *
 * State lives in this module's `Map`, so a limit is **per ECS task** and resets
 * on deploy or task replacement. With N tasks behind the ALB an attacker gets up
 * to N× the nominal budget, and a rolling deploy clears all counters.
 *
 * That is a deliberate trade: it needs no new infrastructure and turns
 * unlimited credential stuffing into a bounded trickle. It is a speed bump, not
 * a guarantee. Genuine protection across tasks needs shared state (Redis or a
 * DynamoDB table) or a WAF rate rule at the ALB — worth doing if this app ever
 * faces real abuse rather than incidental scanning.
 */

import { NextRequest } from 'next/server';

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

const rateLimitMap = new Map<string, RateLimitEntry>();

// Cleanup old entries every 10 minutes.
//
// `.unref()` keeps this timer from holding the event loop open: without it Jest
// reports "a worker process has failed to exit gracefully" in any suite that
// imports this module, and the interval alone would keep a CLI process alive.
const cleanupTimer = setInterval(
  () => {
    const now = Date.now();
    for (const [key, entry] of rateLimitMap.entries()) {
      if (now > entry.resetTime) {
        rateLimitMap.delete(key);
      }
    }
  },
  10 * 60 * 1000
);
cleanupTimer.unref?.();

/**
 * Check if user has exceeded rate limit
 * @param userId - User ID to check
 * @param limit - Maximum requests allowed per window (default: 100)
 * @param windowMs - Time window in milliseconds (default: 60000 = 1 minute)
 * @returns true if request is allowed, false if rate limit exceeded
 */
export function checkRateLimit(
  userId: string,
  limit: number = 100,
  windowMs: number = 60000
): boolean {
  return consume(`progress:${userId}`, limit, windowMs);
}

/**
 * Core sliding-window check against an arbitrary key.
 *
 * @param key - Fully-qualified bucket key, e.g. `login:1.2.3.4`
 * @param limit - Maximum requests allowed per window
 * @param windowMs - Window length in milliseconds
 * @returns true if the request is allowed, false if the limit is exceeded
 */
function consume(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(key);

  if (!entry || now > entry.resetTime) {
    // New window or expired entry
    rateLimitMap.set(key, { count: 1, resetTime: now + windowMs });
    return true;
  }

  if (entry.count >= limit) {
    return false;
  }

  entry.count++;
  return true;
}

/**
 * Best-effort client IP for rate-limit bucketing.
 *
 * Requests reach the app through an ALB, which appends the real client IP to
 * `x-forwarded-for`. The **left-most** entry is the client; anything further
 * right is a proxy hop. A client can forge extra left-hand entries, so this is
 * only trustworthy enough for rate limiting — never for authorization.
 *
 * Falls back to a single shared bucket when no header is present (local dev),
 * which is stricter than skipping the limit.
 */
export function getClientIp(request: NextRequest): string {
  const forwarded = request.headers.get('x-forwarded-for');
  if (forwarded) {
    const first = forwarded.split(',')[0]?.trim();
    if (first) return first;
  }
  return request.headers.get('x-real-ip')?.trim() || 'unknown';
}

/**
 * Rate limit an unauthenticated endpoint by client IP.
 *
 * `checkRateLimit` keys on a user id, so it structurally cannot protect routes
 * that run *before* authentication — which left login and token refresh with no
 * limit at all. Password login is otherwise brute-forceable at network speed,
 * with bcrypt's cost factor as the only brake.
 *
 * Defaults to 10 requests per minute: far above any legitimate client (a person
 * mistyping a password, or the iOS app refreshing a token) and far below what
 * credential stuffing needs.
 *
 * @param request - Incoming request, for the client IP
 * @param bucket - Namespace so routes don't share a budget, e.g. 'login'
 * @param limit - Max requests per window (default 10)
 * @param windowMs - Window length in ms (default 60000)
 * @returns true if allowed, false if the caller should return 429
 */
export function checkIpRateLimit(
  request: NextRequest,
  bucket: string,
  limit: number = 10,
  windowMs: number = 60000
): boolean {
  return consume(`${bucket}:${getClientIp(request)}`, limit, windowMs);
}

/** Reset all buckets. Test-only. */
export function __resetRateLimits(): void {
  rateLimitMap.clear();
}

/**
 * Check download rate limit (max 50 downloads per day per user)
 * Uses database to track downloads for persistent rate limiting
 * @param userId - User ID to check
 * @returns Promise<boolean> - true if download is allowed, false if limit exceeded
 */
export async function checkDownloadLimit(userId: string): Promise<boolean> {
  const { prisma } = await import('@/lib/db');

  // Count downloads in last 24 hours
  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

  const downloadCount = await prisma.userDownload.count({
    where: {
      userId,
      downloadedAt: {
        gte: twentyFourHoursAgo,
      },
    },
  });

  // Max 50 downloads per day
  return downloadCount < 50;
}
