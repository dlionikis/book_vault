import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';

export async function GET(request: NextRequest, { params }: { params: { bookId: string } }) {
  try {
    // Check both auth methods
    const auth = await requireUser(request);
    if (auth.error) return auth.error;

    const { bookId } = params;
    const normalizedBookId = normalizeUuid(bookId);

    // Verify book exists
    const book = await prisma.book.findUnique({
      where: { id: normalizedBookId as string },
      select: { id: true },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    // For MVP: All users can download all books
    // Future: Check if book in user's library, check storage quota, etc.
    return NextResponse.json({
      eligible: true,
    });
  } catch (error) {
    logger.error('Download eligibility check error', { error: String(error) });
    return NextResponse.json({ error: 'Failed to check download eligibility' }, { status: 500 });
  }
}
