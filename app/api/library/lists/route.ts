import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { prisma } from '@/lib/db';

// GET /api/library/lists - Get all user lists with book counts
export async function GET(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const lists = await prisma.userList.findMany({
      where: { userId: session.user.id },
      include: {
        _count: { select: { books: true } },
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
    console.error('Error fetching lists:', error);
    return NextResponse.json({ error: 'Failed to fetch lists' }, { status: 500 });
  }
}

// POST /api/library/lists - Create new list
export async function POST(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await request.json();
    const { name, description } = body;

    if (!name || typeof name !== 'string') {
      return NextResponse.json({ error: 'List name is required' }, { status: 400 });
    }

    const list = await prisma.userList.create({
      data: {
        userId: session.user.id,
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
    console.error('Error creating list:', error);
    return NextResponse.json({ error: 'Failed to create list' }, { status: 500 });
  }
}
