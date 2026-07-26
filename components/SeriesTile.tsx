import Image from 'next/image';
import Link from 'next/link';

export interface SeriesTileSeries {
  id: string;
  title: string;
  asin?: string | null;
  bookCount: number;
  /** Derived from the lowest-sequence book in the series that has cover art. */
  coverUrl?: string | null;
  /** Library-scoped responses only: how many of this series' books the user owns. */
  ownedCount?: number;
}

interface SeriesTileProps {
  series: SeriesTileSeries;
}

/**
 * Builds the count line shown under a series title.
 *
 * Catalog scope (no `ownedCount`) and fully-owned Library series both read
 * "N books"; a partially-owned Library series reads "N of M in your library".
 */
export function seriesCountLabel(series: SeriesTileSeries): string {
  const { bookCount, ownedCount } = series;

  if (ownedCount !== undefined && ownedCount < bookCount) {
    return `${ownedCount} of ${bookCount} in your library`;
  }

  return `${bookCount} ${bookCount === 1 ? 'book' : 'books'}`;
}

/**
 * Displays a single series as a clickable card with a derived cover image.
 *
 * The Series-mode counterpart to BookCard: same cover treatment, rounding, and
 * title typography, but no author/narrator/runtime lines (a series has no single
 * value for those). Links to the series detail page.
 *
 * @param series - Series with book count, derived cover, and optional owned count
 * @returns Interactive series card that links to /series/[id]
 *
 * @example
 * <SeriesTile series={{ id, title: 'The Expanse', bookCount: 9, ownedCount: 3 }} />
 */
export default function SeriesTile({ series }: SeriesTileProps) {
  return (
    <div className="group bg-white dark:bg-gray-800 rounded-lg shadow-md hover:shadow-xl transition-shadow duration-200 overflow-hidden">
      <Link href={`/series/${series.id}`} className="block">
        {/* Cover Image (derived from the series' first book with cover art) */}
        <div className="relative aspect-[2/3] bg-gray-200 dark:bg-gray-700">
          {series.coverUrl ? (
            <Image
              src={series.coverUrl}
              alt={`Cover of ${series.title}`}
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
          {/* Series marker — distinguishes a series tile from a book cover at a glance */}
          <span className="absolute top-2 left-2 inline-flex items-center rounded-full bg-gray-900/75 px-2 py-0.5 text-xs font-medium text-white backdrop-blur-sm">
            Series
          </span>
        </div>
      </Link>

      {/* Series Info */}
      <div className="p-4">
        <Link href={`/series/${series.id}`} className="block">
          <h3 className="font-semibold text-lg text-gray-900 dark:text-white group-hover:text-blue-600 dark:group-hover:text-blue-400 transition-colors line-clamp-2 mb-2">
            {series.title}
          </h3>
        </Link>

        <p className="text-sm text-gray-600 dark:text-gray-400">{seriesCountLabel(series)}</p>
      </div>
    </div>
  );
}
