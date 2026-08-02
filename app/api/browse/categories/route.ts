import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { parsePagination } from '@/lib/api-utils';
import { getBrowseEntities, getCategoryParentPaths } from '@/lib/queries/browse-entities';

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

    // Shared with the /browse/categories page — visibility filtering, the
    // matching bookCount, and ancestry resolution all live in one place.
    const [{ entities, total }, parentPaths] = await Promise.all([
      getBrowseEntities('category', { skip, limit }),
      getCategoryParentPaths(),
    ]);

    // Transform to include book count, level and ancestry (OpenAPI compliant)
    const transformedCategories = entities.map((entity) => ({
      id: entity.id,
      name: entity.label,
      level: entity.level ?? 0,
      parentPath: parentPaths.get(entity.id) ?? [],
      bookCount: entity.bookCount,
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
