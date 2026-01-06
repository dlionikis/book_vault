import Image from 'next/image';
import Link from 'next/link';
import { Book, Author, Narrator } from '@/lib/types';

interface BookCardProps {
  book: Book;
}

/**
 * Displays a single audiobook as a clickable card with cover image and metadata.
 *
 * Renders a responsive card showing book cover, title, series information, authors,
 * narrators, and runtime. Card links to the book detail page and includes hover
 * effects. Handles missing cover images gracefully with a placeholder icon.
 * Automatically formats runtime and displays primary series with sequence number.
 *
 * @param book - Complete book object from API including nested authors, narrators, and series
 * @returns Interactive book card component that links to /books/[id]
 *
 * @example
 * <BookCard book={myBook} />
 */
export default function BookCard({ book }: BookCardProps) {
  // Format runtime as hours and minutes
  const formatRuntime = (minutes?: number | null) => {
    if (!minutes) return null;
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    return `${hours}h ${mins}m`;
  };

  // Get first series if exists
  const primarySeries = book.series.length > 0 ? book.series[0] : null;

  return (
    <Link
      href={`/books/${book.id}`}
      className="group block bg-white dark:bg-gray-800 rounded-lg shadow-md hover:shadow-xl transition-shadow duration-200 overflow-hidden"
    >
      {/* Cover Image */}
      <div className="relative aspect-[2/3] bg-gray-200 dark:bg-gray-700">
        {book.coverUrl ? (
          <Image
            src={book.coverUrl}
            alt={`Cover of ${book.title}`}
            fill
            className="object-cover"
            sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw"
          />
        ) : (
          <div className="absolute inset-0 flex items-center justify-center text-gray-400">
            <svg className="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
              />
            </svg>
          </div>
        )}
      </div>

      {/* Book Info */}
      <div className="p-4">
        {/* Title */}
        <h3 className="font-semibold text-lg text-gray-900 dark:text-white group-hover:text-blue-600 dark:group-hover:text-blue-400 transition-colors line-clamp-2 mb-2">
          {book.title}
        </h3>

        {/* Series */}
        {primarySeries && (
          <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">
            {primarySeries.title}
            {primarySeries.sequence && ` #${primarySeries.sequence}`}
          </p>
        )}

        {/* Authors */}
        {book.authors.length > 0 && (
          <p className="text-sm text-gray-700 dark:text-gray-300 mb-1">
            by {book.authors.map((a: Author) => a.name).join(', ')}
          </p>
        )}

        {/* Narrators */}
        {book.narrators.length > 0 && (
          <p className="text-sm text-gray-600 dark:text-gray-400 mb-2">
            Narrated by {book.narrators.map((n: Narrator) => n.name).join(', ')}
          </p>
        )}

        {/* Runtime */}
        {book.runtimeMinutes && (
          <p className="text-xs text-gray-500 dark:text-gray-400">
            {formatRuntime(book.runtimeMinutes)}
          </p>
        )}
      </div>
    </Link>
  );
}
