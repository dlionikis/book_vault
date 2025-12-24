import { NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

export async function GET(request: Request, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const book = await prisma.book.findUnique({
      where: { id: params.id },
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
      },
    });

    if (!book) {
      return NextResponse.json({ error: 'Book not found' }, { status: 404 });
    }

    // Transform the response
    const transformedBook = {
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
      categories: book.categories.map((bc) => ({
        id: bc.category.id,
        name: bc.category.name,
        level: bc.category.level,
        parentName: bc.category.parent?.name,
      })),
      metadata: book.metadata,
      createdAt: book.createdAt,
    };

    return NextResponse.json(transformedBook);
  } catch (error) {
    console.error('Error fetching book:', error);
    return NextResponse.json({ error: 'Failed to fetch book' }, { status: 500 });
  }
}
