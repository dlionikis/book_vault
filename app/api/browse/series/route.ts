import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { parsePagination, buildPagination } from '@/lib/api-utils';
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

    // A series is listed only while it still has a visible book — hiding every
    // book in a series removes the series from Browse rather than leaving an
    // empty "0 books" entry behind.
    const visibleBooksWhere = { some: { book: VISIBLE_BOOK_WHERE } };

    const [series, total] = await Promise.all([
      prisma.series.findMany({
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
          title: 'asc',
        },
      }),
      prisma.series.count({ where: { books: visibleBooksWhere } }),
    ]);

    // Transform to include book count
    const transformedSeries = series.map((s) => ({
      id: s.id,
      title: s.title,
      asin: s.asin,
      bookCount: s._count.books,
    }));

    return NextResponse.json({
      results: transformedSeries,
      pagination: buildPagination(page, limit, total),
    });
  } catch (error) {
    logger.error('Error fetching series', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch series' }, { status: 500 });
  }
}
