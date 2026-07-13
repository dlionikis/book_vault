import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { requireAdmin } from '@/lib/admin-auth';
import { prisma } from '@/lib/db';
import { extractChaptersBestMethod, isFFProbeAvailable } from '@/lib/audio-metadata';
import { getAbsoluteMediaPath } from '@/lib/media';
import { isS3Enabled, generatePresignedUrl } from '@/lib/s3';
import { normalizeUuid } from '@/lib/api-utils';
import path from 'path';

/**
 * GET /api/books/[id]/chapters
 *
 * Get chapter list for an audiobook with titles and timestamps. Returns chapters from database
 * if they exist, otherwise extracts them from audio file metadata (.metadata.json or FFProbe)
 * on-the-fly. Supports both local filesystem and S3 storage.
 *
 * Auth: Required
 * Path Parameters:
 *   - id: Book UUID or ASIN
 *
 * Returns: { chapters: [{ chapterNumber, title, startTimeSeconds, endTimeSeconds }], source: 'database'|'metadata'|'ffprobe' }
 * Errors: 400 if invalid ID, 401 if not authenticated, 404 if book or audio not found
 *
 * @example
 * fetch('/api/books/abc-123/chapters')
 */
export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // Check both auth methods
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  const id = normalizeUuid(params.id);
  if (!id) {
    return NextResponse.json({ error: 'Invalid book ID' }, { status: 400 });
  }

  try {
    // Get book with audioUrl
    const book = await prisma.book.findUnique({
      where: { id },
      select: {
        id: true,
        audioUrl: true,
        chapters: {
          orderBy: { chapterNumber: 'asc' },
        },
      },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    if (!book.audioUrl) {
      return NextResponse.json({ error: 'No audio file for this book' }, { status: 404 });
    }

    // If chapters already exist in database, return them
    if (book.chapters.length > 0) {
      return NextResponse.json({
        chapters: book.chapters.map((ch) => ({
          id: ch.id,
          title: ch.title,
          startTime: ch.startTime,
          endTime: ch.endTime,
          duration: ch.duration,
          index: ch.chapterNumber,
        })),
        source: 'database',
      });
    }

    // Check if ffprobe is available
    const ffprobeAvailable = await isFFProbeAvailable();
    if (!ffprobeAvailable) {
      return NextResponse.json({
        chapters: [],
        source: 'unavailable',
        message: 'Chapter extraction requires ffprobe (install FFmpeg)',
      });
    }

    // Determine the audio source path for ffprobe
    // In production with S3: use presigned URL (ffprobe can read from HTTP)
    // In development: use local file path
    let audioSource: string;
    if (isS3Enabled()) {
      // Generate a presigned URL for ffprobe to read from S3
      // ffprobe only reads the header/metadata, not the entire file
      audioSource = await generatePresignedUrl(book.audioUrl, 300); // 5 min expiry
    } else {
      // Local development: use filesystem path
      const mediaPath = getAbsoluteMediaPath();
      audioSource = path.join(mediaPath, book.audioUrl);
    }

    // Extract chapters from audio file using the best available method
    // (prefers Audible metadata.json over ffprobe for more accurate timing)
    let extractedChapters;
    try {
      extractedChapters = await extractChaptersBestMethod(audioSource);
    } catch (extractError) {
      // If extraction fails, return empty chapters instead of 500 error
      console.warn('Chapter extraction failed:', extractError);
      return NextResponse.json({
        chapters: [],
        source: 'error',
        message: 'Failed to extract chapters from audio file',
      });
    }

    if (extractedChapters.length === 0) {
      return NextResponse.json({
        chapters: [],
        source: 'none',
        message: 'No chapters found in audio file',
      });
    }

    // Save chapters to database (with duplicate check in case of race condition)
    try {
      await prisma.$transaction(
        extractedChapters.map((chapter) =>
          prisma.chapter.create({
            data: {
              bookId: book.id,
              chapterNumber: chapter.chapterNumber,
              title: chapter.title,
              startTime: chapter.startTime,
              endTime: chapter.endTime,
              duration: chapter.duration,
            },
          })
        )
      );
    } catch (dbError: any) {
      // If we hit a unique constraint error, chapters were already created by another request
      if (dbError.code === 'P2002') {
        const existingChapters = await prisma.chapter.findMany({
          where: { bookId: book.id },
          orderBy: { chapterNumber: 'asc' },
        });
        return NextResponse.json({
          chapters: existingChapters.map((ch) => ({
            id: ch.id,
            title: ch.title,
            startTime: ch.startTime,
            endTime: ch.endTime,
            duration: ch.duration,
            index: ch.chapterNumber,
          })),
          source: 'database',
        });
      }
      throw dbError;
    }

    // Fetch the saved chapters
    const savedChapters = await prisma.chapter.findMany({
      where: { bookId: book.id },
      orderBy: { chapterNumber: 'asc' },
    });

    return NextResponse.json({
      chapters: savedChapters.map((ch) => ({
        id: ch.id,
        title: ch.title,
        startTime: ch.startTime,
        endTime: ch.endTime,
        duration: ch.duration,
        index: ch.chapterNumber,
      })),
      source: 'extracted',
    });
  } catch (error) {
    logger.error('Error getting chapters', { error: String(error) });
    return NextResponse.json({ error: 'Failed to get chapters' }, { status: 500 });
  }
}

/**
 * POST /api/books/[id]/chapters
 * Re-extract chapters for a book (deletes existing chapters and extracts fresh ones)
 * This is useful when chapter timing needs to be corrected.
 *
 * Auth: Admin only - this deletes and rewrites the shared Chapter table.
 */
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const { error } = await requireAdmin(request);
  if (error) {
    return error;
  }

  const id = normalizeUuid(params.id);
  if (!id) {
    return NextResponse.json({ error: 'Invalid book ID' }, { status: 400 });
  }

  try {
    // Get book with audioUrl
    const book = await prisma.book.findUnique({
      where: { id },
      select: {
        id: true,
        audioUrl: true,
        title: true,
      },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    if (!book.audioUrl) {
      return NextResponse.json({ error: 'No audio file for this book' }, { status: 404 });
    }

    // Delete existing chapters for this book
    const deletedCount = await prisma.chapter.deleteMany({
      where: { bookId: book.id },
    });

    // Determine the audio source path
    let audioSource: string;
    if (isS3Enabled()) {
      audioSource = await generatePresignedUrl(book.audioUrl, 300);
    } else {
      const mediaPath = getAbsoluteMediaPath();
      audioSource = path.join(mediaPath, book.audioUrl);
    }

    // Extract chapters using the best available method
    let extractedChapters;
    try {
      extractedChapters = await extractChaptersBestMethod(audioSource);
    } catch (extractError) {
      console.warn('Chapter extraction failed:', extractError);
      return NextResponse.json({
        chapters: [],
        source: 'error',
        message: 'Failed to extract chapters from audio file',
        deletedCount: deletedCount.count,
      });
    }

    if (extractedChapters.length === 0) {
      return NextResponse.json({
        chapters: [],
        source: 'none',
        message: 'No chapters found in audio file',
        deletedCount: deletedCount.count,
      });
    }

    // Save new chapters to database
    await prisma.$transaction(
      extractedChapters.map((chapter) =>
        prisma.chapter.create({
          data: {
            bookId: book.id,
            chapterNumber: chapter.chapterNumber,
            title: chapter.title,
            startTime: chapter.startTime,
            endTime: chapter.endTime,
            duration: chapter.duration,
          },
        })
      )
    );

    // Fetch the saved chapters
    const savedChapters = await prisma.chapter.findMany({
      where: { bookId: book.id },
      orderBy: { chapterNumber: 'asc' },
    });

    return NextResponse.json({
      chapters: savedChapters.map((ch) => ({
        id: ch.id,
        title: ch.title,
        startTime: ch.startTime,
        endTime: ch.endTime,
        duration: ch.duration,
        index: ch.chapterNumber,
      })),
      source: 're-extracted',
      deletedCount: deletedCount.count,
      message: `Re-extracted ${savedChapters.length} chapters (deleted ${deletedCount.count} old chapters)`,
    });
  } catch (error) {
    logger.error('Error re-extracting chapters', { error: String(error) });
    return NextResponse.json(
      {
        error: 'Failed to re-extract chapters',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}
