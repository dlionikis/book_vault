import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// GET /api/library/check?bookId=xxx - Check if book is in library
export async function GET(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) {
      return NextResponse.json({ inLibrary: false });
    }

    const bookId = request.nextUrl.searchParams.get('bookId');
    if (!bookId) {
      return NextResponse.json({ error: 'Book ID is required' }, { status: 400 });
    }

    // Get user's library
    const library = await prisma.userList.findFirst({
      where: {
        userId: session.user.id,
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
    console.error('Error checking library:', error);
    return NextResponse.json({ inLibrary: false });
  }
}
