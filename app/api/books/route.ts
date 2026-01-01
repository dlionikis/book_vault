import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
import { buildPagination } from '@/lib/api-utils';
import type { components } from '@/lib/api-types';

type Book = components['schemas']['Book'];

export async function GET(request: NextRequest) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;
    const sort = searchParams.get('sort') || 'title';

    // Build orderBy based on sort parameter
    let orderBy: any = { title: 'asc' };

    // For author/narrator/series, we'll sort after fetching
    // Only use database ordering for title
    if (sort === 'title') {
      orderBy = { title: 'asc' };
    }

    // Fetch books with their relationships
    const [books, total] = await Promise.all([
      prisma.book.findMany({
        skip,
        take: limit,
        include: BOOK_INCLUDE,
        orderBy,
      }),
      prisma.book.count(),
    ]);

    // Transform the response to match OpenAPI Book schema
    // Note: transformBook is async (generates presigned URLs in production)
    let transformedBooks: Book[] = await Promise.all(books.map(transformBook));

    // Apply client-side sorting for author/narrator/series
    if (sort === 'author') {
      transformedBooks.sort((a, b) => {
        const aAuthor = a.authors[0]?.name || '';
        const bAuthor = b.authors[0]?.name || '';
        return aAuthor.localeCompare(bAuthor);
      });
    } else if (sort === 'narrator') {
      transformedBooks.sort((a, b) => {
        const aNarrator = a.narrators?.[0]?.name || '';
        const bNarrator = b.narrators?.[0]?.name || '';
        return aNarrator.localeCompare(bNarrator);
      });
    } else if (sort === 'series') {
      transformedBooks.sort((a, b) => {
        const aSeries = a.series?.[0]?.title || '';
        const bSeries = b.series?.[0]?.title || '';
        return aSeries.localeCompare(bSeries);
      });
    }

    return NextResponse.json({
      books: transformedBooks,
      pagination: buildPagination(page, limit, total),
    });
  } catch (error) {
    console.error('Error fetching books:', error);
    return NextResponse.json({ error: 'Failed to fetch books' }, { status: 500 });
  }
}
