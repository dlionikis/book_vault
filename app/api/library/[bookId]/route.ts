import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';
import { logger, withLogging } from '@/lib/logger';

// DELETE /api/library/[bookId] - Remove book from library
export const DELETE = withLogging(async (request: NextRequest, context) => {
  const { bookId: bookIdParam } = await context!.params;
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const bookId = normalizeUuid(bookIdParam);
    if (!bookId) {
      return NextResponse.json({ error: 'Invalid book ID' }, { status: 400 });
    }

    // Get user's library
    const library = await prisma.userList.findFirst({
      where: {
        userId: user.id,
        name: 'My Library',
      },
    });

    if (!library) {
      return NextResponse.json({ error: 'Library not found' }, { status: 404 });
    }

    // Remove book from library
    await prisma.userListBook.deleteMany({
      where: {
        listId: library.id,
        bookId,
      },
    });

    return NextResponse.json({ message: 'Book removed from library' });
  } catch (error) {
    logger.error('Error removing from library', { error: String(error) });
    return NextResponse.json({ error: 'Failed to remove book from library' }, { status: 500 });
  }
});
