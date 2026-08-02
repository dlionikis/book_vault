import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { getCoverUrl } from '@/lib/media';
import { VISIBLE_BOOK_WHERE } from '@/lib/book-transformer';

export async function GET(request: NextRequest) {
  // Check both auth methods
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  try {
    const searchParams = request.nextUrl.searchParams;
    const query = (searchParams.get('q') || '').trim();

    if (query.length < 2) {
      return NextResponse.json({ error: 'Query must be at least 2 characters' }, { status: 400 });
    }

    // Search across books, authors, and narrators in parallel
    const [books, authors, narrators] = await Promise.all([
      // Top 5 books
      prisma.book.findMany({
        where: {
          // Beside OR, not inside it: as a branch this would match hidden
          // books instead of excluding them.
          ...VISIBLE_BOOK_WHERE,
          OR: [
            {
              title: {
                contains: query,
                mode: 'insensitive',
              },
            },
            {
              series: {
                some: {
                  series: {
                    title: {
                      contains: query,
                      mode: 'insensitive',
                    },
                  },
                },
              },
            },
          ],
        },
        select: {
          id: true,
          title: true,
          coverUrl: true,
        },
        take: 5,
        orderBy: {
          title: 'asc',
        },
      }),
      // Top 3 authors. Requires at least one visible book, so an author whose
      // whole catalogue is hidden is not suggested into an empty detail page.
      prisma.author.findMany({
        where: {
          name: {
            contains: query,
            mode: 'insensitive',
          },
          books: { some: { book: VISIBLE_BOOK_WHERE } },
        },
        select: {
          id: true,
          name: true,
        },
        take: 3,
        orderBy: {
          name: 'asc',
        },
      }),
      // Top 2 narrators
      prisma.narrator.findMany({
        where: {
          name: {
            contains: query,
            mode: 'insensitive',
          },
          books: { some: { book: VISIBLE_BOOK_WHERE } },
        },
        select: {
          id: true,
          name: true,
        },
        take: 2,
        orderBy: {
          name: 'asc',
        },
      }),
    ]);

    // Transform book results (async for presigned S3 URLs in production)
    const transformedBooks = await Promise.all(
      books.map(async (book) => ({
        id: book.id,
        title: book.title,
        coverUrl: await getCoverUrl(book.coverUrl),
      }))
    );

    return NextResponse.json({
      books: transformedBooks,
      authors,
      narrators,
    });
  } catch (error) {
    logger.error('Error fetching suggestions', { error: String(error) });
    return NextResponse.json({ error: 'Failed to fetch suggestions' }, { status: 500 });
  }
}
