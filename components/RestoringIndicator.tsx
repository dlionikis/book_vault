'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';

interface RestoringIndicatorProps {
  bookId: string;
  estimatedCompletion?: string | null;
}

/**
 * Shown on the detail page while a book's audio is being restored. Polls
 * /api/books/{id}/restore-status every 30s; when it flips to available it
 * refreshes the page so the server re-renders the Play CTA.
 */
export default function RestoringIndicator({
  bookId,
  estimatedCompletion,
}: RestoringIndicatorProps) {
  const router = useRouter();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const interval = setInterval(async () => {
      try {
        const res = await fetch(`/api/books/${bookId}/restore-status`);
        if (!res.ok) return;
        const data = await res.json();
        if (data.status === 'available') {
          setReady(true);
          clearInterval(interval);
          router.refresh();
        }
      } catch {
        // transient — keep polling
      }
    }, 30_000);

    return () => clearInterval(interval);
  }, [bookId, router]);

  const eta = estimatedCompletion
    ? new Date(estimatedCompletion).toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : null;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2 rounded-full bg-blue-600 px-6 py-3 font-medium text-white dark:bg-blue-700">
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
        {ready ? 'Ready — refreshing…' : 'Restoring from archive…'}
      </div>
      <p className="text-sm text-gray-600 dark:text-gray-400">
        {eta ? `Expected ready around ${eta}.` : 'This takes about 3–5 hours.'} You&apos;ll get a
        notification when it&apos;s ready.
      </p>
    </div>
  );
}
