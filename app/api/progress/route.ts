import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

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
  } finally {
    await prisma.$disconnect();
  }
}

// POST /api/progress - Update user's progress (save position)
export async function POST(request: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { bookId, positionSeconds } = body;

    if (!bookId || positionSeconds === undefined) {
      return NextResponse.json({ error: 'Book ID and position are required' }, { status: 400 });
    }

    // Create or update progress
    const progress = await prisma.userProgress.upsert({
      where: {
        userId_bookId: {
          userId: session.user.id,
          bookId: bookId,
        },
      },
      update: {
        positionSeconds: positionSeconds,
        lastPlayed: new Date(),
      },
      create: {
        userId: session.user.id,
        bookId: bookId,
        positionSeconds: positionSeconds,
        completed: false,
      },
    });

    return NextResponse.json({
      positionSeconds: progress.positionSeconds,
      completed: progress.completed,
      lastPlayed: progress.lastPlayed.toISOString(),
    });
  } catch (error) {
    console.error('Error updating progress:', error);
    return NextResponse.json({ error: 'Failed to update progress' }, { status: 500 });
  } finally {
    await prisma.$disconnect();
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
  } finally {
    await prisma.$disconnect();
  }
}
