'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

interface RestoreSeriesButtonProps {
  seriesId: string;
  /** Series-wide count of archived books (drives the label). */
  archivedCount: number;
}

/**
 * "Restore All Archived" CTA on the series detail page. POSTs
 * /api/series/{id}/restore, which batch-initiates a restore for every archived
 * book in the whole series (not just the current page). On success it refreshes
 * so the server re-renders each book's badge into its restoring state.
 *
 * Renders nothing when the series has no archived books.
 */
export default function RestoreSeriesButton({ seriesId, archivedCount }: RestoreSeriesButtonProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState(false);

  if (archivedCount === 0) return null;

  const handleRestore = async () => {
    setLoading(true);
    setError(false);
    try {
      const res = await fetch(`/api/series/${seriesId}/restore`, { method: 'POST' });
      if (res.ok) {
        setDone(true);
        router.refresh();
      } else {
        setError(true);
      }
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="mt-4 flex flex-col gap-2">
      <button
        onClick={handleRestore}
        disabled={loading || done}
        className="flex items-center gap-2 self-start rounded-full bg-amber-600 px-6 py-3 font-medium text-white transition-colors hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-700 dark:hover:bg-amber-800"
      >
        {loading ? (
          <svg className="h-5 w-5 animate-spin" fill="none" viewBox="0 0 24 24" aria-hidden="true">
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
            />
          </svg>
        ) : (
          <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path d="M11 2h2v20h-2z" />
            <path d="M2 11h20v2H2z" />
          </svg>
        )}
        {done
          ? 'Restore requested'
          : `Restore All Archived (${archivedCount} book${archivedCount === 1 ? '' : 's'})`}
      </button>
      <p className="text-sm text-gray-600 dark:text-gray-400">
        {archivedCount} book{archivedCount === 1 ? ' in' : 's in'} this series{' '}
        {archivedCount === 1 ? 'is' : 'are'} archived. Restoring takes about 3–5 hours; you can
        leave the page and we&apos;ll notify you when books are ready.
      </p>
      {error && (
        <p className="text-sm text-red-600 dark:text-red-400" role="alert">
          Couldn&apos;t start the restore. Please try again.
        </p>
      )}
    </div>
  );
}
