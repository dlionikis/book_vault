import { NextRequest, NextResponse } from 'next/server';
import { logger } from '@/lib/logger';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';

// Force dynamic rendering - this route uses headers() via requireUser (session lookup)
export const dynamic = 'force-dynamic';

// GET /api/library/check?bookId=xxx - Check if book is in library
export async function GET(request: NextRequest) {
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) {
      // Soft check: unauthenticated users get a 200 with inLibrary=false, not a 401
      return NextResponse.json({ inLibrary: false });
    }
    const user = auth.user;

    const bookId = normalizeUuid(request.nextUrl.searchParams.get('bookId'));
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
      return NextResponse.json({ inLibrary: false });
    }

    // Check if book is in library
    const inLibrary = await prisma.userListBook.findUnique({
      where: {
        listId_bookId: {
          listId: library.id,
          bookId,
        },
      },
    });

    return NextResponse.json({ inLibrary: !!inLibrary });
  } catch (error) {
    logger.error('Error checking library', { error: String(error) });
    return NextResponse.json({ inLibrary: false });
  }
}
