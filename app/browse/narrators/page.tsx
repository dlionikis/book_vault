import Link from 'next/link';
import BackButton from '@/components/BackButton';
import { getBrowseEntities } from '@/lib/queries/browse-entities';

// DB-backed page: render per-request instead of static prerender at build time
// (where DATABASE_URL is unset and the Prisma query would throw). Keeps the
// build log free of PrismaClientInitializationError noise.
export const dynamic = 'force-dynamic';

interface NarratorWithCount {
  id: string;
  name: string;
  asin?: string | null;
  bookCount: number;
}

async function getNarrators(): Promise<NarratorWithCount[]> {
  try {
    // Shared with /api/browse/narrators: only entities that still have a visible
    // book, with a bookCount that matches. Also counts in SQL rather than
    // loading every joined book row to take .length.
    const { entities } = await getBrowseEntities('narrator', { limit: null });

    return entities.map((entity) => ({
      id: entity.id,
      name: entity.label,
      asin: entity.asin,
      bookCount: entity.bookCount,
    }));
  } catch (error) {
    console.error('Error fetching narrators:', error);
    return [];
  }
}

export default async function BrowseNarratorsPage() {
  const narrators = await getNarrators();

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <BackButton />

          <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Browse by Narrator</h1>
          <p className="text-gray-600 dark:text-gray-400 mt-2">
            {narrators.length} {narrators.length === 1 ? 'narrator' : 'narrators'}
          </p>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {narrators.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {narrators.map((narrator) => (
              <Link
                key={narrator.id}
                href={`/narrators/${narrator.id}`}
                className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow block"
              >
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2 hover:text-blue-600 dark:hover:text-blue-400">
                  {narrator.name}
                </h3>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  {narrator.bookCount} {narrator.bookCount === 1 ? 'book' : 'books'}
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
                d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
              />
            </svg>
            <h3 className="mt-4 text-lg font-medium text-gray-900">No narrators found</h3>
            <p className="mt-2 text-gray-500">Add some audiobooks to see narrators here</p>
          </div>
        )}
      </main>
    </div>
  );
}
