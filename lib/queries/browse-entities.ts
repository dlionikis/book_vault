/**
 * Browse-by-entity listings (author / narrator / series / category).
 *
 * Shared by the /api/browse/* routes and the /browse/* pages. Two behaviours
 * that used to live only in the routes and are now guaranteed on both:
 *
 *   1. An entity is listed only while it still has a visible book, so hiding a
 *      whole series removes it instead of leaving an empty "0 books" row.
 *   2. `bookCount` counts visible books only — an unfiltered `_count` reads
 *      "12 books" beside a detail page listing 11.
 *
 * The pages additionally used to load every joined book row just to take
 * `.length` for the count; `_count` does it in SQL.
 *
 * See docs/hidden-books.md.
 */

import { prisma } from '@/lib/db';
import { VISIBLE_BOOK_WHERE } from '@/lib/book-transformer';

export type BrowseEntityKind = 'author' | 'narrator' | 'series' | 'category';

/** Only entities with at least one visible book. */
const VISIBLE_BOOKS_RELATION = { some: { book: VISIBLE_BOOK_WHERE } };

/** Count of visible books, for the `_count` aggregate. */
const VISIBLE_BOOKS_COUNT = { books: { where: { book: VISIBLE_BOOK_WHERE } } };

interface BrowseSpec {
  model: () => {
    findMany: (args: unknown) => Promise<Array<Record<string, unknown>>>;
    count: (args: unknown) => Promise<number>;
  };
  /** Column the list is sorted and labelled by (`name`, or `title` for series). */
  labelField: 'name' | 'title';
}

const SPECS: Record<BrowseEntityKind, BrowseSpec> = {
  author: { model: () => prisma.author as never, labelField: 'name' },
  narrator: { model: () => prisma.narrator as never, labelField: 'name' },
  series: { model: () => prisma.series as never, labelField: 'title' },
  category: { model: () => prisma.category as never, labelField: 'name' },
};

export interface BrowseEntity {
  id: string;
  /** `name` for author/narrator/category, `title` for series. */
  label: string;
  asin?: string | null;
  level?: number;
  bookCount: number;
}

export interface BrowseEntitiesResult {
  entities: BrowseEntity[];
  total: number;
}

/**
 * One page of browsable entities that still have visible books.
 *
 * Pass `limit: null` for the un-paginated variant the /browse/* pages render
 * (they show the whole list rather than paging it).
 */
export async function getBrowseEntities(
  kind: BrowseEntityKind,
  opts: { skip?: number; limit: number | null } = { limit: null }
): Promise<BrowseEntitiesResult> {
  const spec = SPECS[kind];
  const model = spec.model();
  const where = { books: VISIBLE_BOOKS_RELATION };

  const [rows, total] = await Promise.all([
    model.findMany({
      where,
      ...(opts.skip ? { skip: opts.skip } : {}),
      ...(opts.limit === null ? {} : { take: opts.limit }),
      include: { _count: { select: VISIBLE_BOOKS_COUNT } },
      orderBy: { [spec.labelField]: 'asc' },
    }),
    model.count({ where }),
  ]);

  const entities = rows.map((row) => {
    const counted = row as { _count: { books: number } } & Record<string, unknown>;
    return {
      id: row.id as string,
      label: row[spec.labelField] as string,
      asin: (row.asin as string | null | undefined) ?? null,
      ...(row.level === undefined ? {} : { level: row.level as number }),
      bookCount: counted._count.books,
    };
  });

  return { entities, total };
}

/**
 * Root-to-immediate-parent name chains for categories, keyed by category id.
 *
 * Category names are unique only per-parent, so the same name legitimately
 * appears under several ancestries ("Action & Adventure" sits under both
 * "Literature & Fiction" and "SF&F > Fantasy"). The immediate parent alone
 * doesn't always disambiguate them, so we resolve the full chain. The table is
 * small (~150 rows) and parents may sit outside the current page, so we pull the
 * whole id->parent map rather than issuing per-row lookups.
 */
export async function getCategoryParentPaths(): Promise<Map<string, string[]>> {
  const all = await prisma.category.findMany({
    select: { id: true, name: true, parentId: true },
  });
  const byId = new Map(all.map((c) => [c.id, c]));

  const pathOf = (categoryId: string): string[] => {
    const path: string[] = [];
    // Guards against a cycle in parent_id, which would otherwise spin forever.
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

  return new Map(all.map((c) => [c.id, pathOf(c.id)]));
}
