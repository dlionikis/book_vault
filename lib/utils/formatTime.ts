/**
 * Format a duration in seconds as M:SS, or H:MM:SS once it reaches an hour.
 *
 * Pass `forceHours` to always render H:MM:SS — the audio player uses this so
 * the timestamp width doesn't jump when playback crosses the hour mark.
 */
export function formatTime(seconds: number, options?: { forceHours?: boolean }): string {
  if (!seconds || !isFinite(seconds) || seconds < 0) {
    return options?.forceHours ? '0:00:00' : '0:00';
  }

  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  if (hrs > 0 || options?.forceHours) {
    return `${hrs}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}
