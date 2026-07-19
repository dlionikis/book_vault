import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid, isValidUuid } from '@/lib/api-utils';
import { isS3Enabled } from '@/lib/s3';
import {
  getArchiveState,
  initiateRestore,
  estimatedCompletion,
  setBookAvailability,
  AVAILABILITY,
} from '@/lib/restore';

/**
 * POST /api/books/{id}/restore
 *
 * Explicitly request an S3 Intelligent-Tiering restore for an archived
 * audiobook (the "Request restore" button) — lets a user restore without
 * pretending to play. Idempotent: an in-flight restore is reused. If the
 * real-time HeadObject shows the file is NOT archived, responds
 * 200 { status: 'available' } and self-heals the cached availability.
 *
 * Auth: Required
 * Returns: 202 BookStreamResponse (status=restoring) or 200 (status=available)
 * Errors: 400 invalid id / no audio, 401 unauthenticated, 404 not found
 */
export async function POST(request: NextRequest, props: { params: Promise<{ id: string }> }) {
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
      select: { id: true, audioUrl: true, audioAvailability: true },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    if (!book.audioUrl) {
      return NextResponse.json({ error: 'Book has no audio file' }, { status: 400 });
    }

    // Local development: files never archive.
    if (!isS3Enabled()) {
      return NextResponse.json({ status: 'available', bookId: book.id });
    }

    const { archived } = await getArchiveState(book.audioUrl);

    if (!archived) {
      // Nothing to restore — self-heal the cache and report available.
      if (book.audioAvailability !== AVAILABILITY.AVAILABLE) {
        await setBookAvailability(book.id, AVAILABILITY.AVAILABLE);
      }
      return NextResponse.json({ status: 'available', bookId: book.id });
    }

    const restoreRequest = await initiateRestore(
      { id: book.id, audioUrl: book.audioUrl },
      auth.user.id
    );
    return NextResponse.json(
      {
        status: 'restoring',
        message: 'Restore initiated. The audiobook will be ready in 3-5 hours.',
        bookId: book.id,
        requestedAt: restoreRequest.requestedAt.toISOString(),
        estimatedCompletion: estimatedCompletion(restoreRequest.requestedAt),
      },
      { status: 202 }
    );
  } catch (error) {
    logger.error('Restore request error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to request restore' }, { status: 500 });
  }
}
