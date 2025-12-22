import { NextRequest, NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

const prisma = new PrismaClient();

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const query = searchParams.get('q') || '';
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    if (!query) {
      return NextResponse.json({ error: 'Search query is required' }, { status: 400 });
    }

    // Search across multiple fields
    const [books, total] = await Promise.all([
      prisma.book.findMany({
        where: {
          OR: [
            {
              title: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              description: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              publisherSummary: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              authors: {
                some: {
                  author: {
                    name: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
            {
              narrators: {
                some: {
                  narrator: {
                    name: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
            {
              series: {
                some: {
                  series: {
                    title: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
          ],
        },
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
      prisma.book.count({
        where: {
          OR: [
            {
              title: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              description: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              publisherSummary: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              authors: {
                some: {
                  author: {
                    name: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
            {
              narrators: {
                some: {
                  narrator: {
                    name: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
            {
              series: {
                some: {
                  series: {
                    title: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
          ],
        },
      }),
    ]);

    // Transform the response
    const transformedBooks = books.map((book) => ({
      id: book.id,
      asin: book.asin,
      title: book.title,
      publisherSummary: book.publisherSummary,
      runtimeMinutes: book.runtimeMinutes,
      releaseDate: book.releaseDate,
      publisher: book.publisher,
      coverUrl: getCoverUrl(book.coverUrl),
      audioUrl: getAudioUrl(book.audioUrl),
      authors: book.authors.map((ba) => ({
        id: ba.author.id,
        name: ba.author.name,
        asin: ba.author.asin,
      })),
      narrators: book.narrators.map((bn) => ({
        id: bn.narrator.id,
        name: bn.narrator.name,
        asin: bn.narrator.asin,
      })),
      series: book.series.map((bs) => ({
        id: bs.series.id,
        title: bs.series.title,
        asin: bs.series.asin,
        sequence: bs.sequence,
      })),
      createdAt: book.createdAt,
    }));

    return NextResponse.json({
      query,
      books: transformedBooks,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('Error searching books:', error);
    return NextResponse.json({ error: 'Failed to search books' }, { status: 500 });
  } finally {
    await prisma.$disconnect();
  }
}
