import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';
import { BOOK_INCLUDE, transformLibraryBook } from '@/lib/book-transformer';

// GET /api/library - Get user's library books
export async function GET(request: NextRequest) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

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
    const libraryBooks = await prisma.userListBook.findMany({
      where: {
        listId: library.id,
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
    const books = libraryBooks.map(transformLibraryBook);

    return NextResponse.json({ books, total: books.length });
  } catch (error) {
    console.error('Error fetching library:', error);
    return NextResponse.json({ error: 'Failed to fetch library' }, { status: 500 });
  }
}

// POST /api/library - Add book to library
export async function POST(request: NextRequest) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

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
    console.error('Error adding to library:', error);
    return NextResponse.json({ error: 'Failed to add book to library' }, { status: 500 });
  }
}
