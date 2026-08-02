import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid, isValidUuid } from '@/lib/api-utils';
import { VISIBLE_BOOK_WHERE } from '@/lib/book-transformer';

// POST /api/library/series/[seriesId] - Add all books in series to library
export async function POST(request: NextRequest, props: { params: Promise<{ seriesId: string }> }) {
  const params = await props.params;
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const seriesId = normalizeUuid(params.seriesId);
    if (!isValidUuid(seriesId)) {
      return NextResponse.json({ error: 'Invalid series ID format' }, { status: 400 });
    }

    // Get all books in the series. Hidden books are skipped so "add series to
    // library" cannot pull in titles the user can't see anywhere else.
    const seriesBooks = await prisma.bookSeries.findMany({
      where: {
        seriesId,
        book: VISIBLE_BOOK_WHERE,
      },
      select: {
        bookId: true,
      },
    });

    if (seriesBooks.length === 0) {
      return NextResponse.json({ error: 'Series not found or has no books' }, { status: 404 });
    }

    // Get or create user's library
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

    // Add all books to library (skip duplicates)
    let addedCount = 0;
    for (const { bookId } of seriesBooks) {
      const existing = await prisma.userListBook.findUnique({
        where: {
          listId_bookId: {
            listId: library.id,
            bookId,
          },
        },
      });

      if (!existing) {
        await prisma.userListBook.create({
          data: {
            listId: library.id,
            bookId,
          },
        });
        addedCount++;
      }
    }

    return NextResponse.json({
      message: `Added ${addedCount} book${addedCount !== 1 ? 's' : ''} to library`,
      added: addedCount,
      total: seriesBooks.length,
    });
  } catch (error) {
    logger.error('Error adding series to library', { error: String(error) });
    return NextResponse.json({ error: 'Failed to add series to library' }, { status: 500 });
  }
}

// DELETE /api/library/series/[seriesId] - Remove all books in series from library
export async function DELETE(
  request: NextRequest,
  props: { params: Promise<{ seriesId: string }> }
) {
  const params = await props.params;
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const seriesId = normalizeUuid(params.seriesId);
    if (!isValidUuid(seriesId)) {
      return NextResponse.json({ error: 'Invalid series ID format' }, { status: 400 });
    }

    // Get all books in the series
    const seriesBooks = await prisma.bookSeries.findMany({
      where: {
        seriesId,
      },
      select: {
        bookId: true,
      },
    });

    if (seriesBooks.length === 0) {
      return NextResponse.json({ error: 'Series not found or has no books' }, { status: 404 });
    }

    // Get user's library
    const library = await prisma.userList.findFirst({
      where: {
        userId: user.id,
        name: 'My Library',
      },
    });

    if (!library) {
      return NextResponse.json({ message: 'No books removed (library empty)' }, { status: 200 });
    }

    // Remove all books from library
    const bookIds = seriesBooks.map((b) => b.bookId);
    const result = await prisma.userListBook.deleteMany({
      where: {
        listId: library.id,
        bookId: {
          in: bookIds,
        },
      },
    });

    return NextResponse.json({
      message: `Removed ${result.count} book${result.count !== 1 ? 's' : ''} from library`,
      removed: result.count,
    });
  } catch (error) {
    logger.error('Error removing series from library', { error: String(error) });
    return NextResponse.json({ error: 'Failed to remove series from library' }, { status: 500 });
  }
}
