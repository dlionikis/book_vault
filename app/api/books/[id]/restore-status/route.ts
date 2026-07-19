import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid, isValidUuid } from '@/lib/api-utils';
import { estimatedCompletion, AVAILABILITY } from '@/lib/restore';

/**
 * GET /api/books/{id}/restore-status
 *
 * Restore-progress polling endpoint. Driven by the book's cached availability
 * (kept current by the stream/restore endpoints, the restore poller, and the
 * nightly sync) — no S3 call, so clients can poll it every ~30s for free.
 *
 * Auth: Required
 * Returns: RestoreStatus { status: available|archived|restoring, ... }
 * Errors: 400 invalid id, 401 unauthenticated, 404 not found
 */
export async function GET(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  try {
    const auth = await requireUser(request);
    if (auth.error) return auth.error;

    const bookId = normalizeUuid(params.id);
    if (!isValidUuid(bookId)) {
      return NextResponse.json({ error: 'Invalid book ID format' }, { status: 400 });
    }

    const book = await prisma.book.findUnique({
      where: { id: bookId },
      select: { id: true, audioAvailability: true },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    const latest = await prisma.mediaRestoreRequest.findFirst({
      where: { bookId: book.id },
      orderBy: { requestedAt: 'desc' },
    });

    switch (book.audioAvailability) {
      case AVAILABILITY.RESTORING:
        return NextResponse.json({
          status: 'restoring',
          requestedAt: latest?.requestedAt.toISOString(),
          estimatedCompletion: latest ? estimatedCompletion(latest.requestedAt) : undefined,
        });
      case AVAILABILITY.ARCHIVED:
        return NextResponse.json({
          status: 'archived',
          lastError: latest?.status === 'failed' ? latest.errorMessage : null,
        });
      default:
        return NextResponse.json({
          status: 'available',
          completedAt: latest?.completedAt?.toISOString() ?? null,
        });
    }
  } catch (error) {
    logger.error('Restore status error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to get restore status' }, { status: 500 });
  }
}
