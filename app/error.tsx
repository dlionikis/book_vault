'use client';

import { useEffect } from 'react';
import Link from 'next/link';

/**
 * Root error boundary — catches render/runtime errors in any route segment so a
 * client-side throw shows a recoverable screen instead of a white page.
 */
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  useEffect(() => {
    console.error('Route error boundary:', error);
  }, [error]);

  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Something went wrong</h1>
      <p className="mt-2 max-w-md text-gray-600 dark:text-gray-400">
        An unexpected error occurred. You can try again, or head back to your library.
      </p>
      <div className="mt-6 flex gap-3">
        <button
          onClick={reset}
          className="rounded-full bg-blue-600 px-6 py-2 font-medium text-white transition-colors hover:bg-blue-700 dark:bg-blue-700 dark:hover:bg-blue-800"
        >
          Try again
        </button>
        <Link
          href="/library"
          className="rounded-full bg-gray-200 px-6 py-2 font-medium text-gray-900 transition-colors hover:bg-gray-300 dark:bg-gray-700 dark:text-white dark:hover:bg-gray-600"
        >
          My Library
        </Link>
      </div>
    </div>
  );
}
