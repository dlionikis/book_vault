import { NextRequest, NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

const prisma = new PrismaClient();

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    const narrator = await prisma.narrator.findUnique({
      where: { id: params.id },
    });

    if (!narrator) {
      return NextResponse.json({ error: 'Narrator not found' }, { status: 404 });
    }

    // Get books by this narrator with their relationships
    const [bookNarratorEntries, total] = await Promise.all([
      prisma.bookNarrator.findMany({
        where: { narratorId: params.id },
        skip,
        take: limit,
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
        orderBy: {
          book: {
            title: 'asc',
          },
        },
      }),
      prisma.bookNarrator.count({
        where: { narratorId: params.id },
      }),
    ]);

    // Transform book data to include full URLs and proper structure
    const booksWithUrls = bookNarratorEntries.map((entry) => {
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

    const totalPages = Math.ceil(total / limit);

    return NextResponse.json({
      ...narrator,
      books: booksWithUrls,
      pagination: {
        page,
        limit,
        total,
        pages: totalPages,
      },
    });
  } catch (error) {
    console.error('Error fetching narrator:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
