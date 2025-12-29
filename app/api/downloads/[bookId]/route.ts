import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { isS3Enabled, generatePresignedUrl, getS3ObjectMetadata } from '@/lib/s3';
import { checkDownloadLimit } from '@/lib/rate-limit';
import { normalizeUuid } from '@/lib/api-utils';
import { getAbsoluteMediaPath } from '@/lib/media';
import { statSync } from 'fs';
import { join } from 'path';

export async function POST(request: NextRequest, { params }: { params: { bookId: string } }) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

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

    // Check rate limit (max 10 downloads per day)
    const withinLimit = await checkDownloadLimit(user.id);
    if (!withinLimit) {
      return NextResponse.json({ error: 'Download limit exceeded (10/day)' }, { status: 429 });
    }

    let downloadUrl: string;
    let fileSize: number;
    let expiresAt: string;

    if (isS3Enabled()) {
      // Production: Generate pre-signed S3 URL
      // audioUrl format: "book-folder/filename.mp3" (S3 key)
      const expiresIn = 3600; // 1 hour
      downloadUrl = await generatePresignedUrl(book.audioUrl, expiresIn);

      // Get file size from S3
      const metadata = await getS3ObjectMetadata(book.audioUrl);
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
    console.error('Download URL generation error:', error);
    return NextResponse.json({ error: 'Failed to generate download URL' }, { status: 500 });
  }
}
