import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { getCoverUrl } from '@/lib/media';

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
    const query = (searchParams.get('q') || '').trim();

    if (query.length < 2) {
      return NextResponse.json({ error: 'Query must be at least 2 characters' }, { status: 400 });
    }

    // Search across books, authors, and narrators in parallel
    const [books, authors, narrators] = await Promise.all([
      // Top 5 books
      prisma.book.findMany({
        where: {
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
      // Top 3 authors
      prisma.author.findMany({
        where: {
          name: {
            contains: query,
            mode: 'insensitive',
          },
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
    console.error('Error fetching suggestions:', error);
    return NextResponse.json({ error: 'Failed to fetch suggestions' }, { status: 500 });
  }
}
