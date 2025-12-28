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
  const seriesId = normalizeUuid(params.id);
  if (!seriesId) {
    return NextResponse.json({ error: 'Invalid series ID format' }, { status: 400 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    const series = await prisma.series.findUnique({
      where: { id: seriesId },
    });

    if (!series) {
      return NextResponse.json({ error: 'Series not found' }, { status: 404 });
    }

    // Get books in this series with their relationships
    const [bookSeriesEntries, total] = await Promise.all([
      prisma.bookSeries.findMany({
        where: { seriesId },
        skip,
        take: limit,
        include: {
          book: {
            include: BOOK_INCLUDE,
          },
        },
        orderBy: [{ sequence: 'asc' }],
      }),
      prisma.bookSeries.count({
        where: { seriesId },
      }),
    ]);

    // Transform book data to include full URLs and proper structure (OpenAPI compliant)
    const booksWithUrls = bookSeriesEntries.map((entry) => transformBook(entry.book));
  } catch (error) {
    console.error('Error fetching series:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
