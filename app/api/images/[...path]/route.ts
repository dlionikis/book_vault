import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs/promises';
import path from 'path';
import { getAbsoluteMediaPath, validateMediaPath } from '@/lib/media';

export async function GET(request: NextRequest, { params }: { params: { path: string[] } }) {
  try {
    // Reconstruct the file path
    const mediaDir = getAbsoluteMediaPath();
    const filePath = path.join(mediaDir, ...params.path);

    // Security: ensure the path is within media directory
    if (!validateMediaPath(filePath)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 403 });
    }

    // Check if file exists
    try {
      await fs.access(filePath);
    } catch {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    // Read the file
    const fileBuffer = await fs.readFile(filePath);

    // Determine content type based on extension
    const ext = path.extname(filePath).toLowerCase();
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
