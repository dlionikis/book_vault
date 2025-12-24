/**
 * Format runtime in minutes to "Xh Ym" format
 * @param minutes - Runtime in minutes
 * @returns Formatted string like "2h 30m"
 */
export function formatRuntime(minutes: number | undefined): string {
  if (!minutes || minutes === 0) {
    return '0h 0m';
  }

  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;

  return `${hours}h ${mins}m`;
}
