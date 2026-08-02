import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { parsePagination, buildPagination } from '@/lib/api-utils';
import { getBrowseEntities } from '@/lib/queries/browse-entities';

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

    // Shared with the /browse/seriess page — visibility filtering and the
    // matching bookCount live in one place.
    const { entities, total } = await getBrowseEntities('series', { skip, limit });

    const results = entities.map((entity) => ({
      id: entity.id,
      title: entity.label,
      asin: entity.asin,
      bookCount: entity.bookCount,
    }));

    return NextResponse.json({
      results,
      pagination: buildPagination(page, limit, total),
    });
  } catch (error) {
    logger.error('Error fetching series', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch series' }, { status: 500 });
  }
}
