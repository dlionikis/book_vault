/**
 * Tests for library series add/remove endpoints
 *
 * Covers UUID validation (previously missing on this route, unlike siblings)
 * and the auth requirement.
 */

import { POST, DELETE } from '@/app/api/library/series/[seriesId]/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

// Mock dependencies
jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    bookSeries: {
      findMany: jest.fn(),
    },
    userList: {
      findFirst: jest.fn(),
      create: jest.fn(),
    },
    userListBook: {
      findUnique: jest.fn(),
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
  },
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;

const mockUser = { id: 'user-123', username: 'testuser' };
const VALID_SERIES_ID = '123e4567-e89b-12d3-a456-426614174000';

function makeRequest(seriesId: string, method: 'POST' | 'DELETE'): NextRequest {
  return new NextRequest(`http://localhost:3000/api/library/series/${seriesId}`, { method });
}

describe('/api/library/series/[seriesId]', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);
  });

  describe('auth', () => {
    it('POST returns 401 when unauthenticated', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const response = await POST(makeRequest(VALID_SERIES_ID, 'POST'), {
        params: { seriesId: VALID_SERIES_ID },
      });

      expect(response.status).toBe(401);
    });
  });

  describe('UUID validation', () => {
    it('POST returns 400 for a malformed series ID', async () => {
      const response = await POST(makeRequest('not-a-uuid', 'POST'), {
        params: { seriesId: 'not-a-uuid' },
      });

      expect(response.status).toBe(400);
      expect(prisma.bookSeries.findMany).not.toHaveBeenCalled();
    });

    it('DELETE returns 400 for a malformed series ID', async () => {
      const response = await DELETE(makeRequest('not-a-uuid', 'DELETE'), {
        params: { seriesId: 'not-a-uuid' },
      });

      expect(response.status).toBe(400);
      expect(prisma.bookSeries.findMany).not.toHaveBeenCalled();
    });

    it('POST accepts a valid UUID (404 for unknown series proves validation passed)', async () => {
      (prisma.bookSeries.findMany as jest.Mock).mockResolvedValue([]);

      const response = await POST(makeRequest(VALID_SERIES_ID, 'POST'), {
        params: { seriesId: VALID_SERIES_ID },
      });

      expect(response.status).toBe(404);
      expect(prisma.bookSeries.findMany).toHaveBeenCalled();
    });
  });
});
