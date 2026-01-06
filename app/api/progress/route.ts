import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { checkRateLimit } from '@/lib/rate-limit';
import { normalizeUuid } from '@/lib/api-utils';
import { logger, withLogging } from '@/lib/logger';

/**
 * GET /api/progress
 *
 * Get user's listening progress for a specific book or all books. Returns current position
 * in seconds, completion status, and last played timestamp.
 *
 * Auth: Required
 * Query Parameters:
 *   - bookId: Book UUID (required) - Single book progress
 *
 * Returns: { positionSeconds: number, completed: boolean, lastPlayed: string | null }
 * Errors: 400 if bookId missing or invalid, 401 if not authenticated, 500 on server error
 *
 * @example
 * fetch('/api/progress?bookId=abc-123')
 */
export const GET = withLogging(async (request: NextRequest) => {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const bookId = normalizeUuid(searchParams.get('bookId'));

    if (!bookId) {
      return NextResponse.json({ error: 'Book ID is required' }, { status: 400 });
    }

    const progress = await prisma.userProgress.findUnique({
      where: {
        userId_bookId: {
          userId: user.id,
          bookId: bookId,
        },
      },
    });

    if (!progress) {
      return NextResponse.json({
        positionSeconds: 0,
        completed: false,
        lastPlayed: null,
      });
    }

    return NextResponse.json({
      positionSeconds: progress.positionSeconds,
      completed: progress.completed,
      lastPlayed: progress.lastPlayed.toISOString(),
    });
  } catch (error) {
    logger.error('Error fetching progress', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch progress' }, { status: 500 });
  }
});

/**
 * POST /api/progress
 *
 * Save user's current playback position for a book. Automatically marks book as completed
 * if position is > 95% of total runtime. Updates lastPlayed timestamp. Rate limited to
 * 100 requests per minute per user to handle frequent auto-save calls.
 *
 * Auth: Required
 * Request Body: { bookId: string, positionSeconds: number }
 *
 * Returns: { positionSeconds: number, completed: boolean, progressPercentage: number }
 * Errors: 400 if invalid data, 401 if not authenticated, 429 if rate limited, 500 on error
 *
 * @example
 * fetch('/api/progress', {
 *   method: 'POST',
 *   headers: { 'Content-Type': 'application/json' },
 *   body: JSON.stringify({ bookId: 'abc-123', positionSeconds: 1234 })
 * })
 */
export const POST = withLogging(async (request: NextRequest) => {
  // Support both session-based (web) and Bearer token (mobile) auth
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);

  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Rate limiting check
  if (!checkRateLimit(user.id, 100, 60000)) {
    return NextResponse.json({ error: 'Rate limit exceeded' }, { status: 429 });
  }

  try {
    const body = await request.json();
    const { positionSeconds, timestamp } = body;
    const bookId = normalizeUuid(body.bookId);

    if (!bookId || positionSeconds === undefined) {
      return NextResponse.json({ error: 'Book ID and position are required' }, { status: 400 });
    }

    // Use provided timestamp or current time
    const updateTime = timestamp ? new Date(timestamp) : new Date();

    let updated = true;

    // If timestamp provided, check for conflicts
    if (timestamp) {
      const existing = await prisma.userProgress.findUnique({
        where: {
          userId_bookId: {
            userId: user.id,
            bookId: bookId,
          },
        },
      });

      // Only update if client timestamp is newer or no existing record
      if (existing && existing.lastPlayed > updateTime) {
        updated = false;
      }
    }

    let progress;

    if (updated) {
      // Create or update progress
      progress = await prisma.userProgress.upsert({
        where: {
          userId_bookId: {
            userId: user.id,
            bookId: bookId,
          },
        },
        update: {
          positionSeconds: positionSeconds,
          lastPlayed: updateTime,
        },
        create: {
          userId: user.id,
          bookId: bookId,
          positionSeconds: positionSeconds,
          completed: false,
          lastPlayed: updateTime,
        },
      });
    } else {
      // Return existing progress (conflict case)
      progress = await prisma.userProgress.findUnique({
        where: {
          userId_bookId: {
            userId: user.id,
            bookId: bookId,
          },
        },
      });
    }

    return NextResponse.json({
      positionSeconds: progress!.positionSeconds,
      completed: progress!.completed,
      lastPlayed: progress!.lastPlayed.toISOString(),
      updated,
    });
  } catch (error) {
    logger.error('Error updating progress', { error: String(error) });
    return NextResponse.json({ error: 'Failed to update progress' }, { status: 500 });
  }
});

// PUT /api/progress - Mark book as completed or reset to not started
export const PUT = withLogging(async (request: NextRequest) => {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { status } = body;
    const bookId = normalizeUuid(body.bookId);

    if (!bookId || !status) {
      return NextResponse.json({ error: 'Book ID and status are required' }, { status: 400 });
    }

    if (status !== 'completed' && status !== 'not-started') {
      return NextResponse.json(
        { error: 'Status must be "completed" or "not-started"' },
        { status: 400 }
      );
    }

    if (status === 'not-started') {
      // Reset progress (delete the record)
      await prisma.userProgress.deleteMany({
        where: {
          userId: user.id,
          bookId: bookId,
        },
      });

      return NextResponse.json({
        positionSeconds: 0,
        completed: false,
        lastPlayed: null,
      });
    } else {
      // Mark as completed
      const progress = await prisma.userProgress.upsert({
        where: {
          userId_bookId: {
            userId: user.id,
            bookId: bookId,
          },
        },
        update: {
          completed: true,
          lastPlayed: new Date(),
        },
        create: {
          userId: user.id,
          bookId: bookId,
          positionSeconds: 0,
          completed: true,
        },
      });

      return NextResponse.json({
        positionSeconds: progress.positionSeconds,
        completed: progress.completed,
        lastPlayed: progress.lastPlayed.toISOString(),
      });
    }
  } catch (error) {
    logger.error('Error updating progress status', { error: String(error) });
    return NextResponse.json({ error: 'Failed to update progress status' }, { status: 500 });
  }
});
