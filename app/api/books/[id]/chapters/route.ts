import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { extractChapters } from '@/lib/audio-metadata';
import { getAbsoluteMediaPath } from '@/lib/media';
import path from 'path';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    // Get book with audioUrl
    const book = await prisma.book.findUnique({
      where: { id: params.id },
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
        chapters: book.chapters,
        source: 'database',
      });
    }

    // Otherwise, extract from audio file and save to database
    const mediaPath = getAbsoluteMediaPath();
    const audioFilePath = path.join(mediaPath, book.audioUrl);

    // Extract chapters from audio file
    const extractedChapters = await extractChapters(audioFilePath);

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
          chapters: existingChapters,
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
      chapters: savedChapters,
      source: 'extracted',
    });
  } catch (error) {
    console.error('Error getting chapters:', error);
    return NextResponse.json(
      {
        error: 'Failed to get chapters',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}
