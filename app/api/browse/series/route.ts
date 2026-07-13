import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { parsePagination, buildPagination } from '@/lib/api-utils';

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

    const [series, total] = await Promise.all([
      prisma.series.findMany({
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
          title: 'asc',
        },
      }),
      prisma.series.count(),
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
