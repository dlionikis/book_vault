/**
 * Book Transformer
 *
 * Centralized book transformation logic to ensure consistency across all API endpoints.
 * This prevents bugs where fields are added to some endpoints but not others.
 *
 * Usage:
 * ```typescript
 * import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
 *
 * const books = await prisma.book.findMany({
 *   include: BOOK_INCLUDE,
 * });
 *
 * const transformedBooks = books.map(transformBook);
 * ```
 */

import { Prisma } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from './media';

/**
 * Standard book include for Prisma queries
 * Use this in all queries that return books to ensure consistency
 */
export const BOOK_INCLUDE = {
  authors: {
    include: {
      author: true,
    },
  },
  narrators: {
    include: {
      narrator: true,
    },
  },
  series: {
    include: {
      series: true,
    },
  },
  categories: {
    include: {
      category: true,
    },
  },
} as const;

/**
 * Book type with all standard includes
 * Use this type for functions that accept books with full relationships
 */
export type BookWithIncludes = Prisma.BookGetPayload<{
  include: typeof BOOK_INCLUDE;
}>;

/**
 * Transform a Prisma book to API response format (OpenAPI compliant)
 *
 * This ensures all endpoints return books with the same structure,
 * preventing issues where fields are missing from some responses.
 *
 * @param book - Book from Prisma with standard includes
 * @returns Transformed book matching OpenAPI Book schema
 */
export function transformBook(book: BookWithIncludes) {
  return {
    id: book.id,
    asin: book.asin,
    title: book.title,
    description: book.description,
    runtimeMinutes: book.runtimeMinutes,
    releaseDate: book.releaseDate ? book.releaseDate.toISOString().split('T')[0] : null,
    publisher: book.publisher,
    coverUrl: getCoverUrl(book.coverUrl),
    audioUrl: getAudioUrl(book.audioUrl),
    authors: book.authors.map((ba) => ({
      id: ba.author.id,
      name: ba.author.name,
      asin: ba.author.asin,
    })),
    narrators: book.narrators.map((bn) => ({
      id: bn.narrator.id,
      name: bn.narrator.name,
      asin: bn.narrator.asin,
    })),
    series: book.series.map((bs) => ({
      id: bs.series.id,
      title: bs.series.title,
      asin: bs.series.asin,
      sequence: bs.sequence,
    })),
    categories: book.categories.map((bc) => ({
      id: bc.category.id,
      name: bc.category.name,
    })),
  };
}

/**
 * Transform a library book (from UserListBook join table) to API response format
 *
 * Extends the standard book transformation with library-specific fields like addedAt.
 * Used by GET /api/library endpoint to return books with their library metadata.
 *
 * @param libraryBook - UserListBook entry with nested book and addedAt timestamp
 * @returns Transformed book with addedAt field
 *
 * @example
 * const libraryBooks = await prisma.userListBook.findMany({
 *   include: { book: { include: BOOK_INCLUDE } }
 * });
 * const transformed = libraryBooks.map(transformLibraryBook);
 */
export function transformLibraryBook(libraryBook: { book: BookWithIncludes; addedAt: Date }) {
  return {
    ...transformBook(libraryBook.book),
    addedAt: libraryBook.addedAt.toISOString(),
  };
}
