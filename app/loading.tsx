/**
 * Root loading UI — shown during server-component data fetches (Suspense
 * boundary) so multi-query pages don't flash a blank screen.
 */
export default function Loading() {
  return (
    <div
      className="flex min-h-[60vh] items-center justify-center"
      role="status"
      aria-label="Loading"
    >
      <div className="h-10 w-10 animate-spin rounded-full border-b-2 border-blue-600" />
    </div>
  );
}
