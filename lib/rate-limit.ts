/**
 * Simple in-memory rate limiter for API endpoints
 * Uses a Map-based approach with sliding window
 */

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

const rateLimitMap = new Map<string, RateLimitEntry>();

// Cleanup old entries every 10 minutes
setInterval(
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
  const key = `progress:${userId}`;
  const now = Date.now();
  const entry = rateLimitMap.get(key);

  if (!entry || now > entry.resetTime) {
    // New window or expired entry
    rateLimitMap.set(key, {
      count: 1,
      resetTime: now + windowMs,
    });
    return true;
  }

  if (entry.count >= limit) {
    return false;
  }

  entry.count++;
  return true;
}

/**
 * Check download rate limit (max 10 downloads per day per user)
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

  // Max 10 downloads per day
  return downloadCount < 10;
}
