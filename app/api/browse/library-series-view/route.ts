import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { parsePagination } from '@/lib/api-utils';
import { getCatalogSeriesView } from '@/lib/catalog-series-view';

export async function GET(request: NextRequest) {
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  try {
    const searchParams = request.nextUrl.searchParams;
    const { page, limit } = parsePagination(searchParams.get('page'), searchParams.get('limit'));

    const result = await getCatalogSeriesView(page, limit, {
      scope: 'library',
      userId: auth.user.id,
    });

    return NextResponse.json(result);
  } catch (error) {
    logger.error('Error fetching library series view', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch library series view' }, { status: 500 });
  }
}
