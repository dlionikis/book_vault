import Link from 'next/link';

/**
 * Root 404 — used by notFound() (e.g. the book detail page) and unknown routes.
 */
export default function NotFound() {
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Page not found</h1>
      <p className="mt-2 max-w-md text-gray-600 dark:text-gray-400">
        We couldn&apos;t find what you were looking for. It may have moved, or the link may be
        broken.
      </p>
      <Link
        href="/library"
        className="mt-6 rounded-full bg-blue-600 px-6 py-2 font-medium text-white transition-colors hover:bg-blue-700 dark:bg-blue-700 dark:hover:bg-blue-800"
      >
        Go to My Library
      </Link>
    </div>
  );
}
