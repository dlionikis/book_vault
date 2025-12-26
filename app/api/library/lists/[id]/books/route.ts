import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

// POST /api/library/lists/[id]/books - Add book to list
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { id: listId } = params;
    const body = await request.json();
    const { bookId } = body;

    if (!bookId || typeof bookId !== 'string') {
      return NextResponse.json({ error: 'Book ID is required' }, { status: 400 });
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

    // Verify book exists
    const book = await prisma.book.findUnique({
      where: { id: bookId },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    // Use upsert to handle duplicates gracefully
    await prisma.userListBook.upsert({
      where: {
        listId_bookId: {
          listId,
          bookId,
        },
      },
      create: {
        listId,
        bookId,
      },
      update: {},
    });

    return NextResponse.json({ success: true }, { status: 201 });
  } catch (error) {
    console.error('Error adding book to list:', error);
    return NextResponse.json({ error: 'Failed to add book to list' }, { status: 500 });
  }
}

// DELETE /api/library/lists/[id]/books - Remove book from list
export async function DELETE(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { id: listId } = params;
    const { searchParams } = new URL(request.url);
    const bookId = searchParams.get('bookId');

    if (!bookId) {
      return NextResponse.json({ error: 'Book ID is required' }, { status: 400 });
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

    // Remove book from list
    await prisma.userListBook.deleteMany({
      where: {
        listId,
        bookId,
      },
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error removing book from list:', error);
    return NextResponse.json({ error: 'Failed to remove book from list' }, { status: 500 });
  }
}
