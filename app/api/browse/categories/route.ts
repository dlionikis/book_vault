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

    // Listed only while the category still has a visible book, with a matching
    // count — see the note in browse/authors.
    const visibleBooksWhere = { some: { book: VISIBLE_BOOK_WHERE } };

    const [categories, total] = await Promise.all([
      prisma.category.findMany({
        where: { books: visibleBooksWhere },
        skip,
        take: limit,
        include: {
          _count: {
            select: {
              books: { where: { book: VISIBLE_BOOK_WHERE } },
            },
          },
          parent: {
            select: {
              name: true,
            },
          },
        },
        orderBy: {
          name: 'asc',
        },
      }),
      prisma.category.count({ where: { books: visibleBooksWhere } }),
    ]);

    // Transform to include book count and level (OpenAPI compliant)
    const transformedCategories = categories.map((category) => ({
      id: category.id,
      name: category.name,
      level: category.level,
      bookCount: category._count.books,
    }));

    return NextResponse.json({
      results: transformedCategories,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    logger.error('Error fetching categories', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch categories' }, { status: 500 });
  }
}
