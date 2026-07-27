/**
 * Combined Series-mode feed: series (with book count + derived cover) and
 * standalone books (books with no series), merged into one
 * alphabetically-sorted, paginated list. Backs the Books/Series toggle on
 * both the Catalog ("All Books") and Library pages/screens.
 *
 * See docs/archive/completed-plans/series-view-toggle-implementation.md for the full spec —
 * this implements the "Pagination algorithm" section verbatim.
 */

import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook, transformLibraryBook } from '@/lib/book-transformer';
import { getCoverUrl } from '@/lib/media';
import { buildPagination, type PaginationResult } from '@/lib/api-utils';

export interface CatalogSeriesViewItem {
  series?: Awaited<ReturnType<typeof transformSeriesItem>>;
  book?:
    Awaited<ReturnType<typeof transformBook>> | Awaited<ReturnType<typeof transformLibraryBook>>;
}

export interface CatalogSeriesViewResult {
  results: CatalogSeriesViewItem[];
  pagination: PaginationResult;
}

interface SortKeyRow {
  id: string;
  title: string;
  type: 'series' | 'book';
  /** Library scope only: when this book was added to the user's library. */
  addedAt?: Date;
}

/**
 * Scope determines which series/books are eligible:
 * - 'catalog': every series and every standalone book in the library.
 * - 'library': only series with at least one book owned by `userId`, and
 *   only standalone books owned by `userId`. Series items carry `ownedCount`.
 */
type ScopeOptions = { scope: 'catalog' } | { scope: 'library'; userId: string };

export async function getCatalogSeriesView(
  page: number,
  limit: number,
  scopeOptions: ScopeOptions
): Promise<CatalogSeriesViewResult> {
  const skip = (page - 1) * limit;

  // Step 1: lightweight sort-key lists for both kinds, in parallel.
  const [seriesKeys, bookKeys] =
    scopeOptions.scope === 'library'
      ? await getLibrarySortKeys(scopeOptions.userId)
      : await getCatalogSortKeys();

  // Step 2: merge-sort by title (both inputs are already title-sorted).
  const merged: SortKeyRow[] = mergeByTitle(seriesKeys, bookKeys);

  // Step 3: slice to the requested page.
  const pageSlice = merged.slice(skip, skip + limit);
  const pageSeriesIds = pageSlice.filter((r) => r.type === 'series').map((r) => r.id);
  const pageBookIds = pageSlice.filter((r) => r.type === 'book').map((r) => r.id);

  // Step 4: fetch full records for only this page's ids.
  const [seriesRecords, bookRecords] = await Promise.all([
    pageSeriesIds.length > 0
      ? prisma.series.findMany({
          where: { id: { in: pageSeriesIds } },
          include: { _count: { select: { books: true } } },
        })
      : Promise.resolve([]),
    pageBookIds.length > 0
      ? prisma.book.findMany({ where: { id: { in: pageBookIds } }, include: BOOK_INCLUDE })
      : Promise.resolve([]),
  ]);

  // Step 5: derive each series' cover from its lowest-sequence book with a
  // non-null coverUrl.
  const seriesCovers =
    pageSeriesIds.length > 0
      ? await getSeriesCoverPaths(pageSeriesIds)
      : new Map<string, string | null>();

  // Library scope: owned count per series in this page.
  const ownedCounts =
    scopeOptions.scope === 'library' && pageSeriesIds.length > 0
      ? await getOwnedCounts(pageSeriesIds, scopeOptions.userId)
      : new Map<string, number>();

  const seriesById = new Map(seriesRecords.map((s) => [s.id, s]));
  const bookById = new Map(bookRecords.map((b) => [b.id, b]));

  // Step 6: transform, re-assembling in step-3's order (WHERE id IN (...)
  // does not preserve input order).
  const results: CatalogSeriesViewItem[] = await Promise.all(
    pageSlice.map(async (row) => {
      if (row.type === 'series') {
        const series = seriesById.get(row.id);
        if (!series) return {};
        return {
          series: await transformSeriesItem(
            series,
            seriesCovers.get(row.id) ?? null,
            scopeOptions.scope === 'library' ? (ownedCounts.get(row.id) ?? 0) : undefined
          ),
        };
      }
      const book = bookById.get(row.id);
      if (!book) return {};
      if (scopeOptions.scope === 'library' && row.addedAt) {
        return { book: await transformLibraryBook({ book, addedAt: row.addedAt }) };
      }
      return { book: await transformBook(book) };
    })
  );

  // Step 7: total = merged list length (already computed, no extra query).
  return {
    results,
    pagination: buildPagination(page, limit, merged.length),
  };
}

async function getCatalogSortKeys(): Promise<[SortKeyRow[], SortKeyRow[]]> {
  const [series, books] = await Promise.all([
    prisma.series.findMany({ select: { id: true, title: true }, orderBy: { title: 'asc' } }),
    prisma.book.findMany({
      where: { series: { none: {} } },
      select: { id: true, title: true },
      orderBy: { title: 'asc' },
    }),
  ]);

  return [
    series.map((s) => ({ id: s.id, title: s.title, type: 'series' as const })),
    books.map((b) => ({ id: b.id, title: b.title, type: 'book' as const })),
  ];
}

async function getLibrarySortKeys(userId: string): Promise<[SortKeyRow[], SortKeyRow[]]> {
  const library = await prisma.userList.findFirst({
    where: { userId, name: 'My Library' },
  });

  if (!library) return [[], []];

  const [ownedSeriesIds, standaloneListBooks] = await Promise.all([
    prisma.bookSeries.findMany({
      where: { book: { listBooks: { some: { listId: library.id } } } },
      select: { seriesId: true },
      distinct: ['seriesId'],
    }),
    prisma.userListBook.findMany({
      where: { listId: library.id, book: { series: { none: {} } } },
      select: { bookId: true, addedAt: true, book: { select: { title: true } } },
      orderBy: { book: { title: 'asc' } },
    }),
  ]);

  const seriesIds = ownedSeriesIds.map((s) => s.seriesId);
  const series =
    seriesIds.length > 0
      ? await prisma.series.findMany({
          where: { id: { in: seriesIds } },
          select: { id: true, title: true },
          orderBy: { title: 'asc' },
        })
      : [];

  return [
    series.map((s) => ({ id: s.id, title: s.title, type: 'series' as const })),
    standaloneListBooks.map((lb) => ({
      id: lb.bookId,
      title: lb.book.title,
      type: 'book' as const,
      addedAt: lb.addedAt,
    })),
  ];
}

function mergeByTitle(seriesKeys: SortKeyRow[], bookKeys: SortKeyRow[]): SortKeyRow[] {
  return [...seriesKeys, ...bookKeys].sort((a, b) => a.title.localeCompare(b.title));
}

async function getSeriesCoverPaths(seriesIds: string[]): Promise<Map<string, string | null>> {
  const rows = await prisma.bookSeries.findMany({
    where: { seriesId: { in: seriesIds } },
    orderBy: [{ sequence: 'asc' }],
    include: { book: { select: { coverUrl: true } } },
  });

  const covers = new Map<string, string | null>();
  for (const row of rows) {
    if (covers.has(row.seriesId)) continue;
    if (row.book.coverUrl) covers.set(row.seriesId, row.book.coverUrl);
  }
  // Ensure every requested series has an entry (null if no cover found).
  for (const id of seriesIds) {
    if (!covers.has(id)) covers.set(id, null);
  }
  return covers;
}

async function getOwnedCounts(seriesIds: string[], userId: string): Promise<Map<string, number>> {
  const library = await prisma.userList.findFirst({ where: { userId, name: 'My Library' } });
  if (!library) return new Map();

  const rows = await prisma.bookSeries.findMany({
    where: {
      seriesId: { in: seriesIds },
      book: { listBooks: { some: { listId: library.id } } },
    },
    select: { seriesId: true },
  });

  const counts = new Map<string, number>();
  for (const row of rows) {
    counts.set(row.seriesId, (counts.get(row.seriesId) ?? 0) + 1);
  }
  return counts;
}

async function transformSeriesItem(
  series: { id: string; title: string; asin: string | null; _count: { books: number } },
  coverPath: string | null,
  ownedCount: number | undefined
) {
  return {
    id: series.id,
    title: series.title,
    asin: series.asin,
    bookCount: series._count.books,
    coverUrl: await getCoverUrl(coverPath),
    ...(ownedCount !== undefined ? { ownedCount } : {}),
  };
}
