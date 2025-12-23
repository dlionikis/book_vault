import { notFound } from 'next/navigation';
import { Book, Narrator } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';
import { PrismaClient } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

const prisma = new PrismaClient();

interface NarratorWithBooks extends Narrator {
  books: Book[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

async function getNarrator(id: string, page?: string): Promise<NarratorWithBooks | null> {
  try {
    const pageNum = parseInt(page || '1');
    const limit = 20;
    const skip = (pageNum - 1) * limit;

    const narrator = await prisma.narrator.findUnique({
      where: { id },
    });

    if (!narrator) {
      return null;
    }

    const [bookNarratorEntries, total] = await Promise.all([
      prisma.bookNarrator.findMany({
        where: { narratorId: id },
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
      prisma.bookNarrator.count({
        where: { narratorId: id },
      }),
    ]);

    const books = bookNarratorEntries.map((entry) => {
      const book = entry.book;
      return {
        id: book.id,
        asin: book.asin,
        title: book.title,
        publisherSummary: book.publisherSummary,
        runtimeMinutes: book.runtimeMinutes,
        releaseDate: book.releaseDate,
        publisher: book.publisher,
        coverUrl: getCoverUrl(book.coverUrl),
        audioUrl: getAudioUrl(book.audioUrl),
        authors: book.authors.map((ba) => ba.author),
        narrators: book.narrators.map((bn) => bn.narrator),
        series: book.series.map((bs) => ({
          id: bs.series.id,
          title: bs.series.title,
          asin: bs.series.asin,
          sequence: bs.sequence,
        })),
        createdAt: book.createdAt.toISOString(),
      };
    });

    return {
      ...narrator,
      books,
      pagination: {
        page: pageNum,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    };
  } catch (error) {
    console.error('Error fetching narrator:', error);
    return null;
  }
}

export default async function NarratorPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: Promise<{ page?: string }>;
}) {
  const sp = await searchParams;
  const narrator = await getNarrator(params.id, sp.page);

  if (!narrator) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Narrator Header */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-2">{narrator.name}</h1>

          <div className="text-gray-600 dark:text-gray-400 text-lg">
            {narrator.books.length} {narrator.books.length === 1 ? 'book' : 'books'}
          </div>
        </div>

        {/* Books by Narrator */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 dark:text-white mb-4">
            Books narrated by {narrator.name}
          </h2>
          {narrator.books.length > 0 ? (
            <>
              <BookGrid books={narrator.books} />
              <Pagination
                currentPage={narrator.pagination.page}
                totalPages={narrator.pagination.pages}
                total={narrator.pagination.total}
                itemName="books"
              />
            </>
          ) : (
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-8 text-center text-gray-500 dark:text-gray-400">
              No books found for this narrator
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
