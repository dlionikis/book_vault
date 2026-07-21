import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid, isValidUuid } from '@/lib/api-utils';
import { isS3Enabled } from '@/lib/s3';
import { initiateRestore, AVAILABILITY } from '@/lib/restore';

/**
 * POST /api/series/{id}/restore
 *
 * Batch-initiate an S3 Intelligent-Tiering restore for every archived audiobook
 * in a series (the "Restore All Archived" button), so a user with a fully
 * archived series doesn't have to request restores one book at a time.
 *
 * Filters on the cached `audioAvailability` column (fine here — `initiateRestore`
 * is idempotent and harmless if a book turns out to be available, and the
 * per-book stream/restore endpoints self-correct at play time). Per book:
 * idempotent — an in-flight restore is reused, never duplicated.
 *
 * Auth: Required
 * Returns: 200 { message, total, results[] } — `total` is the archived count a
 *   restore was attempted for; each result is { bookId, title, status, error? }.
 * Errors: 400 invalid id, 401 unauthenticated, 404 series not found
 */
export async function POST(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  try {
    const auth = await requireUser(request);
    if (auth.error) return auth.error;

    const seriesId = normalizeUuid(params.id);
    if (!isValidUuid(seriesId)) {
      return NextResponse.json({ error: 'Invalid series ID format' }, { status: 400 });
    }

    const series = await prisma.series.findUnique({
      where: { id: seriesId },
      select: { id: true },
    });
    if (!series) {
      return NextResponse.json({ error: 'Series not found' }, { status: 404 });
    }

    const seriesBooks = await prisma.bookSeries.findMany({
      where: { seriesId },
      include: {
        book: { select: { id: true, title: true, audioUrl: true, audioAvailability: true } },
      },
      orderBy: { sequence: 'asc' },
    });

    // Only books with audio that the cache says are archived. In local dev
    // (no S3) nothing is archived, so this is naturally empty.
    const archivedBooks = isS3Enabled()
      ? seriesBooks.filter(
          (sb) => sb.book.audioUrl && sb.book.audioAvailability === AVAILABILITY.ARCHIVED
        )
      : [];

    if (archivedBooks.length === 0) {
      return NextResponse.json({
        message: 'No archived books in this series',
        total: 0,
        results: [],
      });
    }

    const results = [];
    for (const sb of archivedBooks) {
      try {
        await initiateRestore({ id: sb.book.id, audioUrl: sb.book.audioUrl! }, auth.user.id);
        results.push({ bookId: sb.book.id, title: sb.book.title, status: 'initiated' });
      } catch (error) {
        logger.error('Series restore: per-book initiate failed', {
          seriesId,
          bookId: sb.book.id,
          error: String(error),
        });
        results.push({
          bookId: sb.book.id,
          title: sb.book.title,
          status: 'failed',
          error: String(error),
        });
      }
    }

    const initiated = results.filter((r) => r.status === 'initiated').length;
    return NextResponse.json({
      message: `Restore initiated for ${initiated} book${initiated === 1 ? '' : 's'}`,
      total: archivedBooks.length,
      results,
    });
  } catch (error) {
    logger.error('Series restore request error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to request series restore' }, { status: 500 });
  }
}
