import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { checkRateLimit } from '@/lib/rate-limit';

interface ProgressUpdate {
  bookId: string;
  positionSeconds: number;
  timestamp: string;
}

interface BatchUpdateRequest {
  updates: ProgressUpdate[];
}

interface UpdateResult {
  bookId: string;
  status: 'updated' | 'conflict';
}

/**
 * POST /api/progress/batch - Batch update user progress for offline sync
 * Accepts array of progress updates with timestamps for conflict resolution
 */
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
    const body: BatchUpdateRequest = await request.json();

    if (!body.updates || !Array.isArray(body.updates) || body.updates.length === 0) {
      return NextResponse.json({ error: 'Updates array required' }, { status: 400 });
    }

    let updatedCount = 0;
    let conflictCount = 0;
    const details: UpdateResult[] = [];

    // Process updates in a transaction
    await prisma.$transaction(async (tx) => {
      for (const update of body.updates) {
        const { bookId, positionSeconds, timestamp } = update;

        if (!bookId || positionSeconds === undefined || !timestamp) {
          continue; // Skip invalid entries
        }

        const clientTimestamp = new Date(timestamp);

        // Fetch existing progress to check for conflicts
        const existing = await tx.userProgress.findUnique({
          where: {
            userId_bookId: {
              userId: user.id,
              bookId,
            },
          },
        });

        let shouldUpdate = true;

        // Conflict resolution: only update if client timestamp is newer
        if (existing && existing.lastPlayed > clientTimestamp) {
          shouldUpdate = false;
          conflictCount++;
          details.push({ bookId, status: 'conflict' });
        }

        if (shouldUpdate) {
          await tx.userProgress.upsert({
            where: {
              userId_bookId: {
                userId: user.id,
                bookId,
              },
            },
            update: {
              positionSeconds,
              lastPlayed: clientTimestamp,
            },
            create: {
              userId: user.id,
              bookId,
              positionSeconds,
              completed: false,
              lastPlayed: clientTimestamp,
            },
          });

          updatedCount++;
          details.push({ bookId, status: 'updated' });
        }
      }
    });

    return NextResponse.json({
      updated: updatedCount,
      conflicts: conflictCount,
      details,
    });
  } catch (error) {
    console.error('Error in batch progress update:', error);
    return NextResponse.json({ error: 'Batch update failed' }, { status: 500 });
  }
}
