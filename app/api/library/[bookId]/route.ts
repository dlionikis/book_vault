import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// DELETE /api/library/[bookId] - Remove book from library
export async function DELETE(request: NextRequest, { params }: { params: { bookId: string } }) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { bookId } = params;

    // Get user's library
    const library = await prisma.userList.findFirst({
      where: {
        userId: session.user.id,
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
    console.error('Error removing from library:', error);
    return NextResponse.json({ error: 'Failed to remove book from library' }, { status: 500 });
  }
}
