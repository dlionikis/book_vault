/**
 * Route test for GET /api/browse/categories.
 *
 * The interesting behavior here is ancestry resolution. Audible ships each book's
 * genre as a full ladder and the importer materializes every distinct path, so
 * `categories.name` is unique only per-parent — "Action & Adventure" legitimately
 * exists under both "Literature & Fiction" and "SF&F > Fantasy". The route returns
 * `parentPath` so clients can tell those rows apart; these tests pin that, plus
 * the visible-book filtering the list depends on.
 */

import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    category: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
  },
}));

import { GET as getCategoriesRoute } from '@/app/api/browse/categories/route';
import { prisma } from '@/lib/db';

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockFindMany = prisma.category.findMany as jest.Mock;
const mockCount = prisma.category.count as jest.Mock;

function authenticate() {
  mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-123', username: 'testuser' });
}

const makeRequest = (query = '') =>
  new NextRequest(`http://localhost:3000/api/browse/categories${query}`);

/**
 * The route issues two findMany calls: the paginated page of categories, then the
 * full id/name/parentId map used to walk ancestries. They run inside one
 * Promise.all, so dispatch on the `select` shape rather than call order.
 */
function mockCategories(
  page: Array<{ id: string; name: string; level: number; bookCount: number }>,
  ancestry: Array<{ id: string; name: string; parentId: string | null }>
) {
  mockFindMany.mockImplementation((args: { select?: unknown }) => {
    if (args?.select) return Promise.resolve(ancestry);
    return Promise.resolve(
      page.map((c) => ({
        id: c.id,
        name: c.name,
        level: c.level,
        _count: { books: c.bookCount },
      }))
    );
  });
  mockCount.mockResolvedValue(page.length);
}

beforeEach(() => {
  jest.resetAllMocks();
  mockGetServerSession.mockResolvedValue(null);
  mockGetAuthUserFromRequest.mockResolvedValue(null);
});

describe('GET /api/browse/categories', () => {
  it('returns 401 unauthenticated', async () => {
    const response = await getCategoriesRoute(makeRequest());
    expect(response.status).toBe(401);
    expect(mockFindMany).not.toHaveBeenCalled();
  });

  it('resolves the full ancestor path, not just the immediate parent', async () => {
    authenticate();
    // Two same-named leaves whose immediate parents also share a name — only the
    // grandparent tells them apart, which is exactly the case the old
    // parent-name-only response could not represent.
    mockCategories(
      [
        { id: 'leaf-a', name: 'Action & Adventure', level: 2, bookCount: 334 },
        { id: 'leaf-b', name: 'Action & Adventure', level: 3, bookCount: 5 },
      ],
      [
        { id: 'sff', name: 'Science Fiction & Fantasy', parentId: null },
        { id: 'fantasy', name: 'Fantasy', parentId: 'sff' },
        { id: 'leaf-a', name: 'Action & Adventure', parentId: 'fantasy' },
        { id: 'teen', name: 'Teen & Young Adult', parentId: null },
        { id: 'teen-sff', name: 'Science Fiction & Fantasy', parentId: 'teen' },
        { id: 'teen-fantasy', name: 'Fantasy', parentId: 'teen-sff' },
        { id: 'leaf-b', name: 'Action & Adventure', parentId: 'teen-fantasy' },
      ]
    );

    const response = await getCategoriesRoute(makeRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.results).toEqual([
      {
        id: 'leaf-a',
        name: 'Action & Adventure',
        level: 2,
        parentPath: ['Science Fiction & Fantasy', 'Fantasy'],
        bookCount: 334,
      },
      {
        id: 'leaf-b',
        name: 'Action & Adventure',
        level: 3,
        parentPath: ['Teen & Young Adult', 'Science Fiction & Fantasy', 'Fantasy'],
        bookCount: 5,
      },
    ]);
  });

  it('returns an empty path for a top-level category', async () => {
    authenticate();
    mockCategories(
      [{ id: 'root', name: 'Romance', level: 0, bookCount: 4 }],
      [{ id: 'root', name: 'Romance', parentId: null }]
    );

    const body = await (await getCategoriesRoute(makeRequest())).json();

    expect(body.results[0].parentPath).toEqual([]);
  });

  it('filters to categories with visible books and counts only those books', async () => {
    authenticate();
    mockCategories([], []);

    await getCategoriesRoute(makeRequest());

    const pageCall = mockFindMany.mock.calls.find(([args]) => !args?.select)?.[0];
    // Hidden books must not keep a dead category in the list, nor inflate its count.
    expect(pageCall.where).toEqual({ books: { some: { book: { hiddenAt: null } } } });
    expect(pageCall.include._count.select.books).toEqual({ where: { book: { hiddenAt: null } } });
    expect(mockCount).toHaveBeenCalledWith({
      where: { books: { some: { book: { hiddenAt: null } } } },
    });
  });

  it('terminates on a parent_id cycle instead of hanging', async () => {
    authenticate();
    // Not expected in real data, but an unbounded walk here would hang the request.
    mockCategories(
      [{ id: 'a', name: 'A', level: 0, bookCount: 1 }],
      [
        { id: 'a', name: 'A', parentId: 'b' },
        { id: 'b', name: 'B', parentId: 'a' },
      ]
    );

    const body = await (await getCategoriesRoute(makeRequest())).json();

    expect(body.results[0].parentPath).toEqual(['B']);
  });

  it('passes pagination through to the query', async () => {
    authenticate();
    mockCategories([], []);

    await getCategoriesRoute(makeRequest('?page=3&limit=10'));

    const pageCall = mockFindMany.mock.calls.find(([args]) => !args?.select)?.[0];
    expect(pageCall.skip).toBe(20);
    expect(pageCall.take).toBe(10);
  });
});
