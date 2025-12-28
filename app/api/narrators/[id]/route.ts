import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
import { normalizeUuid } from '@/lib/api-utils';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Normalize UUID
  const narratorId = normalizeUuid(params.id);
  if (!narratorId) {
    return NextResponse.json({ error: 'Invalid narrator ID format' }, { status: 400 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    const narrator = await prisma.narrator.findUnique({
      where: { id: narratorId },
    });

    if (!narrator) {
      return NextResponse.json({ error: 'Narrator not found' }, { status: 404 });
    }

    // Get books by this narrator with their relationships
    const [bookNarratorEntries, total] = await Promise.all([
      prisma.bookNarrator.findMany({
        where: { narratorId },
        skip,
        take: limit,
        include: {
          book: {
            include: BOOK_INCLUDE,
          },
        },
        orderBy: {
          book: {
            title: 'asc',
          },
        },
      }),
      prisma.bookNarrator.count({
        where: { narratorId },
      }),
    ]);

    // Transform book data to include full URLs and proper structure (OpenAPI compliant)
    const booksWithUrls = bookNarratorEntries.map((entry) => transformBook(entry.book));

    const totalPages = Math.ceil(total / limit);

    return NextResponse.json({
      id: narrator.id,
      name: narrator.name,
      asin: narrator.asin,
      books: booksWithUrls,
      pagination: {
        page,
        limit,
        total,
        pages: totalPages,
      },
    });
  } catch (error) {
    console.error('Error fetching narrator:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
