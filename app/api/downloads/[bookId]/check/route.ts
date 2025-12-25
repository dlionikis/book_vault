import { NextRequest, NextResponse } from 'next/server';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

export async function GET(
  request: NextRequest,
  { params }: { params: { bookId: string } }
) {
  try {
    // Authenticate user
    const user = await getAuthUserFromRequest(request);
    if (!user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    const { bookId } = params;

    // Verify book exists
    const book = await prisma.book.findUnique({
      where: { id: bookId },
      select: { id: true },
    });

    if (!book) {
      return NextResponse.json(
        { error: 'Book not found' },
        { status: 404 }
      );
    }

    // For MVP: All users can download all books
    // Future: Check if book in user's library, check storage quota, etc.
    return NextResponse.json({
      eligible: true,
    });
  } catch (error) {
    console.error('Download eligibility check error:', error);
    return NextResponse.json(
      { error: 'Failed to check download eligibility' },
      { status: 500 }
    );
  }
}
