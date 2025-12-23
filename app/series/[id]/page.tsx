import { notFound } from 'next/navigation';
import { Book, Series } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';
import { getBaseUrl } from '@/lib/api-url';

interface SeriesWithBooks extends Series {
  books: Book[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

async function getSeries(id: string, page?: string): Promise<SeriesWithBooks | null> {
  try {
    const pageParam = page ? `?page=${page}` : '';
    const res = await fetch(`${getBaseUrl()}/api/series/${id}${pageParam}`, {
      next: { revalidate: 0 },
    });

    if (!res.ok) {
      return null;
    }

    return res.json();
  } catch (error) {
    console.error('Error fetching series:', error);
    return null;
  }
}

export default async function SeriesPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: Promise<{ page?: string }>;
}) {
  const sp = await searchParams;
  const series = await getSeries(params.id, sp.page);

  if (!series) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Series Header */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-2">{series.title}</h1>

          <div className="text-gray-600 dark:text-gray-400 text-lg">
            {series.books.length} {series.books.length === 1 ? 'book' : 'books'} in this series
          </div>
        </div>

        {/* Books in Series */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 dark:text-white mb-4">
            Books in Series Order
          </h2>
          {series.books.length > 0 ? (
            <>
              <BookGrid books={series.books} />
              <Pagination
                currentPage={series.pagination.page}
                totalPages={series.pagination.pages}
                total={series.pagination.total}
                itemName="books"
              />
            </>
          ) : (
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-8 text-center text-gray-500 dark:text-gray-400">
              No books found in this series
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
