import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
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

    const author = await prisma.author.findUnique({
      where: { id: params.id },
    });

    if (!author) {
      return NextResponse.json({ error: 'Author not found' }, { status: 404 });
    }

    // Get books by this author with their relationships
    const [bookAuthorEntries, total] = await Promise.all([
      prisma.bookAuthor.findMany({
        where: { authorId: params.id },
        skip,
        take: limit,
        include: {
          book: {
            include: {
              authors: {
                include: {
                  author: true,
                },
              },
              narrators: {
                include: {
                  narrator: true,
                },
              },
              series: {
                include: {
                  series: true,
                },
              },
            },
          },
        },
        orderBy: {
          book: {
            title: 'asc',
          },
        },
      }),
      prisma.bookAuthor.count({
        where: { authorId: params.id },
      }),
    ]);

    // Transform book data to include full URLs and proper structure
    const booksWithUrls = bookAuthorEntries.map((entry) => {
      const book = entry.book;
      return {
        id: book.id,
        asin: book.asin,
        title: book.title,
        description: book.description,
        publisherSummary: book.publisherSummary,
        runtimeMinutes: book.runtimeMinutes,
        releaseDate: book.releaseDate,
        publisher: book.publisher,
        coverUrl: getCoverUrl(book.coverUrl),
        audioUrl: getAudioUrl(book.audioUrl),
        authors: book.authors.map((ba) => ({
          id: ba.author.id,
          name: ba.author.name,
          asin: ba.author.asin,
        })),
        narrators: book.narrators.map((bn) => ({
          id: bn.narrator.id,
          name: bn.narrator.name,
          asin: bn.narrator.asin,
        })),
        series: book.series.map((bs) => ({
          id: bs.series.id,
          title: bs.series.title,
          asin: bs.series.asin,
          sequence: bs.sequence,
        })),
        createdAt: book.createdAt.toISOString(),
      };
    });

    const totalPages = Math.ceil(total / limit);

    return NextResponse.json({
      ...author,
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
