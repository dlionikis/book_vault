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
 * // Note: transformBook is async (generates presigned URLs in production)
 * const transformedBooks = await Promise.all(books.map(transformBook));
 * ```
 */

import { Prisma } from '@/lib/generated/prisma/client';
import { getCoverUrl, getAudioUrl } from './media';
import { htmlToMarkdown } from './html-to-markdown';

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
 * Note: This function is async because it generates presigned S3 URLs in production.
 *
 * @param book - Book from Prisma with standard includes
 * @returns Promise resolving to transformed book matching OpenAPI Book schema
 */
/**
 * Book.audioAvailability (DB, SCREAMING_CASE) → API archiveStatus (lowercase).
 * Derived purely from the row already in hand — zero extra queries (a per-book
 * lookup here would be an N+1 on every 100-book list page).
 */
const ARCHIVE_STATUS_MAP: Record<string, 'available' | 'archived' | 'restoring'> = {
  AVAILABLE: 'available',
  ARCHIVED: 'archived',
  RESTORING: 'restoring',
};

export async function transformBook(book: BookWithIncludes) {
  // Generate URLs (async in production for presigned S3 URLs)
  const [coverUrl, audioUrl] = await Promise.all([
    getCoverUrl(book.coverUrl),
    getAudioUrl(book.audioUrl),
  ]);

  return {
    id: book.id,
    asin: book.asin,
    title: book.title,
    archiveStatus: ARCHIVE_STATUS_MAP[book.audioAvailability] ?? 'available',
    publisherSummary: htmlToMarkdown(book.publisherSummary),
    runtimeMinutes: book.runtimeMinutes,
    releaseDate: book.releaseDate ? book.releaseDate.toISOString().split('T')[0] : null,
    publisher: book.publisher,
    coverUrl,
    audioUrl,
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
    metadata: book.metadata as Record<string, unknown> | undefined,
  };
}

/**
 * Transform a library book (from UserListBook join table) to API response format
 *
 * Extends the standard book transformation with library-specific fields like addedAt.
 * Used by GET /api/library endpoint to return books with their library metadata.
 *
 * @param libraryBook - UserListBook entry with nested book and addedAt timestamp
 * @returns Promise resolving to transformed book with addedAt field
 *
 * @example
 * const libraryBooks = await prisma.userListBook.findMany({
 *   include: { book: { include: BOOK_INCLUDE } }
 * });
 * const transformed = await Promise.all(libraryBooks.map(transformLibraryBook));
 */
export async function transformLibraryBook(libraryBook: { book: BookWithIncludes; addedAt: Date }) {
  const transformedBook = await transformBook(libraryBook.book);
  return {
    ...transformedBook,
    addedAt: libraryBook.addedAt.toISOString(),
  };
}
