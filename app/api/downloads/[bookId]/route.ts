import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { isS3Enabled, generatePresignedUrl, getS3ObjectMetadata } from '@/lib/s3';
import { checkDownloadLimit } from '@/lib/rate-limit';

export async function POST(
  request: NextRequest,
  { params }: { params: { bookId: string } }
) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    const { bookId } = params;

    // Parse request body
    const body = await request.json();
    const { deviceId } = body;

    // Verify book exists
    const book = await prisma.book.findUnique({
      where: { id: bookId },
      select: {
        id: true,
        audioUrl: true,
      },
    });

    if (!book) {
      return NextResponse.json(
        { error: 'Book not found' },
        { status: 404 }
      );
    }

    if (!book.audioUrl) {
      return NextResponse.json(
        { error: 'Book has no audio file' },
        { status: 400 }
      );
    }

    // Check eligibility (for MVP: always eligible, future: check library, quota)
    // For now, just verify book exists (already done above)

    // Check rate limit (max 10 downloads per day)
    const withinLimit = await checkDownloadLimit(user.id);
    if (!withinLimit) {
      return NextResponse.json(
        { error: 'Download limit exceeded (10/day)' },
        { status: 429 }
      );
    }

    // Check if S3 is configured
    if (!isS3Enabled()) {
      return NextResponse.json(
        { error: 'Downloads require S3 configuration' },
        { status: 501 }
      );
    }

    // Generate pre-signed URL
    // audioUrl format: "book-folder/filename.mp3" (S3 key)
    const expiresIn = 3600; // 1 hour
    const downloadUrl = await generatePresignedUrl(book.audioUrl, expiresIn);

    // Get file size
    const metadata = await getS3ObjectMetadata(book.audioUrl);

    // Record download in database
    await prisma.userDownload.create({
      data: {
        userId: user.id,
        bookId: book.id,
        deviceId: deviceId || null,
      },
    });

    // Calculate expiry time
    const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();

    return NextResponse.json({
      downloadUrl,
      expiresAt,
      fileSize: metadata.size,
    });
  } catch (error) {
    console.error('Download URL generation error:', error);
    return NextResponse.json(
      { error: 'Failed to generate download URL' },
      { status: 500 }
    );
  }
}
