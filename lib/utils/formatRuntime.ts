/**
 * Format runtime in minutes to a compact "2h 30m" string.
 * Returns null when the runtime is missing so callers can render nothing.
 */
export function formatRuntime(minutes?: number | null): string | null {
  if (!minutes) return null;

  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;

  return `${hours}h ${mins}m`;
}
