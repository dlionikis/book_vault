import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
import { buildPagination, parsePagination } from '@/lib/api-utils';
import { logger, withLogging } from '@/lib/logger';
import type { components } from '@/lib/api-types';

type Book = components['schemas']['Book'];

/**
 * GET /api/books
 *
 * List all audiobooks with pagination. Returns books with full metadata
 * including authors, narrators, series, and categories.
 *
 * Auth: Required
 * Query Parameters:
 *   - page: Page number (default: 1)
 *   - limit: Items per page (default: 20, max: 100)
 *   - sort: Sort order - "title" (default; only supported value)
 *
 * For author/narrator/category/series-scoped listings use the entity detail
 * endpoints (/api/authors/{id} etc.), which return their books.
 *
 * Returns: { books: Book[], pagination: { currentPage, totalPages, totalItems, itemsPerPage } }
 * Errors: 401 if not authenticated, 500 on server error
 *
 * @example
 * // Fetch page 2 with 10 books per page
 * fetch('/api/books?page=2&limit=10')
 */
export const GET = withLogging(async (request: NextRequest) => {
  // Check both auth methods
  const auth = await requireUser(request);
  if (auth.error) return auth.error;
  try {
    // parsePagination caps limit at 100 — an uncapped limit lets a single
    // request pull the entire library with all relations
    const searchParams = request.nextUrl.searchParams;
    const { page, limit, skip } = parsePagination(
      searchParams.get('page'),
      searchParams.get('limit')
    );

    // Fetch books with their relationships
    const [books, total] = await Promise.all([
      prisma.book.findMany({
        skip,
        take: limit,
        include: BOOK_INCLUDE,
        orderBy: { title: 'asc' },
      }),
      prisma.book.count(),
    ]);

    // Transform the response to match OpenAPI Book schema
    // Note: transformBook is async (generates presigned URLs in production)
    const transformedBooks: Book[] = await Promise.all(books.map(transformBook));

    return NextResponse.json({
      books: transformedBooks,
      pagination: buildPagination(page, limit, total),
    });
  } catch (error) {
    logger.error('Error fetching books', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch books' }, { status: 500 });
  }
});
