import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { parsePagination } from '@/lib/api-utils';
import {
  getBrowseEntities,
  getCategoryParentPaths,
  getCategoryTree,
} from '@/lib/queries/browse-entities';

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

    // `roots=true` returns the top of the hierarchy for drill-down browsing. The
    // flat default is kept for existing clients: dropping it would silently make
    // most categories unreachable for anything that doesn't drill down yet.
    if (searchParams.get('roots') === 'true') {
      const roots = await getCategoryTree();

      return NextResponse.json({
        results: roots.map((root) => ({
          id: root.id,
          name: root.name,
          level: root.level,
          parentPath: [],
          bookCount: root.bookCount,
          totalBookCount: root.totalBookCount,
          hasChildren: root.children.length > 0,
        })),
        // The root list is short and returned whole, so pagination describes a
        // single page rather than slicing.
        pagination: {
          page: 1,
          limit: roots.length,
          total: roots.length,
          pages: 1,
        },
      });
    }

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
