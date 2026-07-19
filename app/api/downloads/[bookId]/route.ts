import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { isS3Enabled, generatePresignedUrl, getS3ObjectMetadata } from '@/lib/s3';
import { initiateRestore, estimatedCompletion } from '@/lib/restore';
import { checkDownloadLimit } from '@/lib/rate-limit';
import { normalizeUuid } from '@/lib/api-utils';
import { getAbsoluteMediaPath } from '@/lib/media';
import { statSync } from 'fs';
import { join } from 'path';

export async function POST(request: NextRequest, props: { params: Promise<{ bookId: string }> }) {
  const params = await props.params;
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const { bookId } = params;
    const normalizedBookId = normalizeUuid(bookId) as string;

    // Parse request body
    const body = await request.json();
    const { deviceId } = body;

    // Verify book exists
    const book = await prisma.book.findUnique({
      where: { id: normalizedBookId },
      select: {
        id: true,
        audioUrl: true,
      },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    if (!book.audioUrl) {
      return NextResponse.json({ error: 'Book has no audio file' }, { status: 400 });
    }

    // Check eligibility (for MVP: always eligible, future: check library, quota)
    // For now, just verify book exists (already done above)

    // Check rate limit (max 50 downloads per day)
    const withinLimit = await checkDownloadLimit(user.id);
    if (!withinLimit) {
      return NextResponse.json({ error: 'Download limit exceeded (50/day)' }, { status: 429 });
    }

    let downloadUrl: string;
    let fileSize: number;
    let expiresAt: string;

    if (isS3Enabled()) {
      // Production: HeadObject first — an archived file would 403 mid-download
      // if we handed out a presigned URL. If it's in the Archive Access tier,
      // initiate a restore (idempotent) and return the same 202 shape as the
      // stream endpoint; the client retries after the restore completes.
      const metadata = await getS3ObjectMetadata(book.audioUrl);

      if (metadata.archiveStatus) {
        const restoreRequest = await initiateRestore(
          { id: book.id, audioUrl: book.audioUrl },
          user.id
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

      // Available: generate pre-signed S3 URL
      // audioUrl format: "book-folder/filename.mp3" (S3 key)
      const expiresIn = 3600; // 1 hour
      downloadUrl = await generatePresignedUrl(book.audioUrl, expiresIn);
      fileSize = metadata.size;

      // Calculate expiry time
      expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();
    } else {
      // Development: Use local audio streaming endpoint
      // audioUrl is stored as relative path (e.g., "Book Title [ASIN]/filename.mp3")
      const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
      const encodedPath = book.audioUrl.split('/').map(encodeURIComponent).join('/');
      downloadUrl = `${baseUrl}/api/audio/${encodedPath}`;

      // Get file size from local filesystem
      const mediaPath = getAbsoluteMediaPath();
      const localPath = join(mediaPath, book.audioUrl);
      try {
        const stat = statSync(localPath);
        fileSize = stat.size;
      } catch {
        return NextResponse.json({ error: 'Audio file not found on disk' }, { status: 404 });
      }

      // Local URLs don't expire, but set a far-future date for consistency
      expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(); // 24 hours
    }

    // Record download in database
    await prisma.userDownload.create({
      data: {
        userId: user.id,
        bookId: book.id,
        deviceId: deviceId || null,
      },
    });

    return NextResponse.json({
      downloadUrl,
      expiresAt,
      fileSize,
    });
  } catch (error) {
    logger.error('Download URL generation error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to generate download URL' }, { status: 500 });
  }
}
