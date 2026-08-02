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

// ---------------------------------------------------------------------------
// Category tree
// ---------------------------------------------------------------------------

/**
 * A node in the browsable category tree.
 *
 * Two counts, because they answer different questions and the difference is the
 * whole reason the tree is navigable:
 *
 *   - `bookCount` — books tagged with THIS category. What its own page lists.
 *   - `totalBookCount` — distinct books anywhere in its subtree. What the card
 *     advertises.
 *
 * 15 of 16 root categories in production have `bookCount: 0` — Audible's ladders
 * make them pure containers — so a card showing the direct count would read "0
 * books" on nearly every top-level entry point and look broken.
 */
export interface CategoryNode {
  id: string;
  name: string;
  level: number;
  parentId: string | null;
  /** Books tagged with this exact category. */
  bookCount: number;
  /** Distinct visible books in this category or any descendant. */
  totalBookCount: number;
  /** Immediate children that have visible books somewhere beneath them. */
  children: CategoryNode[];
}

/** A category plus the ancestors needed to render a breadcrumb. */
export interface CategoryTreeNode extends CategoryNode {
  /** Root-to-immediate-parent, for breadcrumbs. Empty at the root. */
  ancestors: Array<{ id: string; name: string }>;
}

interface RawCategory {
  id: string;
  name: string;
  level: number;
  parentId: string | null;
}

/**
 * Every category, plus which visible books each one is directly tagged with.
 *
 * Two flat queries regardless of tree depth: the category table (~150 rows) and
 * the visible book_categories links (~1.9k rows). Both are small enough to shape
 * in memory, which avoids either a recursive CTE (unavailable through Prisma's
 * typed API) or a per-node query walking down the tree.
 */
async function loadCategoryGraph(): Promise<{
  categories: RawCategory[];
  directBookIds: Map<string, string[]>;
}> {
  const [categories, links] = await Promise.all([
    prisma.category.findMany({
      select: { id: true, name: true, level: true, parentId: true },
      orderBy: { name: 'asc' },
    }),
    prisma.bookCategory.findMany({
      where: { book: VISIBLE_BOOK_WHERE },
      select: { categoryId: true, bookId: true },
    }),
  ]);

  const directBookIds = new Map<string, string[]>();
  for (const link of links) {
    const existing = directBookIds.get(link.categoryId);
    if (existing) existing.push(link.bookId);
    else directBookIds.set(link.categoryId, [link.bookId]);
  }

  return { categories, directBookIds };
}

/**
 * Children of each category, and the ids of the roots.
 *
 * A `parentId` pointing at a row that no longer exists would otherwise orphan a
 * whole subtree out of the UI, so those are treated as roots.
 */
function indexByParent(categories: RawCategory[]) {
  const ids = new Set(categories.map((c) => c.id));
  const childrenOf = new Map<string | null, RawCategory[]>();

  for (const category of categories) {
    const parentId = category.parentId && ids.has(category.parentId) ? category.parentId : null;
    const siblings = childrenOf.get(parentId);
    if (siblings) siblings.push(category);
    else childrenOf.set(parentId, [category]);
  }

  return childrenOf;
}

/**
 * Build the subtree rooted at `category`, pruning branches with no visible books.
 *
 * Returns null when nothing in the subtree is visible, which is what removes the
 * dead ladder nodes (the importer links only leaf categories, so intermediate
 * rows have no books of their own and are worth showing only as containers for
 * something that does).
 *
 * Rollups union book *ids* rather than summing counts: a book tagged both
 * "Fantasy" and "Fantasy > Epic" must count once under Fantasy, and summing
 * would double it. The returned set is the caller's to consume — it is reused as
 * the accumulator up the tree to avoid copying at every level.
 */
function buildSubtree(
  category: RawCategory,
  childrenOf: Map<string | null, RawCategory[]>,
  directBookIds: Map<string, string[]>,
  visiting: Set<string>
): { node: CategoryNode; bookIds: Set<string> } | null {
  // A parent_id cycle would otherwise recurse until the stack blows.
  if (visiting.has(category.id)) return null;
  visiting.add(category.id);

  const direct = directBookIds.get(category.id) ?? [];
  const subtreeBookIds = new Set(direct);
  const children: CategoryNode[] = [];

  for (const child of childrenOf.get(category.id) ?? []) {
    const built = buildSubtree(child, childrenOf, directBookIds, visiting);
    if (!built) continue;
    children.push(built.node);
    for (const bookId of built.bookIds) subtreeBookIds.add(bookId);
  }

  visiting.delete(category.id);

  if (subtreeBookIds.size === 0) return null;

  // Sort siblings here rather than leaning on the query's `orderBy`: that only
  // orders the flat row set, and nothing guarantees it survives the grouping
  // above. Sorting explicitly keeps sibling order stable at every depth.
  children.sort((a, b) => a.name.localeCompare(b.name));

  return {
    node: {
      id: category.id,
      name: category.name,
      level: category.level,
      parentId: category.parentId,
      bookCount: direct.length,
      totalBookCount: subtreeBookIds.size,
      children,
    },
    bookIds: subtreeBookIds,
  };
}

/**
 * The top level of the browsable category tree: roots and their descendants,
 * with empty branches pruned.
 */
export async function getCategoryTree(): Promise<CategoryNode[]> {
  const { categories, directBookIds } = await loadCategoryGraph();
  const childrenOf = indexByParent(categories);

  return (childrenOf.get(null) ?? [])
    .map((root) => buildSubtree(root, childrenOf, directBookIds, new Set())?.node)
    .filter((node): node is CategoryNode => node !== undefined)
    .sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * One category's immediate children (pruned) plus its ancestor breadcrumb.
 *
 * Returns null if the category doesn't exist. A category that exists but has no
 * visible books anywhere is still returned — its own page should render an empty
 * state rather than a 404, since the row is real.
 */
export async function getCategoryTreeNode(categoryId: string): Promise<CategoryTreeNode | null> {
  const { categories, directBookIds } = await loadCategoryGraph();
  const byId = new Map(categories.map((c) => [c.id, c]));
  const category = byId.get(categoryId);
  if (!category) return null;

  const childrenOf = indexByParent(categories);
  const built = buildSubtree(category, childrenOf, directBookIds, new Set());

  const ancestors: Array<{ id: string; name: string }> = [];
  const seen = new Set<string>([categoryId]);
  let current = category.parentId;
  while (current && !seen.has(current)) {
    seen.add(current);
    const node = byId.get(current);
    if (!node) break;
    ancestors.unshift({ id: node.id, name: node.name });
    current = node.parentId;
  }

  const direct = directBookIds.get(categoryId) ?? [];

  return {
    id: category.id,
    name: category.name,
    level: category.level,
    parentId: category.parentId,
    bookCount: direct.length,
    totalBookCount: built?.node.totalBookCount ?? 0,
    children: built?.node.children ?? [],
    ancestors,
  };
}
