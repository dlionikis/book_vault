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

    const [narrators, total] = await Promise.all([
      prisma.narrator.findMany({
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
      prisma.narrator.count(),
    ]);

    // Transform to include book count
    const transformedNarrators = narrators.map((narrator) => ({
      id: narrator.id,
      name: narrator.name,
      asin: narrator.asin,
      bookCount: narrator._count.books,
    }));

    return NextResponse.json({
      results: transformedNarrators,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    logger.error('Error fetching narrators', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch narrators' }, { status: 500 });
  }
}
