import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

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
      return NextResponse.json({ books: [] });
    }

    // Get books in library with full details
    const libraryBooks = await prisma.userListBook.findMany({
      where: {
        listId: library.id,
      },
      include: {
        book: {
          include: {
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
          },
        },
      },
      orderBy: {
        addedAt: 'desc',
      },
    });

    const books = libraryBooks.map((lb) => ({
      ...lb.book,
      // Flatten nested join table structures to match OpenAPI spec
      authors: lb.book.authors.map((ba) => ({
        id: ba.author.id,
        name: ba.author.name,
        asin: ba.author.asin,
      })),
      narrators: lb.book.narrators.map((bn) => ({
        id: bn.narrator.id,
        name: bn.narrator.name,
        asin: bn.narrator.asin,
      })),
      series: lb.book.series.map((bs) => ({
        id: bs.series.id,
        title: bs.series.title,
        asin: bs.series.asin,
        sequence: bs.sequence, // Preserve sequence from join table
      })),
      addedAt: lb.addedAt,
    }));

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

    const { bookId } = await request.json();

    if (!bookId) {
      return NextResponse.json({ error: 'Book ID is required' }, { status: 400 });
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
