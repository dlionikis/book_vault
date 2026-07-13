import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { parsePagination } from '@/lib/api-utils';

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

    const [authors, total] = await Promise.all([
      prisma.author.findMany({
        skip,
        take: limit,
        include: {
          _count: {
            select: {
              books: true,
            },
          },
        },
        orderBy: {
          name: 'asc',
        },
      }),
      prisma.author.count(),
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
