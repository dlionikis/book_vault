/**
 * Authorization tests for chapter re-extraction
 *
 * POST /api/books/[id]/chapters deletes and rewrites the shared Chapter table,
 * so it must be admin-only. GET remains available to any authenticated user
 * (lazy extraction on first playback is a product feature).
 */

import { POST } from '@/app/api/books/[id]/chapters/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

// Mock dependencies
jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    user: {
      findUnique: jest.fn(),
    },
    book: {
      findUnique: jest.fn(),
    },
    chapter: {
      deleteMany: jest.fn(),
      findMany: jest.fn(),
    },
  },
}));
jest.mock('@/lib/audio-metadata', () => ({
  extractChaptersBestMethod: jest.fn(),
  isFFProbeAvailable: jest.fn(() => Promise.resolve(true)),
}));
jest.mock('@/lib/s3', () => ({
  isS3Enabled: jest.fn(() => false),
  generatePresignedUrl: jest.fn(),
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;

const BOOK_ID = '123e4567-e89b-12d3-a456-426614174000';

function makeRequest(): NextRequest {
  return new NextRequest(`http://localhost:3000/api/books/${BOOK_ID}/chapters`, {
    method: 'POST',
  });
}

describe('POST /api/books/[id]/chapters authorization', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(null);
  });

  it('returns 401 for unauthenticated requests', async () => {
    const response = await POST(makeRequest(), { params: { id: BOOK_ID } });

    expect(response.status).toBe(401);
  });

  it('returns 403 for authenticated non-admin users (bearer)', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-123', username: 'testuser' });
    (prisma.user.findUnique as jest.Mock).mockResolvedValue({ isAdmin: false });

    const response = await POST(makeRequest(), { params: { id: BOOK_ID } });

    expect(response.status).toBe(403);
    // The handler must not have touched book/chapter data
    expect(prisma.chapter.deleteMany).not.toHaveBeenCalled();
  });

  it('returns 403 for authenticated non-admin web sessions', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'user-123', username: 'testuser', isAdmin: false },
    } as any);

    const response = await POST(makeRequest(), { params: { id: BOOK_ID } });

    expect(response.status).toBe(403);
  });

  it('lets admins through the gate (404 for unknown book proves the handler proceeded)', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'admin-1', username: 'admin', isAdmin: true },
    } as any);
    (prisma.book.findUnique as jest.Mock).mockResolvedValue(null);

    const response = await POST(makeRequest(), { params: { id: BOOK_ID } });

    expect(response.status).toBe(404);
    expect(prisma.book.findUnique).toHaveBeenCalled();
  });
});
