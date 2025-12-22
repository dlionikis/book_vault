import { NextRequest, NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

const prisma = new PrismaClient();

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const author = await prisma.author.findUnique({
      where: { id: params.id },
    });

    if (!author) {
      return NextResponse.json(
        { error: 'Author not found' },
        { status: 404 }
      );
    }

    // Get books by this author with their relationships
    const bookAuthorEntries = await prisma.bookAuthor.findMany({
      where: { authorId: params.id },
      include: {
        book: {
          include: {
            authors: {
              include: {
                author: true
              }
            },
            narrators: {
              include: {
                narrator: true
              }
            },
            series: {
              include: {
                series: true,
              }
            },
          }
        }
      },
    });

    // Transform book data to include full URLs and proper structure
    const booksWithUrls = bookAuthorEntries.map(entry => {
      const book = entry.book;
      return {
        id: book.id,
        asin: book.asin,
        title: book.title,
        description: book.description,
        publisherSummary: book.publisherSummary,
        runtimeMinutes: book.runtimeMinutes,
        releaseDate: book.releaseDate,
        publisher: book.publisher,
        coverUrl: getCoverUrl(book.coverUrl),
        audioUrl: getAudioUrl(book.audioUrl),
        authors: book.authors.map(ba => ba.author),
        narrators: book.narrators.map(bn => bn.narrator),
        series: book.series.map(bs => ({
          id: bs.series.id,
          title: bs.series.title,
          asin: bs.series.asin,
          sequence: bs.sequence,
        })),
        createdAt: book.createdAt.toISOString(),
      };
    });

    return NextResponse.json({
      ...author,
      books: booksWithUrls
    });
  } catch (error) {
    console.error('Error fetching author:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
