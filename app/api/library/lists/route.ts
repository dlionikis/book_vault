import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { VISIBLE_BOOK_WHERE } from '@/lib/book-transformer';

// GET /api/library/lists - Get all user lists with book counts
export async function GET(request: NextRequest) {
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const lists = await prisma.userList.findMany({
      where: { userId: user.id },
      include: {
        _count: { select: { books: { where: { book: VISIBLE_BOOK_WHERE } } } },
      },
      orderBy: { createdAt: 'desc' },
    });

    const formattedLists = lists.map((list) => ({
      id: list.id,
      name: list.name,
      description: list.description,
      bookCount: list._count.books,
      createdAt: list.createdAt.toISOString(),
      updatedAt: list.updatedAt.toISOString(),
    }));

    return NextResponse.json({ lists: formattedLists });
  } catch (error) {
    logger.error('Error fetching lists', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch lists' }, { status: 500 });
  }
}

// POST /api/library/lists - Create new list
export async function POST(request: NextRequest) {
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    const body = await request.json();
    const { name, description } = body;

    if (!name || typeof name !== 'string') {
      return NextResponse.json({ error: 'List name is required' }, { status: 400 });
    }

    const list = await prisma.userList.create({
      data: {
        userId: user.id,
        name,
        description: description || null,
      },
    });

    return NextResponse.json(
      {
        id: list.id,
        name: list.name,
        description: list.description,
        bookCount: 0,
        createdAt: list.createdAt.toISOString(),
        updatedAt: list.updatedAt.toISOString(),
      },
      { status: 201 }
    );
  } catch (error) {
    logger.error('Error creating list', { error: String(error) });
    return NextResponse.json({ error: 'Failed to create list' }, { status: 500 });
  }
}
