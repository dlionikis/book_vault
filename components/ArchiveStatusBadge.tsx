import type { Book } from '@/lib/types';

interface ArchiveStatusBadgeProps {
  status: Book['archiveStatus'];
  /** Icon-only overlay for book cards; full label + text elsewhere. */
  compact?: boolean;
}

/**
 * Availability badge for archived / restoring audiobooks. Renders nothing when
 * the audio is available (the common case), so it can be dropped anywhere.
 *
 * - archived  → snowflake, amber
 * - restoring → spinner, blue
 */
export default function ArchiveStatusBadge({ status, compact = false }: ArchiveStatusBadgeProps) {
  if (status === 'available') return null;

  const isRestoring = status === 'restoring';
  const label = isRestoring ? 'Restoring' : 'Archived';

  const icon = isRestoring ? (
    <svg className="h-3.5 w-3.5 animate-spin" fill="none" viewBox="0 0 24 24" aria-hidden="true">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
      />
    </svg>
  ) : (
    <svg className="h-3.5 w-3.5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      {/* snowflake */}
      <path d="M11 2h2v20h-2z" />
      <path d="M2 11h20v2H2z" />
      <path d="M4.93 3.51l15.56 15.56-1.42 1.42L3.51 4.93zM19.07 3.51l1.42 1.42L4.93 20.49l-1.42-1.42z" />
    </svg>
  );

  const color = isRestoring
    ? 'bg-blue-600/90 text-white dark:bg-blue-700/90'
    : 'bg-amber-500/90 text-white dark:bg-amber-600/90';

  if (compact) {
    return (
      <span
        className={`absolute right-2 top-2 z-10 inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium shadow ${color}`}
        title={isRestoring ? 'Restoring from archive (~3-5 hours)' : 'Archived — restore required'}
        aria-label={label}
      >
        {icon}
      </span>
    );
  }

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-medium ${color}`}
    >
      {icon}
      {label}
    </span>
  );
}
