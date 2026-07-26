/**
 * Route test for GET /api/browse/catalog-series-view. Pins auth and
 * page/limit parameter wiring; the merge/pagination algorithm itself is
 * covered at the lib level in __tests__/lib/catalog-series-view.test.ts.
 */

import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/catalog-series-view', () => ({
  getCatalogSeriesView: jest.fn(),
}));

import { GET as getCatalogSeriesViewRoute } from '@/app/api/browse/catalog-series-view/route';
import { getCatalogSeriesView } from '@/lib/catalog-series-view';

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockGetCatalogSeriesView = getCatalogSeriesView as jest.MockedFunction<
  typeof getCatalogSeriesView
>;

function authenticate() {
  mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-123', username: 'testuser' });
}

const makeRequest = (query = '') =>
  new NextRequest(`http://localhost:3000/api/browse/catalog-series-view${query}`);

beforeEach(() => {
  jest.resetAllMocks();
  mockGetServerSession.mockResolvedValue(null);
  mockGetAuthUserFromRequest.mockResolvedValue(null);
});

describe('GET /api/browse/catalog-series-view', () => {
  it('returns 401 unauthenticated', async () => {
    const response = await getCatalogSeriesViewRoute(makeRequest());
    expect(response.status).toBe(401);
    expect(mockGetCatalogSeriesView).not.toHaveBeenCalled();
  });

  it('defaults to page 1, limit 20, catalog scope', async () => {
    authenticate();
    mockGetCatalogSeriesView.mockResolvedValue({
      results: [],
      pagination: { page: 1, limit: 20, total: 0, pages: 0 },
    });

    const response = await getCatalogSeriesViewRoute(makeRequest());

    expect(response.status).toBe(200);
    expect(mockGetCatalogSeriesView).toHaveBeenCalledWith(1, 20, { scope: 'catalog' });
  });

  it('passes through page and limit query params', async () => {
    authenticate();
    mockGetCatalogSeriesView.mockResolvedValue({
      results: [],
      pagination: { page: 3, limit: 10, total: 0, pages: 0 },
    });

    await getCatalogSeriesViewRoute(makeRequest('?page=3&limit=10'));

    expect(mockGetCatalogSeriesView).toHaveBeenCalledWith(3, 10, { scope: 'catalog' });
  });

  it('returns 500 when the query function throws', async () => {
    authenticate();
    mockGetCatalogSeriesView.mockRejectedValue(new Error('db exploded'));

    const response = await getCatalogSeriesViewRoute(makeRequest());

    expect(response.status).toBe(500);
  });
});
