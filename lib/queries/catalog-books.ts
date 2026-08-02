/**
 * Catalog + personal-library book listings.
 *
 * Shared by /api/books and the home page, and by /api/library and the library
 * page. Both pages previously queried Prisma with no visibility filter, so
 * hidden books stayed on the catalog grid and in users' libraries.
 *
 * See docs/hidden-books.md.
 */

import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, VISIBLE_BOOK_WHERE, transformBook } from '@/lib/book-transformer';
import { Book } from '@/lib/types';

export interface CatalogBooksResult {
  books: Book[];
  total: number;
}

/** One page of the visible catalog, ordered by title. */
export async function getCatalogBooks(opts: {
  skip: number;
  limit: number;
}): Promise<CatalogBooksResult> {
  const [books, total] = await Promise.all([
    prisma.book.findMany({
      where: { ...VISIBLE_BOOK_WHERE },
      skip: opts.skip,
      take: opts.limit,
      include: BOOK_INCLUDE,
      orderBy: { title: 'asc' },
    }),
    // Counted with the same filter — a bare count() reports hidden books and
    // leaves the last page of the grid short.
    prisma.book.count({ where: { ...VISIBLE_BOOK_WHERE } }),
  ]);

  return {
    books: await Promise.all(books.map((book) => transformBook(book))),
    total,
  };
}

/** A user's library rows (visible books only), newest addition first. */
export async function getLibraryListBooks(userId: string) {
  const library = await prisma.userList.findFirst({
    where: { userId, name: 'My Library' },
  });

  if (!library) return { library: null, listBooks: [] };

  // Hiding a book removes it from the shelf but does NOT delete the
  // user_list_books row — clearing hidden_at brings it back untouched.
  const listBooks = await prisma.userListBook.findMany({
    where: { listId: library.id, book: VISIBLE_BOOK_WHERE },
    include: { book: { include: BOOK_INCLUDE } },
    orderBy: { addedAt: 'desc' },
  });

  return { library, listBooks };
}
