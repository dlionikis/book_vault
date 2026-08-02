/**
 * Book search.
 *
 * Shared by /api/search and the /search page. The page used to hold a verbatim
 * copy of this `where` minus the visibility filter, which is why hidden books
 * kept showing up in the web UI after PR #157 fixed the API.
 *
 * See docs/hidden-books.md.
 */

import { Prisma } from '@/lib/generated/prisma/client';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, VISIBLE_BOOK_WHERE, transformBook } from '@/lib/book-transformer';
import { Book } from '@/lib/types';

/**
 * Match a query against title, blurbs, and author/narrator/series names.
 *
 * The visibility filter sits BESIDE `OR` (implicitly AND-ed), never inside it —
 * as an OR branch, `hiddenAt: null` would *match* hidden books rather than
 * exclude them, which is the opposite of the intent and easy to get wrong.
 */
export function buildSearchWhere(query: string): Prisma.BookWhereInput {
  const contains = { contains: query, mode: 'insensitive' as const };

  return {
    ...VISIBLE_BOOK_WHERE,
    OR: [
      { title: contains },
      { description: contains },
      { publisherSummary: contains },
      { authors: { some: { author: { name: contains } } } },
      { narrators: { some: { narrator: { name: contains } } } },
      { series: { some: { series: { title: contains } } } },
    ],
  };
}

export interface SearchBooksResult {
  books: Book[];
  total: number;
}

/** One page of visible books matching `query`, plus the matching total. */
export async function searchBooks(
  query: string,
  opts: { skip: number; limit: number }
): Promise<SearchBooksResult> {
  const where = buildSearchWhere(query);

  const [books, total] = await Promise.all([
    prisma.book.findMany({
      where,
      skip: opts.skip,
      take: opts.limit,
      include: BOOK_INCLUDE,
      orderBy: { title: 'asc' },
    }),
    prisma.book.count({ where }),
  ]);

  return {
    books: await Promise.all(books.map((book) => transformBook(book))),
    total,
  };
}
