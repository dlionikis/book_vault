import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { getCoverUrl, getAudioUrl } from '@/lib/media';
import { parseBookFields, parsePagination } from '@/lib/api-utils';

export async function GET(request: NextRequest) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const searchParams = request.nextUrl.searchParams;
    const query = searchParams.get('q') || '';
    const fieldsParam = searchParams.get('fields');
    const { page, limit, skip } = parsePagination(
      searchParams.get('page'),
      searchParams.get('limit')
    );

    if (!query) {
      return NextResponse.json({ error: 'Search query is required' }, { status: 400 });
    }

    // Parse field filtering
    const select = parseBookFields(fieldsParam);

    // Build where clause for search
    const whereClause = {
      OR: [
        {
          title: {
            contains: query,
            mode: 'insensitive' as const,
          },
        },
        {
          description: {
            contains: query,
            mode: 'insensitive' as const,
          },
        },
        {
          publisherSummary: {
            contains: query,
            mode: 'insensitive' as const,
          },
        },
        {
          authors: {
            some: {
              author: {
                name: {
                  contains: query,
                  mode: 'insensitive' as const,
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
                  mode: 'insensitive' as const,
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
                  mode: 'insensitive' as const,
                },
              },
            },
          },
        },
      ],
    };

    // Search across multiple fields
    const [books, total] = await Promise.all([
      select
        ? prisma.book.findMany({
            where: whereClause,
            skip,
            take: limit,
            select,
            orderBy: {
              title: 'asc',
            },
          })
        : prisma.book.findMany({
            where: whereClause,
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
              categories: {
                include: {
                  category: true,
                },
              },
            },
            orderBy: {
              title: 'asc',
            },
          }),
      prisma.book.count({
        where: whereClause,
      }),
    ]);

    // Transform the response
    const transformedBooks = select
      ? // If using field filtering, return books as-is (with selected fields only)
        books.map((book) => {
          const result: Record<string, unknown> = {};
          for (const [key, value] of Object.entries(book)) {
            if (key === 'coverUrl') {
              result[key] = getCoverUrl(value as string | null);
            } else if (key === 'audioUrl') {
              result[key] = getAudioUrl(value as string | null);
            } else {
              result[key] = value;
            }
          }
          return result;
        })
      : // Otherwise, return full transformed books
        books.map((book) => {
          // Type assertion for the full book with includes
          const fullBook = book as typeof book & {
            authors: Array<{ author: { id: string; name: string; asin: string | null } }>;
            narrators: Array<{ narrator: { id: string; name: string; asin: string | null } }>;
            series: Array<{
              series: { id: string; title: string; asin: string | null };
              sequence: string | null;
            }>;
            categories: Array<{ category: { id: string; name: string } }>;
          };

          return {
            id: fullBook.id,
            asin: fullBook.asin,
            title: fullBook.title,
            publisherSummary: fullBook.publisherSummary,
            runtimeMinutes: fullBook.runtimeMinutes,
            releaseDate: fullBook.releaseDate,
            publisher: fullBook.publisher,
            coverUrl: getCoverUrl(fullBook.coverUrl),
            audioUrl: getAudioUrl(fullBook.audioUrl),
            authors: fullBook.authors.map((ba) => ({
              id: ba.author.id,
              name: ba.author.name,
              asin: ba.author.asin,
            })),
            narrators: fullBook.narrators.map((bn) => ({
              id: bn.narrator.id,
              name: bn.narrator.name,
              asin: bn.narrator.asin,
            })),
            series: fullBook.series.map((bs) => ({
              id: bs.series.id,
              title: bs.series.title,
              asin: bs.series.asin,
              sequence: bs.sequence,
            })),
            categories: fullBook.categories.map((bc) => ({
              id: bc.category.id,
              name: bc.category.name,
            })),
            createdAt: fullBook.createdAt,
          };
        });

    return NextResponse.json({
      results: transformedBooks,
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
  }
}
