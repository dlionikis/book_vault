import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs/promises';
import path from 'path';
import { getAbsoluteMediaPath, validateMediaPath } from '@/lib/media';
import { isS3Enabled, streamS3Object } from '@/lib/s3';

export async function GET(request: NextRequest, { params }: { params: { path: string[] } }) {
  try {
    const filePath = params.path.join('/');

    // Use S3 in production if configured
    if (isS3Enabled()) {
      try {
        const { stream, contentType, contentLength } = await streamS3Object(filePath);

        return new NextResponse(stream as any, {
          headers: {
            'Content-Type': contentType,
            'Content-Length': contentLength.toString(),
            'Cache-Control': 'public, max-age=31536000, immutable',
          },
        });
      } catch (error: any) {
        console.error('Error streaming image from S3:', error);

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

    // Determine content type based on extension
    const ext = path.extname(localFilePath).toLowerCase();
    const contentType =
      ext === '.jpg' || ext === '.jpeg'
        ? 'image/jpeg'
        : ext === '.png'
          ? 'image/png'
          : 'application/octet-stream';

    // Return the image
    return new NextResponse(fileBuffer, {
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    });
  } catch (error) {
    console.error('Error serving image:', error);
    return NextResponse.json({ error: 'Failed to serve image' }, { status: 500 });
  }
}
