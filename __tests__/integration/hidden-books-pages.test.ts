/**
 * Hidden books — web page surfaces.
 *
 * Companion to hidden-books.test.ts, which covers the /api routes. This file
 * covers the *page* server components, which query the database directly rather
 * than going through the API.
 *
 * That distinction is the whole point of this file. PR #157 added the visibility
 * filter to every API route and its test suite passed, while the entire web UI
 * still listed hidden books — because each page had its own hand-rolled copy of
 * the query. Both surfaces now share lib/queries/*, and these tests fail if a
 * page ever regains its own unfiltered query.
 *
 * See docs/hidden-books.md.
 */

import { prisma } from '@/lib/db';
import { getCatalogBooks, getLibraryListBooks } from '@/lib/queries/catalog-books';
import { searchBooks } from '@/lib/queries/search-books';
import { getEntityBooksPage } from '@/lib/queries/entity-books';
import { getBrowseEntities } from '@/lib/queries/browse-entities';

const SERIES_TITLE = 'Hidden Pages Cycle';
const AUTHOR_NAME = 'Hidden Pages Author';
const NARRATOR_NAME = 'Hidden Pages Narrator';
const CATEGORY_NAME = 'Hidden Pages Category';
const VISIBLE_ASIN = 'BPAGEVIS';
const HIDDEN_ASIN = 'BPAGEHID';
const SEARCH_TERM = 'Hidden Pages';

const PAGE = { skip: 0, limit: 100 };

describe('Hidden books — page query paths', () => {
  const username = 'test-hidden-pages';

  let userId: string;
  let seriesId: string;
  let authorId: string;
  let narratorId: string;
  let categoryId: string;
  let visibleBookId: string;
  let hiddenBookId: string;

  const cleanup = async () => {
    await prisma.book.deleteMany({ where: { asin: { in: [VISIBLE_ASIN, HIDDEN_ASIN] } } });
    await prisma.series.deleteMany({ where: { title: SERIES_TITLE } });
    await prisma.author.deleteMany({ where: { name: AUTHOR_NAME } });
    await prisma.narrator.deleteMany({ where: { name: NARRATOR_NAME } });
    await prisma.category.deleteMany({ where: { name: CATEGORY_NAME } });
    await prisma.user.deleteMany({ where: { username } });
  };

  beforeAll(async () => {
    await cleanup();

    const user = await prisma.user.create({
      data: { username, passwordHash: 'x' },
    });
    userId = user.id;

    const series = await prisma.series.create({ data: { title: SERIES_TITLE } });
    seriesId = series.id;
    const author = await prisma.author.create({ data: { name: AUTHOR_NAME } });
    authorId = author.id;
    const narrator = await prisma.narrator.create({ data: { name: NARRATOR_NAME } });
    narratorId = narrator.id;
    const category = await prisma.category.create({ data: { name: CATEGORY_NAME, level: 0 } });
    categoryId = category.id;

    // One visible and one hidden book sharing every relation, so each assertion
    // isolates the hiddenAt filter rather than the absence of a relation.
    const relations = {
      series: { create: { seriesId } },
      authors: { create: { authorId } },
      narrators: { create: { narratorId } },
      categories: { create: { categoryId } },
    };

    const visible = await prisma.book.create({
      data: {
        asin: VISIBLE_ASIN,
        title: `${SEARCH_TERM} Visible Volume`,
        ...relations,
        series: { create: { seriesId, sequence: 1 } },
      },
    });
    visibleBookId = visible.id;

    const hidden = await prisma.book.create({
      data: {
        asin: HIDDEN_ASIN,
        title: `${SEARCH_TERM} Hidden Volume`,
        hiddenAt: new Date(),
        ...relations,
        series: { create: { seriesId, sequence: 2 } },
      },
    });
    hiddenBookId = hidden.id;

    // Put both books in the user's library so the library page has something to
    // filter — a hidden book must leave the shelf without losing the row.
    const library = await prisma.userList.create({
      data: { userId, name: 'My Library' },
    });
    await prisma.userListBook.createMany({
      data: [
        { listId: library.id, bookId: visibleBookId },
        { listId: library.id, bookId: hiddenBookId },
      ],
    });
  });

  afterAll(async () => {
    await cleanup();
  });

  // MARK: - The bug this PR fixes

  it('omits hidden books from the search page query', async () => {
    const { books, total } = await searchBooks(SEARCH_TERM, PAGE);
    const asins = books.map((b) => b.asin);

    expect(asins).toContain(VISIBLE_ASIN);
    expect(asins).not.toContain(HIDDEN_ASIN);
    expect(total).toBe(1);
  });

  it('omits hidden books from the catalog page query', async () => {
    const { books } = await getCatalogBooks(PAGE);
    const asins = books.map((b) => b.asin);

    expect(asins).toContain(VISIBLE_ASIN);
    expect(asins).not.toContain(HIDDEN_ASIN);
  });

  it('omits hidden books from the library page query', async () => {
    const { listBooks } = await getLibraryListBooks(userId);
    const asins = listBooks.map((lb) => lb.book.asin);

    expect(asins).toContain(VISIBLE_ASIN);
    expect(asins).not.toContain(HIDDEN_ASIN);
  });

  // MARK: - Entity detail pages

  it.each([
    ['author', () => authorId] as const,
    ['narrator', () => narratorId] as const,
    ['series', () => seriesId] as const,
    ['category', () => categoryId] as const,
  ])('omits hidden books from the %s detail page and its total', async (kind, id) => {
    const { books, total } = await getEntityBooksPage(kind, id(), PAGE);
    const asins = books.map((b) => b.asin);

    expect(asins).toEqual([VISIBLE_ASIN]);
    // The count is the bug that hides easiest: an unfiltered total reads
    // "2 books" above a grid showing 1.
    expect(total).toBe(1);
  });

  // MARK: - Browse pages

  // Labels are module constants, so they can be inlined here; the entity ids
  // above must stay thunked because they're assigned in beforeAll.
  it.each([
    ['author', AUTHOR_NAME] as const,
    ['narrator', NARRATOR_NAME] as const,
    ['series', SERIES_TITLE] as const,
    ['category', CATEGORY_NAME] as const,
  ])('counts only visible books on the browse %ss page', async (kind, label) => {
    const { entities } = await getBrowseEntities(kind, { limit: null });
    const row = entities.find((e) => e.label === label);

    expect(row).toBeDefined();
    expect(row!.bookCount).toBe(1);
  });

  // MARK: - Whole-entity hide

  it('drops the series from the browse page once every book in it is hidden', async () => {
    await prisma.book.update({ where: { id: visibleBookId }, data: { hiddenAt: new Date() } });

    try {
      const { entities } = await getBrowseEntities('series', { limit: null });
      const labels = entities.map((e) => e.label);

      expect(labels).not.toContain(SERIES_TITLE);
    } finally {
      await prisma.book.update({ where: { id: visibleBookId }, data: { hiddenAt: null } });
    }
  });

  // MARK: - Reversibility

  it('restores a hidden book to every page surface once hiddenAt is cleared', async () => {
    await prisma.book.update({ where: { id: hiddenBookId }, data: { hiddenAt: null } });

    try {
      const [{ books: searchResults }, { books: catalog }, { listBooks }] = await Promise.all([
        searchBooks(SEARCH_TERM, PAGE),
        getCatalogBooks(PAGE),
        getLibraryListBooks(userId),
      ]);

      expect(searchResults.map((b) => b.asin)).toContain(HIDDEN_ASIN);
      expect(catalog.map((b) => b.asin)).toContain(HIDDEN_ASIN);
      // The user_list_books row survived the hide, so the book returns to the
      // shelf rather than needing to be re-added.
      expect(listBooks.map((lb) => lb.book.asin)).toContain(HIDDEN_ASIN);
    } finally {
      await prisma.book.update({
        where: { id: hiddenBookId },
        data: { hiddenAt: new Date() },
      });
    }
  });
});
