import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid, isValidUuid } from '@/lib/api-utils';
import { getAudioUrl } from '@/lib/media';

/** Presigned URL / local URL lifetime, in seconds. Mirrors downloads route. */
const STREAM_URL_EXPIRY = 3600; // 1 hour

/**
 * GET /api/books/{id}/stream
 *
 * On-demand streaming URL generation. Returns a presigned S3 URL (production)
 * or a local /api/audio URL (development) only when a client actually plays a
 * book — instead of eagerly attaching audioUrl to every list response.
 *
 * Phase 0 of the S3 archive restore workflow: this endpoint currently only
 * generates URLs. Phase 2 extends the production branch with HeadObject
 * ArchiveStatus detection, returning 202 { status: 'restoring' } for archived
 * files. The response schema already carries a `status` discriminator so that
 * addition is non-breaking for clients.
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
      select: { id: true, audioUrl: true },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    if (!book.audioUrl) {
      return NextResponse.json({ error: 'Book has no audio file' }, { status: 400 });
    }

    // getAudioUrl() branches on isS3Enabled(): presigned S3 URL in production
    // (and hybrid mode via S3_ENABLED), local /api/audio URL otherwise.
    const streamUrl = await getAudioUrl(book.audioUrl);
    if (!streamUrl) {
      return NextResponse.json({ error: 'Book has no audio file' }, { status: 400 });
    }

    return NextResponse.json({
      status: 'available',
      streamUrl,
      expiresAt: new Date(Date.now() + STREAM_URL_EXPIRY * 1000).toISOString(),
      bookId: book.id,
    });
  } catch (error) {
    logger.error('Stream URL generation error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to generate stream URL' }, { status: 500 });
  }
}
