import { NextRequest, NextResponse } from 'next/server';
import { createReadStream, statSync } from 'fs';
import { join, resolve } from 'path';
import { getAbsoluteMediaPath, validateMediaPath } from '@/lib/media';

export async function GET(request: NextRequest, { params }: { params: { path: string[] } }) {
  try {
    // Build the file path from the media directory
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
    const range = request.headers.get('range');

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
    console.error('Error streaming audio:', error);
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
