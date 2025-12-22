import { NextRequest, NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

const prisma = new PrismaClient();

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const series = await prisma.series.findUnique({
      where: { id: params.id },
    });

    if (!series) {
      return NextResponse.json({ error: 'Series not found' }, { status: 404 });
    }

    // Get books in this series with their relationships
    const bookSeriesEntries = await prisma.bookSeries.findMany({
      where: { seriesId: params.id },
      include: {
        book: {
          include: {
            authors: {
              include: {
                author: true,
              },
            },
            narrators: {
              include: {
                narrator: true,
              },
            },
            series: {
              include: {
                series: true,
              },
            },
          },
        },
      },
      orderBy: [{ sequence: 'asc' }],
    });

    // Transform book data to include full URLs and proper structure
    const booksWithUrls = bookSeriesEntries.map((entry) => {
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
        authors: book.authors.map((ba) => ba.author),
        narrators: book.narrators.map((bn) => bn.narrator),
        series: book.series.map((bs) => ({
          id: bs.series.id,
          title: bs.series.title,
          asin: bs.series.asin,
          sequence: bs.sequence,
        })),
        createdAt: book.createdAt.toISOString(),
      };
    });

    return NextResponse.json({
      ...series,
      books: booksWithUrls,
    });
  } catch (error) {
    console.error('Error fetching series:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
