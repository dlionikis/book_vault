import Link from 'next/link';
import BackButton from '@/components/BackButton';
import { prisma } from '@/lib/db';

// DB-backed page: render per-request instead of static prerender at build time
// (where DATABASE_URL is unset and the Prisma query would throw). Keeps the
// build log free of PrismaClientInitializationError noise.
export const dynamic = 'force-dynamic';

interface SeriesWithCount {
  id: string;
  title: string;
  asin?: string | null;
  bookCount: number;
}

async function getSeries(): Promise<SeriesWithCount[]> {
  try {
    const seriesList = await prisma.series.findMany({
      include: {
        books: {
          include: {
            book: true,
          },
        },
      },
      orderBy: {
        title: 'asc',
      },
    });

    return seriesList.map((series) => ({
      id: series.id,
      title: series.title,
      asin: series.asin,
      bookCount: series.books.length,
    }));
  } catch (error) {
    console.error('Error fetching series:', error);
    return [];
  }
}

export default async function BrowseSeriesPage() {
  const series = await getSeries();

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <BackButton />

          <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Browse by Series</h1>
          <p className="text-gray-600 dark:text-gray-400 mt-2">
            {series.length} {series.length === 1 ? 'series' : 'series'}
          </p>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {series.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {series.map((s) => (
              <Link
                key={s.id}
                href={`/series/${s.id}`}
                className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow block"
              >
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2 hover:text-blue-600 dark:hover:text-blue-400">
                  {s.title}
                </h3>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  {s.bookCount} {s.bookCount === 1 ? 'book' : 'books'}
                </p>
              </Link>
            ))}
          </div>
        ) : (
          <div className="text-center py-12">
            <svg
              className="mx-auto h-16 w-16 text-gray-400 dark:text-gray-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
              />
            </svg>
            <h3 className="mt-4 text-lg font-medium text-gray-900">No series found</h3>
            <p className="mt-2 text-gray-500">Add some audiobooks to see series here</p>
          </div>
        )}
      </main>
    </div>
  );
}
