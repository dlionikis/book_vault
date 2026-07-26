'use client';

import { useCallback, useSyncExternalStore } from 'react';

export type ViewMode = 'books' | 'series';

/** localStorage keys — Catalog and Library persist independently (requirements Q1). */
export const CATALOG_VIEW_MODE_KEY = 'bookvault.catalogViewMode';
export const LIBRARY_VIEW_MODE_KEY = 'bookvault.libraryViewMode';

function readStoredMode(storageKey: string): ViewMode {
  try {
    return window.localStorage.getItem(storageKey) === 'series' ? 'series' : 'books';
  } catch {
    // Private browsing / storage disabled — fall back to the default.
    return 'books';
  }
}

/**
 * Subscribers for in-tab mode changes, keyed by storage key.
 *
 * The `storage` event only fires in *other* tabs, so a same-tab write has to
 * notify listeners itself for useSyncExternalStore to re-render.
 */
const listeners = new Map<string, Set<() => void>>();

function subscribe(storageKey: string, onChange: () => void): () => void {
  let forKey = listeners.get(storageKey);
  if (!forKey) {
    forKey = new Set();
    listeners.set(storageKey, forKey);
  }
  forKey.add(onChange);

  // Cross-tab: mirror a change made to this key in another tab.
  const onStorage = (event: StorageEvent) => {
    if (event.key === storageKey) onChange();
  };
  window.addEventListener('storage', onStorage);

  return () => {
    forKey.delete(onChange);
    window.removeEventListener('storage', onStorage);
  };
}

function writeStoredMode(storageKey: string, mode: ViewMode): void {
  try {
    window.localStorage.setItem(storageKey, mode);
  } catch {
    // Persistence is best-effort — still notify so the UI reflects the choice.
  }
  listeners.get(storageKey)?.forEach((listener) => listener());
}

/**
 * Reads and persists a page's Books/Series view mode in localStorage.
 *
 * Modeled as an external store rather than effect-synced state: the server
 * snapshot is always 'books' (so SSR markup matches the first client render),
 * and the client snapshot reads localStorage directly. `hydrated` tells callers
 * whether the returned mode reflects real stored state yet, so they can hold
 * off on fetching until it does.
 */
export function useViewMode(storageKey: string): {
  mode: ViewMode;
  setMode: (mode: ViewMode) => void;
  hydrated: boolean;
} {
  const subscribeToKey = useCallback(
    (onChange: () => void) => subscribe(storageKey, onChange),
    [storageKey]
  );

  const mode = useSyncExternalStore(
    subscribeToKey,
    () => readStoredMode(storageKey),
    () => 'books' as ViewMode
  );

  // False during SSR and the hydration render, true once running on the client.
  const hydrated = useSyncExternalStore(
    subscribeToKey,
    () => true,
    () => false
  );

  const setMode = useCallback((next: ViewMode) => writeStoredMode(storageKey, next), [storageKey]);

  return { mode, setMode, hydrated };
}

interface ViewModeToggleProps {
  mode: ViewMode;
  onChange: (mode: ViewMode) => void;
}

const OPTIONS: { value: ViewMode; label: string }[] = [
  { value: 'books', label: 'Books' },
  { value: 'series', label: 'Series' },
];

/**
 * Segmented control for switching a page between Books and Series display.
 *
 * Presentational only — the caller owns the mode state (see useViewMode for the
 * localStorage-backed version used by the Catalog and Library pages).
 *
 * @param mode - Currently active view mode
 * @param onChange - Called with the newly selected mode
 *
 * @example
 * const { mode, setMode } = useViewMode(CATALOG_VIEW_MODE_KEY);
 * <ViewModeToggle mode={mode} onChange={setMode} />
 */
export default function ViewModeToggle({ mode, onChange }: ViewModeToggleProps) {
  return (
    <div
      role="group"
      aria-label="View mode"
      className="inline-flex rounded-md border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 p-0.5 shadow-sm"
    >
      {OPTIONS.map((option) => {
        const isActive = mode === option.value;
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={isActive}
            onClick={() => onChange(option.value)}
            className={`px-3 py-1.5 text-sm font-medium rounded transition-colors ${
              isActive
                ? 'bg-blue-600 text-white'
                : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700'
            }`}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
