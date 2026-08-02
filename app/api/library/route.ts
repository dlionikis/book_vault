import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';
import { BOOK_INCLUDE, VISIBLE_BOOK_WHERE, transformLibraryBook } from '@/lib/book-transformer';
import { logger, withLogging } from '@/lib/logger';

/**
 * GET /api/library
 *
 * Get all books in user's personal library with full metadata and progress. Returns books
 * with addedAt timestamp from when they were added to library. Creates "My Library" list
 * if it doesn't exist.
 *
 * Auth: Required
 * Query Parameters: None
 *
 * Returns: { books: LibraryBook[], total: number }
 * Errors: 401 if not authenticated, 500 on server error
 *
 * @example
 * fetch('/api/library')
 */
export const GET = withLogging(async (request: NextRequest) => {
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    // Get or create user's library list
    const library = await prisma.userList.findFirst({
      where: {
        userId: user.id,
        name: 'My Library',
      },
    });

    if (!library) {
      return NextResponse.json({ books: [], total: 0 });
    }

    // Get books in library with full details
    // A hidden book stays in the list row but is not returned — unhiding it
    // puts it back in the user's library untouched.
    const libraryBooks = await prisma.userListBook.findMany({
      where: {
        listId: library.id,
        book: VISIBLE_BOOK_WHERE,
      },
      include: {
        book: {
          include: BOOK_INCLUDE,
        },
      },
      orderBy: {
        addedAt: 'desc',
      },
    });

    // Transform using centralized library book transformer
    // Note: transformLibraryBook is async (generates presigned URLs in production)
    const books = await Promise.all(libraryBooks.map(transformLibraryBook));

    return NextResponse.json({ books, total: books.length });
  } catch (error) {
    logger.error('Error fetching library', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch library' }, { status: 500 });
  }
});

/**
 * POST /api/library
 * \n * Add a book to user's personal library. Creates \"My Library\" list if it doesn't exist.\n * Prevents duplicate additions. Records timestamp of when book was added.\n * \n * Auth: Required\n * Request Body: { bookId: string }\n * \n * Returns: { success: true, addedAt: string }\n * Errors: 400 if bookId missing/invalid or book already in library, 401 if not authenticated, 404 if book not found, 500 on error\n * \n * @example\n * fetch('/api/library', {\n *   method: 'POST',\n *   headers: { 'Content-Type': 'application/json' },\n *   body: JSON.stringify({ bookId: 'abc-123' })\n * })\n */
export const POST = withLogging(async (request: NextRequest) => {
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const body = await request.json();
    const bookId = normalizeUuid(body.bookId);

    if (!bookId) {
      return NextResponse.json({ error: 'Invalid book ID' }, { status: 400 });
    }

    // Get or create user's library list
    let library = await prisma.userList.findFirst({
      where: {
        userId: user.id,
        name: 'My Library',
      },
    });

    if (!library) {
      library = await prisma.userList.create({
        data: {
          userId: user.id,
          name: 'My Library',
          description: 'Your personal audiobook library',
        },
      });
    }

    // Check if book already in library
    const existing = await prisma.userListBook.findUnique({
      where: {
        listId_bookId: {
          listId: library.id,
          bookId,
        },
      },
    });

    if (existing) {
      return NextResponse.json({ message: 'Book already in library' }, { status: 200 });
    }

    // Add book to library
    await prisma.userListBook.create({
      data: {
        listId: library.id,
        bookId,
      },
    });

    return NextResponse.json({ message: 'Book added to library' }, { status: 201 });
  } catch (error) {
    logger.error('Error adding to library', { error: String(error) });
    return NextResponse.json({ error: 'Failed to add book to library' }, { status: 500 });
  }
});
