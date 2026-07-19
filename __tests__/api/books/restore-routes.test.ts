/**
 * Route tests for the restore workflow endpoints:
 *   POST /api/books/{id}/restore
 *   GET  /api/books/{id}/restore-status
 *   GET  /api/books/restores
 *
 * The restore lib itself (RestoreObject shape, dedup, header parsing) is
 * covered at the SDK level in __tests__/lib/restore.test.ts — these tests pin
 * the routes' branching, auth, validation, and response shapes.
 */

import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    book: {
      findUnique: jest.fn(),
    },
    mediaRestoreRequest: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
    },
  },
}));
jest.mock('@/lib/s3', () => ({
  isS3Enabled: jest.fn(() => false),
}));
jest.mock('@/lib/restore', () => ({
  ...jest.requireActual('@/lib/restore'),
  getArchiveState: jest.fn(),
  initiateRestore: jest.fn(),
  setBookAvailability: jest.fn(),
}));
jest.mock('@/lib/media', () => ({
  getCoverUrl: jest.fn(async (url: string | null) => (url ? `https://cdn/${url}` : null)),
}));

import { POST as restoreBook } from '@/app/api/books/[id]/restore/route';
import { GET as restoreStatus } from '@/app/api/books/[id]/restore-status/route';
import { GET as listRestores } from '@/app/api/books/restores/route';
import { isS3Enabled } from '@/lib/s3';
import { getArchiveState, initiateRestore, setBookAvailability } from '@/lib/restore';

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockIsS3Enabled = isS3Enabled as jest.MockedFunction<typeof isS3Enabled>;
const mockGetArchiveState = getArchiveState as jest.MockedFunction<typeof getArchiveState>;
const mockInitiateRestore = initiateRestore as jest.MockedFunction<typeof initiateRestore>;
const mockSetBookAvailability = setBookAvailability as jest.MockedFunction<
  typeof setBookAvailability
>;

const BOOK_ID = '123e4567-e89b-12d3-a456-426614174000';
const REQUESTED_AT = new Date('2026-07-19T12:00:00.000Z');

function authenticate() {
  mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-123', username: 'testuser' });
}

beforeEach(() => {
  jest.clearAllMocks();
  mockGetServerSession.mockResolvedValue(null);
  mockGetAuthUserFromRequest.mockResolvedValue(null);
  mockIsS3Enabled.mockReturnValue(false);
});

describe('POST /api/books/[id]/restore', () => {
  const makeRequest = () =>
    new NextRequest(`http://localhost:3000/api/books/${BOOK_ID}/restore`, { method: 'POST' });
  const params = () => ({ params: Promise.resolve({ id: BOOK_ID }) });

  it('returns 401 unauthenticated', async () => {
    const response = await restoreBook(makeRequest(), params());
    expect(response.status).toBe(401);
  });

  it('returns 400 for a malformed book ID', async () => {
    authenticate();
    const response = await restoreBook(makeRequest(), {
      params: Promise.resolve({ id: 'nope' }),
    });
    expect(response.status).toBe(400);
  });

  it('returns 404 for a non-existent book', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue(null);
    const response = await restoreBook(makeRequest(), params());
    expect(response.status).toBe(404);
  });

  it('returns available without touching S3 when S3 is disabled (local dev)', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'a.m4b',
      audioAvailability: 'AVAILABLE',
    });

    const response = await restoreBook(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe('available');
    expect(mockGetArchiveState).not.toHaveBeenCalled();
  });

  it('returns 202 restoring and initiates the restore for an archived file', async () => {
    authenticate();
    mockIsS3Enabled.mockReturnValue(true);
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'a.m4b',
      audioAvailability: 'ARCHIVED',
    });
    mockGetArchiveState.mockResolvedValue({ archived: true, restoreOngoing: false });
    mockInitiateRestore.mockResolvedValue({ id: 'req-1', requestedAt: REQUESTED_AT } as never);

    const response = await restoreBook(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(202);
    expect(body.status).toBe('restoring');
    expect(body.estimatedCompletion).toBe('2026-07-19T17:00:00.000Z');
    expect(mockInitiateRestore).toHaveBeenCalledWith(
      { id: BOOK_ID, audioUrl: 'a.m4b' },
      'user-123'
    );
  });

  it('self-heals and returns available when the file is not actually archived', async () => {
    authenticate();
    mockIsS3Enabled.mockReturnValue(true);
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'a.m4b',
      audioAvailability: 'ARCHIVED', // stale cache
    });
    mockGetArchiveState.mockResolvedValue({ archived: false, restoreOngoing: false });

    const response = await restoreBook(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe('available');
    expect(mockSetBookAvailability).toHaveBeenCalledWith(BOOK_ID, 'AVAILABLE');
    expect(mockInitiateRestore).not.toHaveBeenCalled();
  });
});

describe('GET /api/books/[id]/restore-status', () => {
  const makeRequest = () =>
    new NextRequest(`http://localhost:3000/api/books/${BOOK_ID}/restore-status`);
  const params = () => ({ params: Promise.resolve({ id: BOOK_ID }) });

  it('returns 401 unauthenticated', async () => {
    const response = await restoreStatus(makeRequest(), params());
    expect(response.status).toBe(401);
  });

  it('returns restoring with an ETA for a RESTORING book', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioAvailability: 'RESTORING',
    });
    (prisma.mediaRestoreRequest.findFirst as jest.Mock).mockResolvedValue({
      requestedAt: REQUESTED_AT,
      status: 'in_progress',
    });

    const response = await restoreStatus(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      status: 'restoring',
      requestedAt: REQUESTED_AT.toISOString(),
      estimatedCompletion: '2026-07-19T17:00:00.000Z',
    });
  });

  it('returns archived with the last error for an ARCHIVED book with a failed request', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioAvailability: 'ARCHIVED',
    });
    (prisma.mediaRestoreRequest.findFirst as jest.Mock).mockResolvedValue({
      requestedAt: REQUESTED_AT,
      status: 'failed',
      errorMessage: 'Restore did not complete within 24 hours',
    });

    const response = await restoreStatus(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe('archived');
    expect(body.lastError).toBe('Restore did not complete within 24 hours');
  });

  it('returns available with completedAt for an AVAILABLE book', async () => {
    authenticate();
    const completedAt = new Date('2026-07-19T16:30:00.000Z');
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioAvailability: 'AVAILABLE',
    });
    (prisma.mediaRestoreRequest.findFirst as jest.Mock).mockResolvedValue({
      requestedAt: REQUESTED_AT,
      status: 'completed',
      completedAt,
    });

    const response = await restoreStatus(makeRequest(), params());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ status: 'available', completedAt: completedAt.toISOString() });
  });
});

describe('GET /api/books/restores', () => {
  const makeRequest = () => new NextRequest('http://localhost:3000/api/books/restores');

  it('returns 401 unauthenticated', async () => {
    const response = await listRestores(makeRequest());
    expect(response.status).toBe(401);
  });

  it("lists the user's restores with derived ETAs and transformed cover URLs", async () => {
    authenticate();
    const completedAt = new Date('2026-07-18T10:00:00.000Z');
    (prisma.mediaRestoreRequest.findMany as jest.Mock).mockResolvedValue([
      {
        id: 'req-active',
        bookId: 'book-1',
        status: 'in_progress',
        requestedAt: REQUESTED_AT,
        completedAt: null,
        book: { id: 'book-1', title: 'Active Book', coverUrl: 'cover1.jpg' },
      },
      {
        id: 'req-done',
        bookId: 'book-2',
        status: 'completed',
        requestedAt: new Date('2026-07-18T05:00:00.000Z'),
        completedAt,
        book: { id: 'book-2', title: 'Done Book', coverUrl: null },
      },
    ]);

    const response = await listRestores(makeRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.restores).toHaveLength(2);
    expect(body.restores[0]).toEqual({
      id: 'req-active',
      bookId: 'book-1',
      status: 'in_progress',
      requestedAt: REQUESTED_AT.toISOString(),
      completedAt: null,
      estimatedCompletion: '2026-07-19T17:00:00.000Z',
      book: { id: 'book-1', title: 'Active Book', coverUrl: 'https://cdn/cover1.jpg' },
    });
    expect(body.restores[1].estimatedCompletion).toBeNull();
    expect(body.restores[1].completedAt).toBe(completedAt.toISOString());

    // Scoped to the requesting user, active + recent completions only
    const where = (prisma.mediaRestoreRequest.findMany as jest.Mock).mock.calls[0][0].where;
    expect(where.requestedByUserId).toBe('user-123');
    expect(where.OR).toHaveLength(2);
  });
});
