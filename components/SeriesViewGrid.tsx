import { Book } from '@/lib/types';
import BookCard from './BookCard';
import SeriesTile, { SeriesTileSeries } from './SeriesTile';

export interface SeriesViewItem {
  series?: SeriesTileSeries;
  book?: Book;
}

interface SeriesViewGridProps {
  items: SeriesViewItem[];
  loading?: boolean;
}

/**
 * Grid layout for the combined Series-mode feed (series + standalone books).
 *
 * Mirrors BookGrid's responsive columns, skeleton loading state, and empty
 * state. Each item carries exactly one of `series`/`book`; series render as
 * SeriesTile, standalone books reuse BookCard unchanged.
 *
 * @param items - Combined feed results from the catalog/library series-view endpoints
 * @param loading - Optional loading state to show skeleton placeholders
 * @returns Grid of series tiles and book cards with loading/empty state handling
 *
 * @example
 * <SeriesViewGrid items={data.results} loading={isLoading} />
 */
export default function SeriesViewGrid({ items, loading }: SeriesViewGridProps) {
  if (loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {[...Array(8)].map((_, i) => (
          <div key={i} className="animate-pulse">
            <div className="aspect-[2/3] bg-gray-200 dark:bg-gray-700 rounded-lg mb-4"></div>
            <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded mb-2"></div>
            <div className="h-3 bg-gray-200 dark:bg-gray-700 rounded w-3/4"></div>
          </div>
        ))}
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <div className="text-center py-12">
        <svg
          className="mx-auto h-12 w-12 text-gray-400"
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
        <h3 className="mt-2 text-sm font-medium text-gray-900 dark:text-white">No series found</h3>
        <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
          Try adjusting your search or filters.
        </p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
      {items.map((item) => {
        // Check `series` first — exactly one of the two is set per item.
        if (item.series) {
          return <SeriesTile key={`series-${item.series.id}`} series={item.series} />;
        }
        if (item.book) {
          return <BookCard key={`book-${item.book.id}`} book={item.book} />;
        }
        return null;
      })}
    </div>
  );
}
