import { SearchResponse } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import SearchBar from '@/components/SearchBar';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';
import { searchBooks } from '@/lib/queries/search-books';

const PAGE_SIZE = 20;

async function getSearchResults(query: string, page?: string): Promise<SearchResponse | null> {
  if (!query) return null;

  try {
    const pageNum = parseInt(page || '1');
    const skip = (pageNum - 1) * PAGE_SIZE;

    // Shared with /api/search, so the visibility filter can't diverge between
    // the two the way it did in PR #157.
    const { books, total } = await searchBooks(query, { skip, limit: PAGE_SIZE });

    return {
      query,
      books,
      pagination: {
        page: pageNum,
        limit: PAGE_SIZE,
        total,
        pages: Math.ceil(total / PAGE_SIZE),
      },
    };
  } catch (error) {
    console.error('Error searching books:', error);
    return null;
  }
}

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; page?: string }>;
}) {
  const params = await searchParams;
  const query = params.q || '';
  const results = query ? await getSearchResults(query, params.page) : null;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between mb-4">
            <BackButton />
          </div>

          <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-4">
            Search Audiobooks
          </h1>

          <SearchBar />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {!query ? (
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
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
              />
            </svg>
            <h3 className="mt-4 text-lg font-medium text-gray-900 dark:text-white">
              Start searching
            </h3>
            <p className="mt-2 text-gray-500 dark:text-gray-400">
              Enter a title, author, narrator, or series name to find audiobooks
            </p>
          </div>
        ) : results && results.books.length > 0 ? (
          <div>
            <div className="mb-6">
              <h2 className="text-2xl font-semibold text-gray-900 dark:text-white">
                Search results for &ldquo;{query}&rdquo;
              </h2>
              <p className="text-gray-600 dark:text-gray-400 mt-1">
                {results.pagination.total} {results.pagination.total === 1 ? 'book' : 'books'} found
              </p>
            </div>
            <BookGrid books={results.books} />
            <Pagination
              currentPage={results.pagination.page}
              totalPages={results.pagination.pages}
              total={results.pagination.total}
              itemName="results"
            />
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
                d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <h3 className="mt-4 text-lg font-medium text-gray-900 dark:text-white">
              No results found
            </h3>
            <p className="mt-2 text-gray-500 dark:text-gray-400">
              No audiobooks found for &ldquo;{query}&rdquo;. Try a different search term.
            </p>
          </div>
        )}
      </main>
    </div>
  );
}
