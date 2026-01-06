import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
import { normalizeUuid } from '@/lib/api-utils';
import { withLogging } from '@/lib/logger';

/**
 * GET /api/books/[id]
 *
 * Get detailed information for a single audiobook including full metadata, nested relations
 * (authors, narrators, series, categories), and user-specific progress/library status if
 * authenticated. Optionally includes chapters with `?include=chapters` query parameter.
 *
 * Auth: Required
 * Path Parameters:
 *   - id: Book UUID or ASIN
 * Query Parameters:
 *   - include: Optional "chapters" to include chapter list
 *
 * Returns: Complete Book object with nested relations
 * Errors: 400 if invalid ID format, 401 if not authenticated, 404 if book not found
 *
 * @example
 * // Get book details
 * fetch('/api/books/abc-123-def')
 *
 * // Get book with chapters
 * fetch('/api/books/abc-123-def?include=chapters')
 */
export const GET = withLogging(async (request: NextRequest, context) => {
  const { id } = await context!.params;
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const bookId = normalizeUuid(id);
    if (!bookId) {
      return NextResponse.json({ error: 'Invalid book ID' }, { status: 400 });
    }

    // Check if chapters should be included
    const url = new URL(request.url);
    const includeChapters = url.searchParams.get('include') === 'chapters';

    const book = await prisma.book.findUnique({
      where: { id: bookId },
      include: {
        ...BOOK_INCLUDE,
        chapters: includeChapters
          ? {
              orderBy: {
                chapterNumber: 'asc',
              },
            }
          : false,
      },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    // Transform the response (OpenAPI compliant - only return spec-defined fields)
    // Note: transformBook is async (generates presigned URLs in production)
    const baseBook = await transformBook(book);
    const transformedBook = {
      ...baseBook,
      ...(includeChapters &&
        book.chapters && {
          chapters: book.chapters.map((chapter) => ({
            id: chapter.id,
            chapterNumber: chapter.chapterNumber,
            title: chapter.title,
            startTime: chapter.startTime,
            endTime: chapter.endTime,
            duration: chapter.duration,
          })),
        }),
    };

    const response = NextResponse.json(transformedBook);

    // Add caching headers when chapters are included
    if (includeChapters) {
      response.headers.set('Cache-Control', 'public, max-age=86400');
    }

    return response;
  } catch (error) {
    console.error('Error fetching book:', error);
    return NextResponse.json({ error: 'Failed to fetch book' }, { status: 500 });
  }
});
