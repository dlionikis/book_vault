/**
 * Tests for GET /api/books/[id]/stream
 *
 * Phase 0 of the S3 archive restore workflow: on-demand stream URL generation.
 * The endpoint delegates URL construction to getAudioUrl() (which branches on
 * isS3Enabled internally), so we mock that seam to exercise both the dev-local
 * and production-presigned shapes.
 */

import { GET } from '@/app/api/books/[id]/stream/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { getAudioUrl } from '@/lib/media';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    book: {
      findUnique: jest.fn(),
    },
  },
}));
jest.mock('@/lib/media', () => ({
  getAudioUrl: jest.fn(),
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

import { isS3Enabled } from '@/lib/s3';
import { getArchiveState, initiateRestore, setBookAvailability } from '@/lib/restore';

const mockIsS3Enabled = isS3Enabled as jest.MockedFunction<typeof isS3Enabled>;
const mockGetArchiveState = getArchiveState as jest.MockedFunction<typeof getArchiveState>;
const mockInitiateRestore = initiateRestore as jest.MockedFunction<typeof initiateRestore>;
const mockSetBookAvailability = setBookAvailability as jest.MockedFunction<
  typeof setBookAvailability
>;

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockGetAudioUrl = getAudioUrl as jest.MockedFunction<typeof getAudioUrl>;

const BOOK_ID = '123e4567-e89b-12d3-a456-426614174000';

function makeRequest(): NextRequest {
  return new NextRequest(`http://localhost:3000/api/books/${BOOK_ID}/stream`);
}

function authenticate() {
  mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-123', username: 'testuser' });
}

describe('GET /api/books/[id]/stream', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(null);
  });

  it('returns 401 for unauthenticated requests', async () => {
    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });

    expect(response.status).toBe(401);
    expect(prisma.book.findUnique).not.toHaveBeenCalled();
  });

  it('returns 400 for a malformed book ID', async () => {
    authenticate();

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: 'not-a-uuid' }) });

    expect(response.status).toBe(400);
    expect(prisma.book.findUnique).not.toHaveBeenCalled();
  });

  it('returns 404 for a non-existent book', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue(null);

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });

    expect(response.status).toBe(404);
  });

  it('returns 400 when the book has no audio file', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({ id: BOOK_ID, audioUrl: null });

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });

    expect(response.status).toBe(400);
    expect(mockGetAudioUrl).not.toHaveBeenCalled();
  });

  it('returns 200 with a local /api/audio URL in development', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'Book Title [ASIN]/audio.m4b',
    });
    mockGetAudioUrl.mockResolvedValue(
      'http://localhost:3000/api/audio/Book%20Title%20%5BASIN%5D/audio.m4b'
    );

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe('available');
    expect(body.streamUrl).toContain('/api/audio/');
    expect(body.bookId).toBe(BOOK_ID);
    expect(typeof body.expiresAt).toBe('string');
    expect(mockGetAudioUrl).toHaveBeenCalledWith('Book Title [ASIN]/audio.m4b');
  });

  it('returns 200 with a presigned S3 URL in production', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'books/audio.m4b',
    });
    mockGetAudioUrl.mockResolvedValue(
      'https://book-vault-media.s3.amazonaws.com/books/audio.m4b?X-Amz-Signature=abc'
    );

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe('available');
    expect(body.streamUrl).toContain('X-Amz-Signature');
  });

  it('accepts a bearer-authenticated (mobile) request', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue({ id: 'mobile-user', username: 'mobile' });
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'books/audio.m4b',
    });
    mockGetAudioUrl.mockResolvedValue('https://example.com/signed');

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });

    expect(response.status).toBe(200);
  });

  it('returns 500 when URL generation throws', async () => {
    authenticate();
    (prisma.book.findUnique as jest.Mock).mockResolvedValue({
      id: BOOK_ID,
      audioUrl: 'books/audio.m4b',
    });
    mockGetAudioUrl.mockRejectedValue(new Error('S3 signing failed'));

    const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });

    expect(response.status).toBe(500);
  });

  describe('archive detection (S3 enabled)', () => {
    const REQUESTED_AT = new Date('2026-07-19T12:00:00.000Z');

    beforeEach(() => {
      mockIsS3Enabled.mockReturnValue(true);
      (prisma.book.findUnique as jest.Mock).mockResolvedValue({
        id: BOOK_ID,
        audioUrl: 'books/audio.m4b',
        audioAvailability: 'AVAILABLE',
      });
    });

    it('returns 202 restoring and initiates a restore when the file is archived', async () => {
      authenticate();
      mockGetArchiveState.mockResolvedValue({ archived: true, restoreOngoing: false });
      mockInitiateRestore.mockResolvedValue({
        id: 'req-1',
        requestedAt: REQUESTED_AT,
      } as never);

      const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });
      const body = await response.json();

      expect(response.status).toBe(202);
      expect(body.status).toBe('restoring');
      expect(body.requestedAt).toBe(REQUESTED_AT.toISOString());
      // ETA = requestedAt + 5h (single archive tier)
      expect(body.estimatedCompletion).toBe('2026-07-19T17:00:00.000Z');
      expect(mockInitiateRestore).toHaveBeenCalledWith(
        { id: BOOK_ID, audioUrl: 'books/audio.m4b' },
        'user-123'
      );
      // No stream URL is generated for an archived file
      expect(mockGetAudioUrl).not.toHaveBeenCalled();
    });

    it('self-heals a stale cached availability when the file is actually available', async () => {
      authenticate();
      (prisma.book.findUnique as jest.Mock).mockResolvedValue({
        id: BOOK_ID,
        audioUrl: 'books/audio.m4b',
        audioAvailability: 'ARCHIVED', // stale — HeadObject says available
      });
      mockGetArchiveState.mockResolvedValue({ archived: false, restoreOngoing: false });
      mockGetAudioUrl.mockResolvedValue('https://example.com/signed');

      const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });
      const body = await response.json();

      expect(response.status).toBe(200);
      expect(body.status).toBe('available');
      expect(mockSetBookAvailability).toHaveBeenCalledWith(BOOK_ID, 'AVAILABLE');
      expect(mockInitiateRestore).not.toHaveBeenCalled();
    });

    it('does not touch the cache when it already says AVAILABLE', async () => {
      authenticate();
      mockGetArchiveState.mockResolvedValue({ archived: false, restoreOngoing: false });
      mockGetAudioUrl.mockResolvedValue('https://example.com/signed');

      const response = await GET(makeRequest(), { params: Promise.resolve({ id: BOOK_ID }) });

      expect(response.status).toBe(200);
      expect(mockSetBookAvailability).not.toHaveBeenCalled();
    });
  });
});
