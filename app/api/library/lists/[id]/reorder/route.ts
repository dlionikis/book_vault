import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { prisma } from '@/lib/db';

// PUT /api/library/lists/[id]/reorder - Reorder books in list
export async function PUT(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { id: listId } = params;
    const body = await request.json();
    const { bookIds } = body;

    if (!Array.isArray(bookIds)) {
      return NextResponse.json({ error: 'Book IDs array required' }, { status: 400 });
    }

    // Verify list belongs to user
    const existingList = await prisma.userList.findUnique({
      where: { id: listId },
    });

    if (!existingList) {
      return NextResponse.json({ error: 'List not found' }, { status: 404 });
    }

    if (existingList.userId !== session.user.id) {
      return NextResponse.json({ error: 'Not your list' }, { status: 403 });
    }

    // Update positions in a transaction
    await prisma.$transaction(
      bookIds.map((bookId, index) =>
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

    return NextResponse.json({ success: true, updated: bookIds.length });
  } catch (error) {
    console.error('Error reordering list:', error);
    return NextResponse.json({ error: 'Failed to reorder list' }, { status: 500 });
  }
}
