import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import fs from 'fs/promises';
import path from 'path';
import { getAbsoluteMediaPath, validateMediaPath } from '@/lib/media';
import { isS3Enabled, streamS3Object } from '@/lib/s3';

// Only image content may be served from this route. Without this allowlist the
// route could stream any object in the media store (including audio files).
const ALLOWED_IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];

const CONTENT_TYPES: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

export async function GET(request: NextRequest, { params }: { params: { path: string[] } }) {
  try {
    // Authentication check - support both session cookies (web) and Bearer tokens (mobile)
    const auth = await requireUser(request);
    if (auth.error) return auth.error;

    const filePath = params.path.join('/');

    const ext = path.extname(filePath).toLowerCase();
    if (!ALLOWED_IMAGE_EXTENSIONS.includes(ext)) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    // Use S3 in production if configured
    if (isS3Enabled()) {
      try {
        const { stream, contentType, contentLength } = await streamS3Object(filePath);

        return new NextResponse(stream as any, {
          headers: {
            'Content-Type': contentType,
            'Content-Length': contentLength.toString(),
            'Cache-Control': 'private, max-age=31536000, immutable',
          },
        });
      } catch (error: any) {
        logger.error('Error streaming image from S3', { error: String(error) });

        // Handle S3-specific errors
        if (error.name === 'NoSuchKey' || error.name === 'NotFound') {
          return NextResponse.json({ error: 'File not found' }, { status: 404 });
        }

        // Re-throw for general error handling
        throw error;
      }
    }

    // Fall back to local filesystem (development)
    const mediaDir = getAbsoluteMediaPath();
    const localFilePath = path.join(mediaDir, ...params.path);

    // Security: ensure the path is within media directory
    if (!validateMediaPath(localFilePath)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 403 });
    }

    // Check if file exists
    try {
      await fs.access(localFilePath);
    } catch {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    // Read the file
    const fileBuffer = await fs.readFile(localFilePath);

    // Return the image
    return new NextResponse(fileBuffer, {
      headers: {
        'Content-Type': CONTENT_TYPES[ext] ?? 'application/octet-stream',
        'Cache-Control': 'private, max-age=31536000, immutable',
      },
    });
  } catch (error) {
    logger.error('Error serving image', { error: String(error) });
    return NextResponse.json({ error: 'Failed to serve image' }, { status: 500 });
  }
}
