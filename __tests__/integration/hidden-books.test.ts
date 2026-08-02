/**
 * Hidden books (soft hide via Book.hiddenAt)
 *
 * A book with `hiddenAt` set must disappear from every *list* surface while
 * staying reachable by direct link. These run against the real database so the
 * assertions cover the generated SQL, not a mock of it.
 *
 * See docs/hidden-books.md.
 */

import { NextRequest } from 'next/server';
import { GET as listBooks } from '@/app/api/books/route';
import { GET as search } from '@/app/api/search/route';
import { GET as suggestions } from '@/app/api/search/suggestions/route';
import { GET as browseSeries } from '@/app/api/browse/series/route';
import { GET as browseAuthors } from '@/app/api/browse/authors/route';
import { GET as browseNarrators } from '@/app/api/browse/narrators/route';
import { GET as getSeries } from '@/app/api/series/[id]/route';
import { GET as getBook } from '@/app/api/books/[id]/route';
import { prisma } from '@/lib/db';
import * as auth from '@/lib/auth';

jest.mock('@/lib/auth');

const mockGetAuthUserFromRequest = auth.getAuthUserFromRequest as jest.MockedFunction<
  typeof auth.getAuthUserFromRequest
>;

const SERIES_TITLE = 'Hidden Test Cycle';
const AUTHOR_NAME = 'Hidden Test Author';
const NARRATOR_NAME = 'Hidden Test Narrator';
const VISIBLE_ASIN = 'BHIDDENVIS';
const HIDDEN_ASIN = 'BHIDDENHID';

describe('Hidden books', () => {
  const mockUser = { id: 'hidden-test-user', username: 'test-hidden' };

  let seriesId: string;
  let visibleBookId: string;
  let hiddenBookId: string;

  const cleanup = async () => {
    await prisma.book.deleteMany({ where: { asin: { in: [VISIBLE_ASIN, HIDDEN_ASIN] } } });
    await prisma.series.deleteMany({ where: { title: SERIES_TITLE } });
    await prisma.author.deleteMany({ where: { name: AUTHOR_NAME } });
    await prisma.narrator.deleteMany({ where: { name: NARRATOR_NAME } });
    await prisma.user.deleteMany({ where: { username: mockUser.username } });
  };

  beforeAll(async () => {
    await cleanup();

    await prisma.user.create({
      data: { id: mockUser.id, username: mockUser.username, passwordHash: 'x' },
    });

    const series = await prisma.series.create({ data: { title: SERIES_TITLE } });
    seriesId = series.id;
    const author = await prisma.author.create({ data: { name: AUTHOR_NAME } });
    const narrator = await prisma.narrator.create({ data: { name: NARRATOR_NAME } });

    // One visible and one hidden book, both in the same series and by the same
    // author, so each assertion isolates the hiddenAt filter rather than the
    // absence of a relation.
    const visible = await prisma.book.create({
      data: {
        asin: VISIBLE_ASIN,
        title: 'Hidden Test Visible Volume',
        series: { create: { seriesId, sequence: 1 } },
        authors: { create: { authorId: author.id } },
        narrators: { create: { narratorId: narrator.id } },
      },
    });
    visibleBookId = visible.id;

    const hidden = await prisma.book.create({
      data: {
        asin: HIDDEN_ASIN,
        title: 'Hidden Test Hidden Volume',
        hiddenAt: new Date(),
        series: { create: { seriesId, sequence: 2 } },
        authors: { create: { authorId: author.id } },
        narrators: { create: { narratorId: narrator.id } },
      },
    });
    hiddenBookId = hidden.id;
  });

  afterAll(async () => {
    await cleanup();
  });

  beforeEach(() => {
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser as never);
  });

  // MARK: - List surfaces

  it('omits hidden books from the catalog listing', async () => {
    const res = await listBooks(new NextRequest('http://localhost/api/books?limit=100'));
    const body = await res.json();
    const asins = body.books.map((b: { asin: string }) => b.asin);

    expect(asins).toContain(VISIBLE_ASIN);
    expect(asins).not.toContain(HIDDEN_ASIN);
  });

  it('omits hidden books from search results', async () => {
    const res = await search(new NextRequest('http://localhost/api/search?q=Hidden%20Test'));
    const body = await res.json();
    const asins = body.results.map((b: { asin: string }) => b.asin);

    expect(asins).toContain(VISIBLE_ASIN);
    expect(asins).not.toContain(HIDDEN_ASIN);
  });

  it('omits hidden books from search suggestions', async () => {
    const res = await suggestions(
      new NextRequest('http://localhost/api/search/suggestions?q=Hidden%20Test')
    );
    const body = await res.json();
    const titles = body.books.map((b: { title: string }) => b.title);

    expect(titles).toContain('Hidden Test Visible Volume');
    expect(titles).not.toContain('Hidden Test Hidden Volume');
  });

  it('omits hidden books from a series detail page and its total', async () => {
    const res = await getSeries(new NextRequest(`http://localhost/api/series/${seriesId}`), {
      params: Promise.resolve({ id: seriesId }),
    });
    const body = await res.json();
    const asins = body.books.map((b: { asin: string }) => b.asin);

    expect(asins).toEqual([VISIBLE_ASIN]);
    expect(body.pagination.total).toBe(1);
  });

  // The count is the bug that hides easiest: an unfiltered _count reads "2
  // books" beside a page that lists 1.
  it('counts only visible books in browse series', async () => {
    const res = await browseSeries(new NextRequest('http://localhost/api/browse/series?limit=100'));
    const body = await res.json();
    const row = body.results.find((s: { title: string }) => s.title === SERIES_TITLE);

    expect(row).toBeDefined();
    expect(row.bookCount).toBe(1);
  });

  it('counts only visible books in browse narrators', async () => {
    const res = await browseNarrators(
      new NextRequest('http://localhost/api/browse/narrators?limit=100')
    );
    const body = await res.json();
    const row = body.results.find((n: { name: string }) => n.name === NARRATOR_NAME);

    expect(row).toBeDefined();
    expect(row.bookCount).toBe(1);
  });

  it('counts only visible books in browse authors', async () => {
    const res = await browseAuthors(
      new NextRequest('http://localhost/api/browse/authors?limit=100')
    );
    const body = await res.json();
    const row = body.results.find((a: { name: string }) => a.name === AUTHOR_NAME);

    expect(row).toBeDefined();
    expect(row.bookCount).toBe(1);
  });

  // MARK: - Direct access is deliberately preserved

  it('still serves the detail page for a hidden book', async () => {
    const res = await getBook(new NextRequest(`http://localhost/api/books/${hiddenBookId}`), {
      params: Promise.resolve({ id: hiddenBookId }),
    });

    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.asin).toBe(HIDDEN_ASIN);
  });

  // MARK: - Reversibility

  it('restores the book everywhere once hiddenAt is cleared', async () => {
    await prisma.book.update({ where: { id: hiddenBookId }, data: { hiddenAt: null } });

    try {
      const res = await listBooks(new NextRequest('http://localhost/api/books?limit=100'));
      const body = await res.json();
      const asins = body.books.map((b: { asin: string }) => b.asin);

      expect(asins).toContain(HIDDEN_ASIN);
      expect(asins).toContain(VISIBLE_ASIN);
    } finally {
      await prisma.book.update({
        where: { id: hiddenBookId },
        data: { hiddenAt: new Date() },
      });
    }
  });

  // MARK: - Whole-series hide

  it('drops the series from browse once every book in it is hidden', async () => {
    await prisma.book.update({ where: { id: visibleBookId }, data: { hiddenAt: new Date() } });

    try {
      const res = await browseSeries(
        new NextRequest('http://localhost/api/browse/series?limit=100')
      );
      const body = await res.json();
      const titles = body.results.map((s: { title: string }) => s.title);

      expect(titles).not.toContain(SERIES_TITLE);
    } finally {
      await prisma.book.update({ where: { id: visibleBookId }, data: { hiddenAt: null } });
    }
  });
});
