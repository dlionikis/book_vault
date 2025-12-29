import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';

export async function GET(request: NextRequest, { params }: { params: { bookId: string } }) {
  try {
    // Check both auth methods
    const session = await getServerSession(authOptions);
    const mobileUser = await getAuthUserFromRequest(request);
    const user = session?.user || mobileUser;

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

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
    console.error('Download eligibility check error:', error);
    return NextResponse.json({ error: 'Failed to check download eligibility' }, { status: 500 });
  }
}
