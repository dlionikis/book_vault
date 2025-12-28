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
  const authorId = normalizeUuid(params.id);
  if (!authorId) {
    return NextResponse.json({ error: 'Invalid author ID format' }, { status: 400 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    const author = await prisma.author.findUnique({
      where: { id: authorId },
    });

    if (!author) {
      return NextResponse.json({ error: 'Author not found' }, { status: 404 });
    }

    // Get books by this author with their relationships
    const [bookAuthorEntries, total] = await Promise.all([
      prisma.bookAuthor.findMany({
        where: { authorId },
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
      prisma.bookAuthor.count({
        where: { authorId },
      }),
    ]);

    // Transform book data to include full URLs and proper structure (OpenAPI compliant)
    const booksWithUrls = bookAuthorEntries.map((entry) => transformBook(entry.book));

    const totalPages = Math.ceil(total / limit);

    return NextResponse.json({
      id: author.id,
      name: author.name,
      asin: author.asin,
      books: booksWithUrls,
      pagination: {
        page,
        limit,
        total,
        pages: totalPages,
      },
    });
  } catch (error) {
    console.error('Error fetching author:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
