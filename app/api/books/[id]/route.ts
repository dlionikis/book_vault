import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { getCoverUrl, getAudioUrl } from '@/lib/media';
import { normalizeUuid } from '@/lib/api-utils';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const bookId = normalizeUuid(params.id);
    if (!bookId) {
      return NextResponse.json({ error: 'Invalid book ID' }, { status: 400 });
    }

    // Check if chapters should be included
    const url = new URL(request.url);
    const includeChapters = url.searchParams.get('include') === 'chapters';

    const book = await prisma.book.findUnique({
      where: { id: bookId },
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
        categories: {
          include: {
            category: {
              include: {
                parent: true,
              },
            },
          },
        },
        chapters: includeChapters
          ? {
              orderBy: {
                chapterNumber: 'asc',
              },
            }
          : false,
      },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    // Transform the response (OpenAPI compliant - only return spec-defined fields)
    const transformedBook = {
      id: book.id,
      asin: book.asin,
      title: book.title,
      description: book.description,
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
      categories: book.categories.map((bc) => ({
        id: bc.category.id,
        name: bc.category.name,
      })),
      ...(includeChapters &&
        book.chapters && {
          chapters: book.chapters.map((chapter) => ({
            id: chapter.id,
            chapterNumber: chapter.chapterNumber,
            title: chapter.title,
            startTime: chapter.startTime,
            endTime: chapter.endTime,
            duration: chapter.duration,
          })),
        }),
    };

    const response = NextResponse.json(transformedBook);

    // Add caching headers when chapters are included
    if (includeChapters) {
      response.headers.set('Cache-Control', 'public, max-age=86400');
    }

    return response;
  } catch (error) {
    console.error('Error fetching book:', error);
    return NextResponse.json({ error: 'Failed to fetch book' }, { status: 500 });
  }
}
