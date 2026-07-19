'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

interface RestoreButtonProps {
  bookId: string;
}

/**
 * "Request restore" CTA shown on the detail page when a book's audio is
 * archived. POSTs /api/books/{id}/restore; on a 202 (restoring) it refreshes
 * the page so the server re-renders into the RestoringIndicator state.
 */
export default function RestoreButton({ bookId }: RestoreButtonProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  const handleRestore = async () => {
    setLoading(true);
    setError(false);
    try {
      const res = await fetch(`/api/books/${bookId}/restore`, { method: 'POST' });
      if (res.ok) {
        // 200 available or 202 restoring — either way, re-render into the
        // correct server-side state.
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
    <div className="flex flex-col gap-2">
      <button
        onClick={handleRestore}
        disabled={loading}
        className="flex items-center gap-2 rounded-full bg-amber-600 px-6 py-3 font-medium text-white transition-colors hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-700 dark:hover:bg-amber-800"
      >
        {loading ? (
          <svg className="h-5 w-5 animate-spin" fill="none" viewBox="0 0 24 24">
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
        Request Restore
      </button>
      <p className="text-sm text-gray-600 dark:text-gray-400">
        This audiobook is archived. Restoring takes about 3–5 hours; you can leave the page.
      </p>
      {error && (
        <p className="text-sm text-red-600 dark:text-red-400" role="alert">
          Couldn&apos;t start the restore. Please try again.
        </p>
      )}
    </div>
  );
}
