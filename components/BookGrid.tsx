import { ReactNode } from 'react';
import { Book } from '@/lib/types';
import BookCard from './BookCard';

interface BookGridProps {
  books: Book[];
  loading?: boolean;
  /** Per-book extra content rendered below each card's built-in info (e.g. progress, remove button). */
  renderFooter?: (book: Book) => ReactNode;
}

/**
 * Responsive grid layout for displaying multiple audiobooks with loading and empty states.
 *
 * Renders books in a responsive grid (1-4 columns based on screen size). Shows skeleton
 * loading placeholders when data is loading. Displays a helpful empty state with icon
 * when no books are found. Uses BookCard component for individual book rendering.
 *
 * @param books - Array of book objects to display in the grid
 * @param loading - Optional loading state to show skeleton placeholders
 * @returns Grid of book cards with loading/empty state handling
 *
 * @example
 * <BookGrid books={searchResults} loading={isSearching} />
 */
export default function BookGrid({ books, loading, renderFooter }: BookGridProps) {
  if (loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {[...Array(8)].map((_, i) => (
          <div key={i} className="animate-pulse">
            <div className="aspect-[2/3] bg-gray-200 rounded-lg mb-4"></div>
            <div className="h-4 bg-gray-200 rounded mb-2"></div>
            <div className="h-3 bg-gray-200 rounded w-3/4"></div>
          </div>
        ))}
      </div>
    );
  }

  if (books.length === 0) {
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
        <h3 className="mt-2 text-sm font-medium text-gray-900">No books found</h3>
        <p className="mt-1 text-sm text-gray-500">Try adjusting your search or filters.</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
      {books.map((book) => (
        <BookCard key={book.id} book={book} footer={renderFooter?.(book)} />
      ))}
    </div>
  );
}
