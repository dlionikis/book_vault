import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { checkRateLimit } from '@/lib/rate-limit';

// GET /api/progress?bookId=xxx - Get user's progress for a book
export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const bookId = searchParams.get('bookId');

    if (!bookId) {
      return NextResponse.json({ error: 'Book ID is required' }, { status: 400 });
    }

    const progress = await prisma.userProgress.findUnique({
      where: {
        userId_bookId: {
          userId: session.user.id,
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
    console.error('Error fetching progress:', error);
    return NextResponse.json({ error: 'Failed to fetch progress' }, { status: 500 });
  }
}

// POST /api/progress - Update user's progress (save position)
export async function POST(request: NextRequest) {
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
    const startTime = Date.now();
    const body = await request.json();
    const { bookId, positionSeconds, timestamp } = body;

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

    const duration = Date.now() - startTime;

    // Performance monitoring: warn on slow queries
    if (duration > 100) {
      console.warn('Slow progress query', {
        userId: user.id,
        bookId,
        durationMs: duration,
      });
    }

    return NextResponse.json({
      positionSeconds: progress!.positionSeconds,
      completed: progress!.completed,
      lastPlayed: progress!.lastPlayed.toISOString(),
      updated,
    });
  } catch (error) {
    console.error('Error updating progress:', error);
    return NextResponse.json({ error: 'Failed to update progress' }, { status: 500 });
  }
}

// PUT /api/progress - Mark book as completed or reset to not started
export async function PUT(request: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { bookId, status } = body;

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
          userId: session.user.id,
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
            userId: session.user.id,
            bookId: bookId,
          },
        },
        update: {
          completed: true,
          lastPlayed: new Date(),
        },
        create: {
          userId: session.user.id,
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
    console.error('Error updating progress status:', error);
    return NextResponse.json({ error: 'Failed to update progress status' }, { status: 500 });
  }
}
