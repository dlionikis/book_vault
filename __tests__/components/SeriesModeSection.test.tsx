import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { useSearchParams } from 'next/navigation';
import SeriesModeSection from '@/components/SeriesModeSection';
import { CATALOG_VIEW_MODE_KEY } from '@/components/ViewModeToggle';

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(() => ({ push: jest.fn() })),
  useSearchParams: jest.fn(),
}));

const mockUseSearchParams = useSearchParams as jest.MockedFunction<typeof useSearchParams>;

const seriesResponse = {
  results: [{ series: { id: 'series-1', title: 'The Expanse', bookCount: 9, coverUrl: null } }],
  pagination: { page: 1, limit: 20, total: 1, pages: 1 },
};

function renderSection(overrides: Partial<React.ComponentProps<typeof SeriesModeSection>> = {}) {
  return render(
    <SeriesModeSection
      storageKey={CATALOG_VIEW_MODE_KEY}
      endpoint="/api/browse/catalog-series-view"
      booksModeControls={<button type="button">Sort by</button>}
      booksHeading={<h2>All Books</h2>}
      seriesHeadingTitle="All Series"
      seriesCountTemplate="({count} series)"
      {...overrides}
    >
      <div>Books mode content</div>
    </SeriesModeSection>
  );
}

describe('SeriesModeSection', () => {
  beforeEach(() => {
    // resetAllMocks (not clearAllMocks) so queued mockResolvedValueOnce values
    // from a prior test can't leak into the next one.
    jest.resetAllMocks();
    window.localStorage.clear();
    mockUseSearchParams.mockReturnValue({ get: () => null } as never);
    global.fetch = jest.fn();
  });

  it('renders the server-rendered books content in books mode', async () => {
    renderSection();
    expect(screen.getByText('Books mode content')).toBeInTheDocument();
    expect(screen.getByText('All Books')).toBeInTheDocument();
    // Books mode must not pay for a series request.
    await waitFor(() => expect(global.fetch).not.toHaveBeenCalled());
  });

  it('shows the books-mode controls only in books mode', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => seriesResponse });
    renderSection();
    expect(screen.getByText('Sort by')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Series' }));

    await waitFor(() => expect(screen.queryByText('Sort by')).not.toBeInTheDocument());
  });

  it('fetches and renders the series feed when switched to series mode', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => seriesResponse });
    renderSection();

    fireEvent.click(screen.getByRole('button', { name: 'Series' }));

    await waitFor(() => expect(screen.getByText('The Expanse')).toBeInTheDocument());
    expect(global.fetch).toHaveBeenCalledWith(
      '/api/browse/catalog-series-view?page=1&limit=20',
      expect.objectContaining({ signal: expect.anything() })
    );
    expect(screen.queryByText('Books mode content')).not.toBeInTheDocument();
    expect(screen.getByText('All Series')).toBeInTheDocument();
  });

  it('fetches the series feed on mount when series mode was persisted', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => seriesResponse });

    renderSection();

    await waitFor(() => expect(screen.getByText('The Expanse')).toBeInTheDocument());
    expect(screen.queryByText('Books mode content')).not.toBeInTheDocument();
  });

  it('requests the page from the URL query param', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    mockUseSearchParams.mockReturnValue({ get: () => '3' } as never);
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({
        ...seriesResponse,
        pagination: { page: 3, limit: 20, total: 60, pages: 3 },
      }),
    });

    renderSection();

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/browse/catalog-series-view?page=3&limit=20',
        expect.objectContaining({ signal: expect.anything() })
      )
    );
  });

  it('uses the library endpoint when given one', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => seriesResponse });

    renderSection({ endpoint: '/api/browse/library-series-view' });

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/browse/library-series-view?page=1&limit=20',
        expect.objectContaining({ signal: expect.anything() })
      )
    );
  });

  it('shows an error with a retry action when the request fails', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    (global.fetch as jest.Mock).mockRejectedValue(new Error('network down'));

    renderSection();

    await waitFor(() =>
      expect(screen.getByText('Failed to load series. Please try again.')).toBeInTheDocument()
    );
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument();
  });

  it('treats a non-ok response as an error', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    (global.fetch as jest.Mock).mockResolvedValue({ ok: false, status: 500 });

    renderSection();

    await waitFor(() =>
      expect(screen.getByText('Failed to load series. Please try again.')).toBeInTheDocument()
    );
  });

  it('recovers when retry succeeds', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    (global.fetch as jest.Mock)
      .mockRejectedValueOnce(new Error('network down'))
      .mockResolvedValueOnce({ ok: true, json: async () => seriesResponse });

    renderSection();

    await waitFor(() => expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));

    await waitFor(() => expect(screen.getByText('The Expanse')).toBeInTheDocument());
  });

  it('renders the series count from the template once loaded', async () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({
        ...seriesResponse,
        pagination: { page: 1, limit: 20, total: 42, pages: 3 },
      }),
    });

    renderSection();

    await waitFor(() => expect(screen.getByText('(42 series)')).toBeInTheDocument());
  });

  it('persists the chosen mode across remounts', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => seriesResponse });
    const { unmount } = renderSection();

    fireEvent.click(screen.getByRole('button', { name: 'Series' }));
    await waitFor(() => expect(screen.getByText('The Expanse')).toBeInTheDocument());
    unmount();

    renderSection();
    await waitFor(() => expect(screen.getByText('The Expanse')).toBeInTheDocument());
    expect(screen.queryByText('Books mode content')).not.toBeInTheDocument();
  });
});
