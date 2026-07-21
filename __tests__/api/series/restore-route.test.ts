/**
 * Route tests for POST /api/series/{id}/restore (Phase 8, series-level restore).
 *
 * Pins auth, id validation, the archived-only filter, per-book idempotent
 * initiate, and the aggregate response shape. The restore lib itself is covered
 * at the SDK level in __tests__/lib/restore.test.ts.
 */

import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    series: { findUnique: jest.fn() },
    bookSeries: { findMany: jest.fn() },
  },
}));
jest.mock('@/lib/s3', () => ({
  isS3Enabled: jest.fn(() => false),
}));
jest.mock('@/lib/restore', () => ({
  ...jest.requireActual('@/lib/restore'),
  initiateRestore: jest.fn(),
}));

import { POST as restoreSeries } from '@/app/api/series/[id]/restore/route';
import { isS3Enabled } from '@/lib/s3';
import { initiateRestore } from '@/lib/restore';

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockIsS3Enabled = isS3Enabled as jest.MockedFunction<typeof isS3Enabled>;
const mockInitiateRestore = initiateRestore as jest.MockedFunction<typeof initiateRestore>;

const SERIES_ID = '123e4567-e89b-12d3-a456-426614174000';

function authenticate() {
  mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-123', username: 'testuser' });
}

const makeRequest = () =>
  new NextRequest(`http://localhost:3000/api/series/${SERIES_ID}/restore`, { method: 'POST' });
const params = (id: string = SERIES_ID) => ({ params: Promise.resolve({ id }) });

/** Build a bookSeries row as returned by the include. */
const sb = (
  id: string,
  title: string,
  availability: string,
  audioUrl: string | null = 'a.m4b'
) => ({
  book: { id, title, audioUrl, audioAvailability: availability },
});

beforeEach(() => {
  jest.clearAllMocks();
  mockGetServerSession.mockResolvedValue(null);
  mockGetAuthUserFromRequest.mockResolvedValue(null);
  mockIsS3Enabled.mockReturnValue(true);
  (prisma.series.findUnique as jest.Mock).mockResolvedValue({ id: SERIES_ID });
});

describe('POST /api/series/[id]/restore', () => {
  it('returns 401 unauthenticated', async () => {
    const response = await restoreSeries(makeRequest(), params());
    expect(response.status).toBe(401);
  });

  it('returns 400 for a malformed series ID', async () => {
    authenticate();
    const response = await restoreSeries(makeRequest(), params('nope'));
    expect(response.status).toBe(400);
  });

  it('returns 404 for a non-existent series', async () => {
    authenticate();
    (prisma.series.findUnique as jest.Mock).mockResolvedValue(null);
    const response = await restoreSeries(makeRequest(), params());
    expect(response.status).toBe(404);
  });

  it('restores only the archived books and reports per-book results', async () => {
    authenticate();
    (prisma.bookSeries.findMany as jest.Mock).mockResolvedValue([
      sb('book-1', 'One', 'ARCHIVED'),
      sb('book-2', 'Two', 'AVAILABLE'), // skipped
      sb('book-3', 'Three', 'ARCHIVED'),
      sb('book-4', 'Four', 'ARCHIVED', null), // no audioUrl → skipped
    ]);
    mockInitiateRestore.mockResolvedValue({ id: 'req' } as never);

    const response = await restoreSeries(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.total).toBe(2); // book-1 + book-3
    expect(body.results).toHaveLength(2);
    expect(body.results.map((r: { bookId: string }) => r.bookId)).toEqual(['book-1', 'book-3']);
    expect(body.results.every((r: { status: string }) => r.status === 'initiated')).toBe(true);
    expect(mockInitiateRestore).toHaveBeenCalledTimes(2);
    expect(mockInitiateRestore).toHaveBeenCalledWith(
      { id: 'book-1', audioUrl: 'a.m4b' },
      'user-123'
    );
  });

  it('returns total 0 when nothing is archived', async () => {
    authenticate();
    (prisma.bookSeries.findMany as jest.Mock).mockResolvedValue([sb('book-1', 'One', 'AVAILABLE')]);

    const response = await restoreSeries(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.total).toBe(0);
    expect(body.results).toEqual([]);
    expect(mockInitiateRestore).not.toHaveBeenCalled();
  });

  it('treats nothing as archived when S3 is disabled (local dev)', async () => {
    authenticate();
    mockIsS3Enabled.mockReturnValue(false);
    (prisma.bookSeries.findMany as jest.Mock).mockResolvedValue([sb('b', 'B', 'ARCHIVED')]);

    const response = await restoreSeries(makeRequest(), params());
    const body = await response.json();

    expect(body.total).toBe(0);
    expect(mockInitiateRestore).not.toHaveBeenCalled();
  });

  it('marks a book failed (and continues) when its initiate throws', async () => {
    authenticate();
    (prisma.bookSeries.findMany as jest.Mock).mockResolvedValue([
      sb('book-1', 'One', 'ARCHIVED'),
      sb('book-2', 'Two', 'ARCHIVED'),
    ]);
    mockInitiateRestore
      .mockRejectedValueOnce(new Error('boom'))
      .mockResolvedValueOnce({ id: 'req' } as never);

    const response = await restoreSeries(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.total).toBe(2);
    const byId = Object.fromEntries(body.results.map((r: { bookId: string }) => [r.bookId, r]));
    expect(byId['book-1'].status).toBe('failed');
    expect(byId['book-2'].status).toBe('initiated');
  });
});
