import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { checkRateLimit } from '@/lib/rate-limit';
import { normalizeUuid } from '@/lib/api-utils';
import { logger, startTimer } from '@/lib/logger';

// GET /api/progress?bookId=xxx - Get user's progress for a book
export async function GET(request: NextRequest) {
  const timer = startTimer();
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    logger.request('GET', '/api/progress', 401, timer());
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const bookId = normalizeUuid(searchParams.get('bookId'));

    if (!bookId) {
      logger.request('GET', '/api/progress', 400, timer());
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
      logger.request('GET', '/api/progress', 200, timer());
      return NextResponse.json({
        positionSeconds: 0,
        completed: false,
        lastPlayed: null,
      });
    }

    logger.request('GET', '/api/progress', 200, timer());
    return NextResponse.json({
      positionSeconds: progress.positionSeconds,
      completed: progress.completed,
      lastPlayed: progress.lastPlayed.toISOString(),
    });
  } catch (error) {
    logger.error('Error fetching progress', { error: String(error) });
    logger.request('GET', '/api/progress', 500, timer());
    return NextResponse.json({ error: 'Failed to fetch progress' }, { status: 500 });
  }
}

// POST /api/progress - Update user's progress (save position)
export async function POST(request: NextRequest) {
  const timer = startTimer();

  // Support both session-based (web) and Bearer token (mobile) auth
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);

  const user = session?.user || mobileUser;

  if (!user) {
    logger.request('POST', '/api/progress', 401, timer());
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Rate limiting check
  if (!checkRateLimit(user.id, 100, 60000)) {
    logger.request('POST', '/api/progress', 429, timer());
    return NextResponse.json({ error: 'Rate limit exceeded' }, { status: 429 });
  }

  try {
    const body = await request.json();
    const { positionSeconds, timestamp } = body;
    const bookId = normalizeUuid(body.bookId);

    if (!bookId || positionSeconds === undefined) {
      logger.request('POST', '/api/progress', 400, timer());
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

    const duration = timer();

    // Performance monitoring: warn on slow queries
    if (duration > 100) {
      logger.warn('Slow progress query', {
        userId: user.id,
        bookId,
        durationMs: duration,
      });
    }

    logger.request('POST', '/api/progress', 200, duration);
    return NextResponse.json({
      positionSeconds: progress!.positionSeconds,
      completed: progress!.completed,
      lastPlayed: progress!.lastPlayed.toISOString(),
      updated,
    });
  } catch (error) {
    logger.error('Error updating progress', { error: String(error) });
    logger.request('POST', '/api/progress', 500, timer());
    return NextResponse.json({ error: 'Failed to update progress' }, { status: 500 });
  }
}

// PUT /api/progress - Mark book as completed or reset to not started
export async function PUT(request: NextRequest) {
  const timer = startTimer();

  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    logger.request('PUT', '/api/progress', 401, timer());
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { status } = body;
    const bookId = normalizeUuid(body.bookId);

    if (!bookId || !status) {
      logger.request('PUT', '/api/progress', 400, timer());
      return NextResponse.json({ error: 'Book ID and status are required' }, { status: 400 });
    }

    if (status !== 'completed' && status !== 'not-started') {
      logger.request('PUT', '/api/progress', 400, timer());
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

      logger.request('PUT', '/api/progress', 200, timer());
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

      logger.request('PUT', '/api/progress', 200, timer());
      return NextResponse.json({
        positionSeconds: progress.positionSeconds,
        completed: progress.completed,
        lastPlayed: progress.lastPlayed.toISOString(),
      });
    }
  } catch (error) {
    logger.error('Error updating progress status', { error: String(error) });
    logger.request('PUT', '/api/progress', 500, timer());
    return NextResponse.json({ error: 'Failed to update progress status' }, { status: 500 });
  }
}
