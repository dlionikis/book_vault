import { NextRequest, NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    // Fetch books with their relationships
    const [books, total] = await Promise.all([
      prisma.book.findMany({
        skip,
        take: limit,
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
        orderBy: {
          title: 'asc',
        },
      }),
      prisma.book.count(),
    ]);

    // Transform the response to be more user-friendly
    const transformedBooks = books.map(book => ({
      id: book.id,
      asin: book.asin,
      title: book.title,
      publisherSummary: book.publisherSummary,
      runtimeMinutes: book.runtimeMinutes,
      releaseDate: book.releaseDate,
      publisher: book.publisher,
      coverUrl: book.coverUrl,
      audioUrl: book.audioUrl,
      authors: book.authors.map(ba => ({
        id: ba.author.id,
        name: ba.author.name,
        asin: ba.author.asin,
      })),
      narrators: book.narrators.map(bn => ({
        id: bn.narrator.id,
        name: bn.narrator.name,
        asin: bn.narrator.asin,
      })),
      series: book.series.map(bs => ({
        id: bs.series.id,
        title: bs.series.title,
        asin: bs.series.asin,
        sequence: bs.sequence,
      })),
      createdAt: book.createdAt,
    }));

    return NextResponse.json({
      books: transformedBooks,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('Error fetching books:', error);
    return NextResponse.json(
      { error: 'Failed to fetch books' },
      { status: 500 }
    );
  } finally {
    await prisma.$disconnect();
  }
}
