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

    const [categories, total, ancestry] = await Promise.all([
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
        },
        orderBy: {
          name: 'asc',
        },
      }),
      prisma.category.count({ where: { books: visibleBooksWhere } }),
      // Category names are unique only per-parent, so the same name legitimately
      // appears under several ancestries (e.g. "Action & Adventure" under both
      // "Literature & Fiction" and "SF&F > Fantasy"). The immediate parent alone
      // doesn't always disambiguate them, so we resolve the full chain. The table
      // is small (~150 rows) and parents may sit outside the current page, so we
      // pull the whole id->parent map rather than issuing per-row lookups.
      prisma.category.findMany({ select: { id: true, name: true, parentId: true } }),
    ]);

    const byId = new Map(ancestry.map((c) => [c.id, c]));

    // Root-to-immediate-parent names. Guards against a cycle in parent_id, which
    // would otherwise spin forever.
    const parentPathOf = (categoryId: string): string[] => {
      const path: string[] = [];
      const seen = new Set<string>([categoryId]);
      let current = byId.get(categoryId)?.parentId ?? null;

      while (current && !seen.has(current)) {
        seen.add(current);
        const node = byId.get(current);
        if (!node) break;
        path.unshift(node.name);
        current = node.parentId;
      }

      return path;
    };

    // Transform to include book count, level and ancestry (OpenAPI compliant)
    const transformedCategories = categories.map((category) => ({
      id: category.id,
      name: category.name,
      level: category.level,
      parentPath: parentPathOf(category.id),
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
