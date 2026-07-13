import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { createReadStream, statSync } from 'fs';
import { join } from 'path';
import { getAbsoluteMediaPath, validateMediaPath } from '@/lib/media';
import { isS3Enabled, streamS3ObjectWithRange, getS3ObjectMetadata } from '@/lib/s3';

export async function GET(request: NextRequest, { params }: { params: { path: string[] } }) {
  try {
    // Authentication check - support both session cookies (web) and Bearer tokens (mobile)
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const filePath = params.path.join('/');
    const range = request.headers.get('range');
    const userId = user.id;

    // Log range requests for monitoring (helpful for debugging iOS seeking issues)
    if (range) {
      // eslint-disable-next-line no-console
      console.log('Range request', { path: filePath, range, userId });
    }

    // Use S3 in production if configured
    if (isS3Enabled()) {
      try {
        // Get file metadata first for range validation
        const { size: fileSize } = await getS3ObjectMetadata(filePath);

        if (range) {
          // Parse range header (e.g., "bytes=0-1023")
          const parts = range.replace(/bytes=/, '').split('-');
          const start = parseInt(parts[0], 10);
          const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

          // Validate range
          if (start >= fileSize || end >= fileSize) {
            return NextResponse.json({ error: 'Range not satisfiable' }, { status: 416 });
          }

          // Stream with range
          const { stream, contentType, contentLength, totalSize } = await streamS3ObjectWithRange(
            filePath,
            { start, end }
          );

          return new NextResponse(stream as any, {
            status: 206, // Partial Content
            headers: {
              'Content-Range': `bytes ${start}-${end}/${totalSize}`,
              'Accept-Ranges': 'bytes',
              'Content-Length': contentLength.toString(),
              'Content-Type': contentType || getContentType(filePath),
            },
          });
        }

        // No range requested - stream full file
        const { stream, contentType, contentLength } = await streamS3ObjectWithRange(filePath);

        return new NextResponse(stream as any, {
          headers: {
            'Content-Type': contentType || getContentType(filePath),
            'Content-Length': contentLength.toString(),
            'Accept-Ranges': 'bytes',
          },
        });
      } catch (error: any) {
        logger.error('Error streaming audio from S3', { error: String(error) });

        // Handle S3-specific errors
        if (error.name === 'NoSuchKey' || error.name === 'NotFound') {
          return NextResponse.json({ error: 'File not found' }, { status: 404 });
        }

        // Re-throw for general error handling
        throw error;
      }
    }

    // Fall back to local filesystem (development)
    const mediaPath = getAbsoluteMediaPath();
    const requestedPath = join(mediaPath, ...params.path);

    // Security: Validate the path is within the media directory
    if (!validateMediaPath(requestedPath)) {
      return NextResponse.json({ error: 'Invalid file path' }, { status: 403 });
    }

    // Check if file exists
    let stat;
    try {
      stat = statSync(requestedPath);
    } catch (error) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    // Get range header for seeking support
    if (range) {
      // Parse range header (e.g., "bytes=0-1023")
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : stat.size - 1;

      // Validate range
      if (start >= stat.size || end >= stat.size) {
        return NextResponse.json({ error: 'Range not satisfiable' }, { status: 416 });
      }

      const chunksize = end - start + 1;
      const stream = createReadStream(requestedPath, { start, end });

      return new NextResponse(stream as any, {
        status: 206, // Partial Content
        headers: {
          'Content-Range': `bytes ${start}-${end}/${stat.size}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunksize.toString(),
          'Content-Type': getContentType(requestedPath),
        },
      });
    }

    // No range requested - stream full file
    const stream = createReadStream(requestedPath);
    return new NextResponse(stream as any, {
      headers: {
        'Content-Type': getContentType(requestedPath),
        'Content-Length': stat.size.toString(),
        'Accept-Ranges': 'bytes',
      },
    });
  } catch (error) {
    logger.error('Error streaming audio', { error: String(error) });
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

function getContentType(filePath: string): string {
  if (filePath.endsWith('.mp3')) {
    return 'audio/mpeg';
  } else if (filePath.endsWith('.m4b') || filePath.endsWith('.m4a')) {
    return 'audio/mp4';
  } else if (filePath.endsWith('.ogg')) {
    return 'audio/ogg';
  } else if (filePath.endsWith('.wav')) {
    return 'audio/wav';
  }
  return 'audio/mpeg'; // Default to mp3
}
