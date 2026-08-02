import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';
import { VISIBLE_BOOK_WHERE } from '@/lib/book-transformer';

// PUT /api/library/lists/[id] - Update list metadata
export async function PUT(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    // Normalize UUID
    const id = normalizeUuid(params.id);
    if (!id) {
      return NextResponse.json({ error: 'Invalid list ID format' }, { status: 400 });
    }
    const body = await request.json();
    const { name, description } = body;

    // Verify list belongs to user
    const existingList = await prisma.userList.findUnique({
      where: { id },
    });

    if (!existingList) {
      return NextResponse.json({ error: 'List not found' }, { status: 404 });
    }

    if (existingList.userId !== user.id) {
      return NextResponse.json({ error: 'Not your list' }, { status: 403 });
    }

    // Update list
    const updateData: { name?: string; description?: string | null } = {};
    if (name !== undefined) {
      updateData.name = name;
    }
    if (description !== undefined) {
      updateData.description = description || null;
    }

    const list = await prisma.userList.update({
      where: { id },
      data: updateData,
      include: {
        _count: { select: { books: { where: { book: VISIBLE_BOOK_WHERE } } } },
      },
    });

    return NextResponse.json({
      id: list.id,
      name: list.name,
      description: list.description,
      bookCount: list._count.books,
      createdAt: list.createdAt.toISOString(),
      updatedAt: list.updatedAt.toISOString(),
    });
  } catch (error) {
    logger.error('Error updating list', { error: String(error) });
    return NextResponse.json({ error: 'Failed to update list' }, { status: 500 });
  }
}

// DELETE /api/library/lists/[id] - Delete list
export async function DELETE(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;
    const user = auth.user;

    // Normalize UUID
    const id = normalizeUuid(params.id);
    if (!id) {
      return NextResponse.json({ error: 'Invalid list ID format' }, { status: 400 });
    }

    // Verify list belongs to user
    const existingList = await prisma.userList.findUnique({
      where: { id },
    });

    if (!existingList) {
      return NextResponse.json({ error: 'List not found' }, { status: 404 });
    }

    if (existingList.userId !== user.id) {
      return NextResponse.json({ error: 'Not your list' }, { status: 403 });
    }

    // Delete list (cascade deletes books via Prisma schema)
    await prisma.userList.delete({
      where: { id },
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    logger.error('Error deleting list', { error: String(error) });
    return NextResponse.json({ error: 'Failed to delete list' }, { status: 500 });
  }
}
