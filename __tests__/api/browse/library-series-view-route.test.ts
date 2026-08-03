/**
 * Route test for GET /api/browse/library-series-view. Pins auth, page/limit
 * wiring, and that the authenticated user's id is threaded through as the
 * library scope. The merge/pagination algorithm itself is covered at the lib
 * level in __tests__/lib/catalog-series-view.test.ts.
 */

import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  // requireUser re-checks the account exists on the bearer path (SEC-2).
  prisma: { user: { findUnique: jest.fn() } },
}));
jest.mock('@/lib/catalog-series-view', () => ({
  getCatalogSeriesView: jest.fn(),
}));

import { GET as getLibrarySeriesViewRoute } from '@/app/api/browse/library-series-view/route';
import { getCatalogSeriesView } from '@/lib/catalog-series-view';

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockGetCatalogSeriesView = getCatalogSeriesView as jest.MockedFunction<
  typeof getCatalogSeriesView
>;

function authenticate(userId = 'user-123') {
  mockGetAuthUserFromRequest.mockResolvedValue({ id: userId, username: 'testuser' });
  // requireUser then confirms the row still exists (SEC-2).
  (require('@/lib/db').prisma.user.findUnique as jest.Mock).mockResolvedValue({ id: userId });
}

const makeRequest = (query = '') =>
  new NextRequest(`http://localhost:3000/api/browse/library-series-view${query}`);

beforeEach(() => {
  jest.resetAllMocks();
  mockGetServerSession.mockResolvedValue(null);
  mockGetAuthUserFromRequest.mockResolvedValue(null);
});

describe('GET /api/browse/library-series-view', () => {
  it('returns 401 unauthenticated', async () => {
    const response = await getLibrarySeriesViewRoute(makeRequest());
    expect(response.status).toBe(401);
    expect(mockGetCatalogSeriesView).not.toHaveBeenCalled();
  });

  it('scopes the query to the authenticated user', async () => {
    authenticate('user-456');
    mockGetCatalogSeriesView.mockResolvedValue({
      results: [],
      pagination: { page: 1, limit: 20, total: 0, pages: 0 },
    });

    const response = await getLibrarySeriesViewRoute(makeRequest());

    expect(response.status).toBe(200);
    expect(mockGetCatalogSeriesView).toHaveBeenCalledWith(1, 20, {
      scope: 'library',
      userId: 'user-456',
    });
  });

  it('passes through page and limit query params', async () => {
    authenticate();
    mockGetCatalogSeriesView.mockResolvedValue({
      results: [],
      pagination: { page: 2, limit: 5, total: 0, pages: 0 },
    });

    await getLibrarySeriesViewRoute(makeRequest('?page=2&limit=5'));

    expect(mockGetCatalogSeriesView).toHaveBeenCalledWith(2, 5, {
      scope: 'library',
      userId: 'user-123',
    });
  });

  it('returns 500 when the query function throws', async () => {
    authenticate();
    mockGetCatalogSeriesView.mockRejectedValue(new Error('db exploded'));

    const response = await getLibrarySeriesViewRoute(makeRequest());

    expect(response.status).toBe(500);
  });
});
