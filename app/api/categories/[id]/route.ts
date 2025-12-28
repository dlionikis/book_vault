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

  // Normalize UUID
  const categoryId = normalizeUuid(params.id);
  if (!categoryId) {
    return NextResponse.json({ error: 'Invalid category ID format' }, { status: 400 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '20');
    const skip = (page - 1) * limit;

    const category = await prisma.category.findUnique({
      where: { id: categoryId },
      include: {
        parent: true,
      },
    });

    if (!category) {
      return NextResponse.json({ error: 'Category not found' }, { status: 404 });
    }

    // Get books in this category with their relationships
    const [bookCategoryEntries, total] = await Promise.all([
      prisma.bookCategory.findMany({
        where: { categoryId },
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
      prisma.bookCategory.count({
        where: { categoryId },
      }),
    ]);

    // Transform book data to include full URLs and proper structure (OpenAPI compliant)
    const booksWithUrls = bookCategoryEntries.map((entry) => {
      const book = entry.book;
      return {
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
      };
    });

    const totalPages = Math.ceil(total / limit);

    return NextResponse.json({
      id: category.id,
      name: category.name,
      books: booksWithUrls,
      pagination: {
        page,
        limit,
        total,
        pages: totalPages,
      },
    });
  } catch (error) {
    console.error('Error fetching category:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
