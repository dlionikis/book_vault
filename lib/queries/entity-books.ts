/**
 * Entity-detail book queries (author / narrator / series / category).
 *
 * The single query path behind BOTH the API routes and the web pages for these
 * four entities. Before this existed the eight surfaces hand-rolled the same
 * Prisma call, which is how PR #157's visibility filter reached all four routes
 * and none of the four pages: the routes shared `handleEntityDetailWithBooks`,
 * the pages each had their own copy.
 *
 * Anything that changes which books a user may see belongs here, not in a
 * caller. See docs/hidden-books.md.
 */

import { Prisma } from '@/lib/generated/prisma/client';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, VISIBLE_BOOK_WHERE, transformBook } from '@/lib/book-transformer';
import { Book } from '@/lib/types';

/** Which entity's books to fetch. Maps to a join table + its FK column. */
export type EntityKind = 'author' | 'narrator' | 'series' | 'category';

interface EntitySpec {
  /** Join-table delegate, e.g. prisma.bookAuthor */
  joinTable: () => {
    findMany: (args: unknown) => Promise<Array<{ book: unknown }>>;
    count: (args: unknown) => Promise<number>;
  };
  /** FK column on the join table pointing at the entity */
  idField: string;
  /** Default ordering for the book list */
  orderBy: unknown;
}

/**
 * Series order by in-series sequence; everything else alphabetically by title.
 * These were already the orderings used by the routes and pages — keeping them
 * here means the two can't drift apart again.
 */
const SPECS: Record<EntityKind, EntitySpec> = {
  author: {
    joinTable: () => prisma.bookAuthor as never,
    idField: 'authorId',
    orderBy: { book: { title: 'asc' } },
  },
  narrator: {
    joinTable: () => prisma.bookNarrator as never,
    idField: 'narratorId',
    orderBy: { book: { title: 'asc' } },
  },
  series: {
    joinTable: () => prisma.bookSeries as never,
    idField: 'seriesId',
    orderBy: { sequence: 'asc' },
  },
  category: {
    joinTable: () => prisma.bookCategory as never,
    idField: 'categoryId',
    orderBy: { book: { title: 'asc' } },
  },
};

export interface EntityBooksPage {
  books: Book[];
  total: number;
}

/**
 * Fetch one page of an entity's *visible* books, plus the total that matches.
 *
 * The filter goes through the join table's `book` relation so hidden books drop
 * out of the page and the total together — an unfiltered count reads "12 books"
 * above a grid showing 11.
 *
 * @param extraCounts Optional named counts scoped to the same entity, evaluated
 *   over ALL pages (the series page needs a series-wide archived count for its
 *   restore button, which restores more than the current page).
 */
export async function getEntityBooksPage(
  kind: EntityKind,
  entityId: string,
  opts: { skip: number; limit: number; extraCounts?: Record<string, Prisma.BookWhereInput> }
): Promise<EntityBooksPage & { extraCounts: Record<string, number> }> {
  const spec = SPECS[kind];
  const table = spec.joinTable();
  const where = { [spec.idField]: entityId, book: VISIBLE_BOOK_WHERE };

  const extraEntries = Object.entries(opts.extraCounts ?? {});

  const [entries, total, ...extras] = await Promise.all([
    table.findMany({
      where,
      skip: opts.skip,
      take: opts.limit,
      include: { book: { include: BOOK_INCLUDE } },
      orderBy: spec.orderBy,
    }),
    table.count({ where }),
    // Extra counts inherit the visibility filter too: a hidden archived book
    // must not inflate a "restore N books" affordance the user can't see.
    ...extraEntries.map(([, bookWhere]) =>
      table.count({
        where: { [spec.idField]: entityId, book: { ...VISIBLE_BOOK_WHERE, ...bookWhere } },
      })
    ),
  ]);

  const books = await Promise.all(entries.map((entry) => transformBook(entry.book as never)));

  return {
    books,
    total,
    extraCounts: Object.fromEntries(extraEntries.map(([name], i) => [name, extras[i]])),
  };
}
