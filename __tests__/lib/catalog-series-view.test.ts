/**
 * Unit tests for the shared merge/pagination algorithm behind the Series-mode
 * combined feed (docs/plans/series-view-toggle-implementation.md, "Pagination
 * algorithm"). Mocks Prisma directly to pin the 7-step algorithm — interleave
 * ordering, page-boundary slicing, cover derivation, and library scoping —
 * without needing a real database.
 */

import { prisma } from '@/lib/db';
import { getCatalogSeriesView } from '@/lib/catalog-series-view';

jest.mock('@/lib/media', () => ({
  getCoverUrl: async (path: string | null) => (path ? `https://example.com/${path}` : null),
  getAudioUrl: async (path: string | null) => (path ? `https://example.com/${path}` : null),
}));

jest.mock('@/lib/db', () => ({
  prisma: {
    series: { findMany: jest.fn() },
    book: { findMany: jest.fn() },
    bookSeries: { findMany: jest.fn() },
    userList: { findFirst: jest.fn() },
    userListBook: { findMany: jest.fn() },
  },
}));

const mockPrisma = prisma as unknown as {
  series: { findMany: jest.Mock };
  book: { findMany: jest.Mock };
  bookSeries: { findMany: jest.Mock };
  userList: { findFirst: jest.Mock };
  userListBook: { findMany: jest.Mock };
};

/** Minimal book shape satisfying BOOK_INCLUDE's nested relations. */
function makeBook(id: string, title: string, coverUrl: string | null = null) {
  return {
    id,
    asin: `ASIN-${id}`,
    title,
    description: null,
    publisherSummary: null,
    runtimeMinutes: null,
    releaseDate: null,
    publisher: null,
    coverUrl,
    audioUrl: null,
    metadata: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    audioAvailability: 'AVAILABLE',
    availabilityCheckedAt: null,
    authors: [],
    narrators: [],
    series: [],
    categories: [],
  };
}

function makeSeries(id: string, title: string, bookCount: number) {
  return { id, asin: null, title, _count: { books: bookCount } };
}

beforeEach(() => {
  // resetAllMocks (not clearAllMocks) — clearAllMocks leaves queued
  // mockResolvedValueOnce() values in place, which would leak into later
  // tests since each test only partially drains its own queue when a call
  // is skipped (e.g. an empty catalog short-circuits some Prisma calls).
  jest.resetAllMocks();
});

describe('getCatalogSeriesView (catalog scope)', () => {
  it('interleaves series and standalone books alphabetically by title', async () => {
    // Sort-key queries (step 1): series titles "Beta", "Delta"; standalone books "Alpha", "Charlie".
    mockPrisma.series.findMany
      .mockResolvedValueOnce([
        { id: 'series-beta', title: 'Beta' },
        { id: 'series-delta', title: 'Delta' },
      ])
      // Step 4: full series records for this page.
      .mockResolvedValueOnce([
        makeSeries('series-beta', 'Beta', 3),
        makeSeries('series-delta', 'Delta', 1),
      ]);

    mockPrisma.book.findMany
      .mockResolvedValueOnce([
        { id: 'book-alpha', title: 'Alpha' },
        { id: 'book-charlie', title: 'Charlie' },
      ])
      // Step 4: full book records for this page.
      .mockResolvedValueOnce([
        makeBook('book-alpha', 'Alpha'),
        makeBook('book-charlie', 'Charlie'),
      ]);

    // Step 5: cover derivation lookups (no covers in this test).
    mockPrisma.bookSeries.findMany.mockResolvedValue([]);

    const result = await getCatalogSeriesView(1, 20, { scope: 'catalog' });

    const titles = result.results.map((r) => r.series?.title ?? r.book?.title);
    expect(titles).toEqual(['Alpha', 'Beta', 'Charlie', 'Delta']);
    expect(result.pagination).toEqual({ page: 1, limit: 20, total: 4, pages: 1 });
  });

  it('slices correctly across a page boundary with a series/book title tie region', async () => {
    // 5 items total, alphabetical: Apple(book) Banana(series) Cherry(book) Date(series) Fig(book)
    // limit=2 → page 2 should be exactly [Cherry, Date].
    mockPrisma.series.findMany
      .mockResolvedValueOnce([
        { id: 'series-banana', title: 'Banana' },
        { id: 'series-date', title: 'Date' },
      ])
      .mockResolvedValueOnce([makeSeries('series-date', 'Date', 2)]);

    mockPrisma.book.findMany
      .mockResolvedValueOnce([
        { id: 'book-apple', title: 'Apple' },
        { id: 'book-cherry', title: 'Cherry' },
        { id: 'book-fig', title: 'Fig' },
      ])
      .mockResolvedValueOnce([makeBook('book-cherry', 'Cherry')]);

    mockPrisma.bookSeries.findMany.mockResolvedValue([]);

    const result = await getCatalogSeriesView(2, 2, { scope: 'catalog' });

    const titles = result.results.map((r) => r.series?.title ?? r.book?.title);
    expect(titles).toEqual(['Cherry', 'Date']);
    expect(result.pagination).toEqual({ page: 2, limit: 2, total: 5, pages: 3 });
  });

  it('derives a series cover from its lowest-sequence book with a non-null coverUrl', async () => {
    mockPrisma.series.findMany
      .mockResolvedValueOnce([{ id: 'series-1', title: 'Series One' }])
      .mockResolvedValueOnce([makeSeries('series-1', 'Series One', 2)]);
    mockPrisma.book.findMany.mockResolvedValueOnce([]).mockResolvedValueOnce([]);

    // sequence 1 has no cover, sequence 2 does — expect sequence 2's cover.
    mockPrisma.bookSeries.findMany.mockResolvedValueOnce([
      { seriesId: 'series-1', sequence: 1, book: { coverUrl: null } },
      { seriesId: 'series-1', sequence: 2, book: { coverUrl: 'covers/book2.jpg' } },
    ]);

    const result = await getCatalogSeriesView(1, 20, { scope: 'catalog' });

    expect(result.results[0].series?.coverUrl).toBe('https://example.com/covers/book2.jpg');
  });

  it('returns a null coverUrl when no book in the series has cover art', async () => {
    mockPrisma.series.findMany
      .mockResolvedValueOnce([{ id: 'series-1', title: 'Series One' }])
      .mockResolvedValueOnce([makeSeries('series-1', 'Series One', 1)]);
    mockPrisma.book.findMany.mockResolvedValueOnce([]).mockResolvedValueOnce([]);
    mockPrisma.bookSeries.findMany.mockResolvedValueOnce([
      { seriesId: 'series-1', sequence: 1, book: { coverUrl: null } },
    ]);

    const result = await getCatalogSeriesView(1, 20, { scope: 'catalog' });

    expect(result.results[0].series?.coverUrl).toBeNull();
  });

  it('returns an empty result set for an empty catalog', async () => {
    mockPrisma.series.findMany.mockResolvedValueOnce([]);
    mockPrisma.book.findMany.mockResolvedValueOnce([]);

    const result = await getCatalogSeriesView(1, 20, { scope: 'catalog' });

    expect(result.results).toEqual([]);
    expect(result.pagination).toEqual({ page: 1, limit: 20, total: 0, pages: 0 });
  });

  it('handles a single-item catalog', async () => {
    mockPrisma.series.findMany.mockResolvedValueOnce([]);
    mockPrisma.book.findMany
      .mockResolvedValueOnce([{ id: 'book-1', title: 'Only Book' }])
      .mockResolvedValueOnce([makeBook('book-1', 'Only Book')]);

    const result = await getCatalogSeriesView(1, 20, { scope: 'catalog' });

    expect(result.results).toHaveLength(1);
    expect(result.results[0].book?.title).toBe('Only Book');
    expect(result.pagination).toEqual({ page: 1, limit: 20, total: 1, pages: 1 });
  });
});

describe('getCatalogSeriesView (library scope)', () => {
  it('returns an empty result when the user has no library list', async () => {
    mockPrisma.userList.findFirst.mockResolvedValue(null);

    const result = await getCatalogSeriesView(1, 20, { scope: 'library', userId: 'user-1' });

    expect(result.results).toEqual([]);
    expect(result.pagination.total).toBe(0);
  });

  it('includes ownedCount on library-scoped series items', async () => {
    mockPrisma.userList.findFirst.mockResolvedValue({ id: 'list-1' });
    mockPrisma.bookSeries.findMany
      // getLibrarySortKeys: owned series ids (distinct)
      .mockResolvedValueOnce([{ seriesId: 'series-1' }])
      // getSeriesCoverPaths (step 5)
      .mockResolvedValueOnce([{ seriesId: 'series-1', sequence: 1, book: { coverUrl: null } }])
      // getOwnedCounts
      .mockResolvedValueOnce([{ seriesId: 'series-1' }, { seriesId: 'series-1' }]);
    mockPrisma.userListBook.findMany.mockResolvedValueOnce([]); // standalone owned books: none
    mockPrisma.series.findMany
      .mockResolvedValueOnce([{ id: 'series-1', title: 'Owned Series' }]) // sort keys
      .mockResolvedValueOnce([makeSeries('series-1', 'Owned Series', 5)]); // full record

    const result = await getCatalogSeriesView(1, 20, { scope: 'library', userId: 'user-1' });

    expect(result.results[0].series).toMatchObject({
      title: 'Owned Series',
      bookCount: 5,
      ownedCount: 2,
    });
  });

  it('renders a standalone owned book with its library addedAt timestamp', async () => {
    const addedAt = new Date('2026-01-15T00:00:00Z');
    mockPrisma.userList.findFirst.mockResolvedValue({ id: 'list-1' });
    mockPrisma.bookSeries.findMany.mockResolvedValueOnce([]); // no owned series
    mockPrisma.userListBook.findMany.mockResolvedValueOnce([
      { bookId: 'book-1', addedAt, book: { title: 'Owned Standalone' } },
    ]);
    mockPrisma.series.findMany.mockResolvedValueOnce([]); // no owned series → no series records fetch
    mockPrisma.book.findMany.mockResolvedValueOnce([makeBook('book-1', 'Owned Standalone')]);

    const result = await getCatalogSeriesView(1, 20, { scope: 'library', userId: 'user-1' });

    expect(result.results).toHaveLength(1);
    expect(result.results[0].book).toMatchObject({
      title: 'Owned Standalone',
      addedAt: addedAt.toISOString(),
    });
  });
});
