import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid, isValidUuid } from '@/lib/api-utils';
import { getAudioUrl } from '@/lib/media';
import { isS3Enabled } from '@/lib/s3';
import {
  getArchiveState,
  initiateRestore,
  estimatedCompletion,
  setBookAvailability,
  AVAILABILITY,
} from '@/lib/restore';

/** Presigned URL / local URL lifetime, in seconds. Mirrors downloads route. */
const STREAM_URL_EXPIRY = 3600; // 1 hour

/**
 * GET /api/books/{id}/stream
 *
 * On-demand streaming URL generation. Returns a presigned S3 URL (production)
 * or a local /api/audio URL (development) only when a client actually plays a
 * book — instead of eagerly attaching audioUrl to every list response.
 *
 * Production (and S3_ENABLED hybrid mode) does a real-time HeadObject at play
 * time: if the audio file is in the Intelligent-Tiering Archive Access tier,
 * a restore is initiated (idempotent) and the response is
 * 202 { status: 'restoring' } with an ETA. The cached Book.audioAvailability
 * column is for badges only and self-heals here on every play attempt —
 * a stale cache can never hand the client a URL that 403s.
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
      select: { id: true, audioUrl: true, audioAvailability: true },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    if (!book.audioUrl) {
      return NextResponse.json({ error: 'Book has no audio file' }, { status: 400 });
    }

    // Real-time archive check (production/hybrid only — local files never
    // archive). One cheap HeadObject per play tap; never trust the cache here.
    if (isS3Enabled()) {
      const { archived } = await getArchiveState(book.audioUrl);

      if (archived) {
        // Restore may or may not already be in flight — initiateRestore is
        // idempotent for both cases and records/reuses the DB request.
        const restoreRequest = await initiateRestore(
          { id: book.id, audioUrl: book.audioUrl },
          auth.user.id
        );
        return NextResponse.json(
          {
            status: 'restoring',
            message:
              'This audiobook is being restored from archive. It will be ready in 3-5 hours.',
            bookId: book.id,
            requestedAt: restoreRequest.requestedAt.toISOString(),
            estimatedCompletion: estimatedCompletion(restoreRequest.requestedAt),
          },
          { status: 202 }
        );
      }

      // Available — self-heal a stale cached state before presigning.
      if (book.audioAvailability !== AVAILABILITY.AVAILABLE) {
        await setBookAvailability(book.id, AVAILABILITY.AVAILABLE);
      }
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
