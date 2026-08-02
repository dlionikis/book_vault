import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { parsePagination } from '@/lib/api-utils';
import { VISIBLE_BOOK_WHERE } from '@/lib/book-transformer';

export async function GET(request: NextRequest) {
  // Check both auth methods
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  try {
    const searchParams = request.nextUrl.searchParams;
    const { page, limit, skip } = parsePagination(
      searchParams.get('page'),
      searchParams.get('limit')
    );

    // An author is listed only while they still have a visible book, and the
    // count matches what the detail page will actually show — an unfiltered
    // _count reads "12 books" next to a page listing 11.
    const visibleBooksWhere = { some: { book: VISIBLE_BOOK_WHERE } };

    const [authors, total] = await Promise.all([
      prisma.author.findMany({
        where: { books: visibleBooksWhere },
        skip,
        take: limit,
        include: {
          _count: {
            select: {
              books: { where: { book: VISIBLE_BOOK_WHERE } },
            },
          },
        },
        orderBy: {
          name: 'asc',
        },
      }),
      prisma.author.count({ where: { books: visibleBooksWhere } }),
    ]);

    // Transform to include book count
    const transformedAuthors = authors.map((author) => ({
      id: author.id,
      name: author.name,
      asin: author.asin,
      bookCount: author._count.books,
    }));

    return NextResponse.json({
      results: transformedAuthors,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    logger.error('Error fetching authors', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch authors' }, { status: 500 });
  }
}
