'use client';

import { ReactNode, useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import Pagination from './Pagination';
import SeriesViewGrid, { SeriesViewItem } from './SeriesViewGrid';
import ViewModeToggle, { useViewMode, ViewMode } from './ViewModeToggle';

interface SeriesViewResponse {
  results: SeriesViewItem[];
  pagination: { page: number; limit: number; total: number; pages: number };
}

interface SeriesModeSectionProps {
  /** localStorage key for this page's mode (Catalog and Library persist separately). */
  storageKey: string;
  /** Series-view endpoint for this page's scope. */
  endpoint: string;
  /** Server-rendered Books-mode content, shown when mode is 'books'. */
  children: ReactNode;
  /** Rendered to the right of the toggle in Books mode only (e.g. SortDropdown). */
  booksModeControls?: ReactNode;
  /**
   * Books-mode heading, rendered by the server.
   *
   * Note these are ReactNodes and plain strings rather than a render prop —
   * a Server Component cannot pass a function across the client boundary.
   */
  booksHeading: ReactNode;
  /** Series-mode heading title (e.g. "All Series"). */
  seriesHeadingTitle: string;
  /**
   * Template for the Series-mode count line, with `{count}` substituted for the
   * total once it loads (e.g. "({count} series)"). A plain string rather than a
   * formatter function, since functions can't cross the server/client boundary.
   */
  seriesCountTemplate?: string;
  /** Tag used for the Series-mode heading, matching the Books-mode heading's level. */
  seriesHeadingAs?: 'h1' | 'h2' | 'p';
  /** Classes for the Series-mode heading element. */
  seriesHeadingClassName?: string;
}

/**
 * Wraps a page's grid area with a Books/Series toggle.
 *
 * Books mode renders the server-rendered `children` untouched. Series mode
 * fetches the combined series feed client-side (the mode lives in localStorage,
 * which the server can't read) and renders it via SeriesViewGrid.
 *
 * @example
 * <SeriesModeSection
 *   storageKey={CATALOG_VIEW_MODE_KEY}
 *   endpoint="/api/browse/catalog-series-view"
 *   booksModeControls={<SortDropdown />}
 *   booksHeading={<h2>All Books</h2>}
 *   seriesHeadingTitle="All Series"
 * >
 *   <BookGrid books={data.books} />
 * </SeriesModeSection>
 */
export default function SeriesModeSection({
  storageKey,
  endpoint,
  children,
  booksModeControls,
  booksHeading,
  seriesHeadingTitle,
  seriesCountTemplate,
  seriesHeadingAs: SeriesHeading = 'h2',
  seriesHeadingClassName = 'text-xl font-semibold text-gray-900 dark:text-white',
}: SeriesModeSectionProps) {
  const { mode, setMode, hydrated } = useViewMode(storageKey);
  const searchParams = useSearchParams();
  const page = searchParams.get('page') || '1';

  // One state slice rather than three, so a completed request lands in a
  // single update and can't leave loading/error/data momentarily inconsistent.
  const [state, setState] = useState<{
    data: SeriesViewResponse | null;
    loading: boolean;
    error: string | null;
  }>({ data: null, loading: false, error: null });

  const loadSeriesView = useCallback(
    async (signal?: AbortSignal) => {
      try {
        const response = await fetch(`${endpoint}?page=${page}&limit=20`, { signal });
        if (!response.ok) {
          throw new Error(`Request failed with status ${response.status}`);
        }
        const json = await response.json();
        if (signal?.aborted) return;
        setState({ data: json, loading: false, error: null });
      } catch (err) {
        // An aborted request was superseded — its result is no longer wanted.
        if (signal?.aborted || (err as Error)?.name === 'AbortError') return;
        setState({ data: null, loading: false, error: 'Failed to load series. Please try again.' });
      }
    },
    [endpoint, page]
  );

  useEffect(() => {
    // Wait for the stored mode before fetching, so Books-mode visitors never
    // pay for a series request they won't see.
    if (!hydrated || mode !== 'series') return;

    const controller = new AbortController();
    // The setState inside loadSeriesView runs when the request resolves, not
    // synchronously on mount — same fetch-on-mount pattern as HealthTab.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadSeriesView(controller.signal);
    return () => controller.abort();
  }, [hydrated, mode, loadSeriesView]);

  const retry = useCallback(() => {
    setState({ data: null, loading: true, error: null });
    loadSeriesView();
  }, [loadSeriesView]);

  const { data, loading, error } = state;
  const isSeries = mode === 'series';

  return (
    <>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        {isSeries ? (
          <SeriesHeading className={seriesHeadingClassName}>
            {seriesHeadingTitle}
            {data && seriesCountTemplate && (
              // The count is a de-emphasized suffix alongside a title, but stands
              // alone (and inherits the heading's own styling) without one.
              <span
                className={
                  seriesHeadingTitle
                    ? 'ml-2 text-sm font-normal text-gray-600 dark:text-gray-400'
                    : undefined
                }
              >
                {seriesCountTemplate.replace('{count}', String(data.pagination.total))}
              </span>
            )}
          </SeriesHeading>
        ) : (
          booksHeading
        )}
        <div className="flex items-center gap-3">
          {/* Series mode is always alphabetical — sorting doesn't apply (Decision B). */}
          {!isSeries && booksModeControls}
          <ViewModeToggle mode={mode} onChange={setMode} />
        </div>
      </div>

      {!isSeries && children}

      {isSeries && error && (
        <div className="text-center py-12">
          <p className="text-sm text-red-600 dark:text-red-400 mb-4">{error}</p>
          <button
            type="button"
            onClick={retry}
            className="inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-md text-sm font-medium transition-colors"
          >
            Retry
          </button>
        </div>
      )}

      {isSeries && !error && (
        <>
          <SeriesViewGrid items={data?.results ?? []} loading={loading || !data} />
          {data && (
            <Pagination
              currentPage={data.pagination.page}
              totalPages={data.pagination.pages}
              total={data.pagination.total}
              itemName="series"
            />
          )}
        </>
      )}
    </>
  );
}
