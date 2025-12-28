import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';

// PUT /api/library/lists/[id]/reorder - Reorder books in list
export async function PUT(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    // Normalize list UUID
    const listId = normalizeUuid(params.id);
    if (!listId) {
      return NextResponse.json({ error: 'Invalid list ID format' }, { status: 400 });
    }

    const body = await request.json();
    const { bookIds } = body;

    if (!Array.isArray(bookIds)) {
      return NextResponse.json({ error: 'Book IDs array required' }, { status: 400 });
    }

    // Normalize all book IDs in the array
    const normalizedBookIds = bookIds
      .map((id) => normalizeUuid(id))
      .filter((id): id is string => id !== null);
    if (normalizedBookIds.length !== bookIds.length) {
      return NextResponse.json({ error: 'Invalid book ID format in array' }, { status: 400 });
    }

    // Verify list belongs to user
    const existingList = await prisma.userList.findUnique({
      where: { id: listId },
    });

    if (!existingList) {
      return NextResponse.json({ error: 'List not found' }, { status: 404 });
    }

    if (existingList.userId !== user.id) {
      return NextResponse.json({ error: 'Not your list' }, { status: 403 });
    }

    // Update positions in a transaction
    await prisma.$transaction(
      normalizedBookIds.map((bookId, index) =>
        prisma.userListBook.updateMany({
          where: {
            listId,
            bookId,
          },
          data: {
            position: index,
          },
        })
      )
    );

    return NextResponse.json({ success: true, updated: normalizedBookIds.length });
  } catch (error) {
    console.error('Error reordering list:', error);
    return NextResponse.json({ error: 'Failed to reorder list' }, { status: 500 });
  }
}
