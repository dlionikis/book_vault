import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { getCoverUrl } from '@/lib/media';
import { estimatedCompletion } from '@/lib/restore';

/**
 * GET /api/books/restores
 *
 * The authenticated user's active restore requests plus those completed in the
 * last 7 days, newest first. Backs the /library/restores page and the iOS
 * restores list.
 *
 * Auth: Required
 * Returns: { restores: RestoreRequestSummary[] }
 */
export async function GET(request: NextRequest) {
  try {
    const auth = await requireUser(request);
    if (auth.error) return auth.error;

    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 3600_000);
    const requests = await prisma.mediaRestoreRequest.findMany({
      where: {
        requestedByUserId: auth.user.id,
        OR: [
          { status: 'in_progress' },
          { status: 'completed', completedAt: { gte: sevenDaysAgo } },
        ],
      },
      include: {
        book: { select: { id: true, title: true, coverUrl: true } },
      },
      orderBy: { requestedAt: 'desc' },
    });

    const restores = await Promise.all(
      requests.map(async (r) => ({
        id: r.id,
        bookId: r.bookId,
        status: r.status,
        requestedAt: r.requestedAt.toISOString(),
        completedAt: r.completedAt?.toISOString() ?? null,
        estimatedCompletion: r.status === 'in_progress' ? estimatedCompletion(r.requestedAt) : null,
        book: {
          id: r.book.id,
          title: r.book.title,
          coverUrl: await getCoverUrl(r.book.coverUrl),
        },
      }))
    );

    return NextResponse.json({ restores });
  } catch (error) {
    logger.error('Restores list error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to list restores' }, { status: 500 });
  }
}
