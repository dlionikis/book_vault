import { GET, POST, PUT } from '@/app/api/progress/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

// Mock dependencies
jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    userProgress: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
      deleteMany: jest.fn(),
    },
  },
}));
jest.mock('@/lib/rate-limit', () => ({
  checkRateLimit: jest.fn(() => true),
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;

describe('/api/progress', () => {
  const mockUser = {
    id: 'user-123',
    username: 'testuser',
  };

  const mockBookId = 'book-123';

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('POST - Update progress', () => {
    it('should update progress without timestamp (backward compatible)', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const mockProgress = {
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 120,
        completed: false,
        lastPlayed: new Date('2025-12-24T10:00:00.000Z'),
      };

      (prisma.userProgress.upsert as jest.Mock).mockResolvedValue(mockProgress);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'POST',
        body: JSON.stringify({
          bookId: mockBookId,
          positionSeconds: 120,
        }),
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.positionSeconds).toBe(120);
      expect(data.completed).toBe(false);
      expect(data.updated).toBe(true);
      expect(prisma.userProgress.upsert).toHaveBeenCalled();
    });

    it('should update progress with newer timestamp', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const clientTimestamp = new Date('2025-12-24T12:00:00.000Z');
      const serverTimestamp = new Date('2025-12-24T10:00:00.000Z'); // Older

      // Existing progress with older timestamp
      (prisma.userProgress.findUnique as jest.Mock).mockResolvedValue({
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 100,
        completed: false,
        lastPlayed: serverTimestamp,
      });

      const updatedProgress = {
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 120,
        completed: false,
        lastPlayed: clientTimestamp,
      };

      (prisma.userProgress.upsert as jest.Mock).mockResolvedValue(updatedProgress);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'POST',
        body: JSON.stringify({
          bookId: mockBookId,
          positionSeconds: 120,
          timestamp: clientTimestamp.toISOString(),
        }),
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.positionSeconds).toBe(120);
      expect(data.updated).toBe(true);
      expect(prisma.userProgress.upsert).toHaveBeenCalled();
    });

    it('should reject progress with older timestamp (conflict)', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const clientTimestamp = new Date('2025-12-24T10:00:00.000Z'); // Older
      const serverTimestamp = new Date('2025-12-24T12:00:00.000Z'); // Newer

      const existingProgress = {
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 200,
        completed: false,
        lastPlayed: serverTimestamp,
      };

      // First findUnique for conflict check
      (prisma.userProgress.findUnique as jest.Mock).mockResolvedValue(existingProgress);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'POST',
        body: JSON.stringify({
          bookId: mockBookId,
          positionSeconds: 120,
          timestamp: clientTimestamp.toISOString(),
        }),
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.positionSeconds).toBe(200); // Existing progress
      expect(data.updated).toBe(false); // Conflict
      expect(prisma.userProgress.upsert).not.toHaveBeenCalled();
    });

    it('should support mobile auth with Bearer token', async () => {
      mockGetServerSession.mockResolvedValue(null);
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

      const mockProgress = {
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 120,
        completed: false,
        lastPlayed: new Date(),
      };

      (prisma.userProgress.upsert as jest.Mock).mockResolvedValue(mockProgress);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer test-token',
        },
        body: JSON.stringify({
          bookId: mockBookId,
          positionSeconds: 120,
        }),
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(mockGetAuthUserFromRequest).toHaveBeenCalledWith(request);
    });

    it('should return 401 if not authenticated', async () => {
      mockGetServerSession.mockResolvedValue(null);
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'POST',
        body: JSON.stringify({
          bookId: mockBookId,
          positionSeconds: 120,
        }),
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(401);
      expect(data.error).toBe('Unauthorized');
    });

    it('should return 400 if bookId is missing', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'POST',
        body: JSON.stringify({
          positionSeconds: 120,
        }),
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toBe('Book ID and position are required');
    });
  });

  describe('GET - Fetch progress', () => {
    it('should return progress for a book', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const mockProgress = {
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 120,
        completed: false,
        lastPlayed: new Date('2025-12-24T10:00:00.000Z'),
      };

      (prisma.userProgress.findUnique as jest.Mock).mockResolvedValue(mockProgress);

      const request = new NextRequest(`http://localhost:3000/api/progress?bookId=${mockBookId}`, {
        method: 'GET',
      });

      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.positionSeconds).toBe(120);
      expect(data.completed).toBe(false);
      expect(data.lastPlayed).toBe('2025-12-24T10:00:00.000Z');
    });

    it('should return default progress if none exists', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      (prisma.userProgress.findUnique as jest.Mock).mockResolvedValue(null);

      const request = new NextRequest(`http://localhost:3000/api/progress?bookId=${mockBookId}`, {
        method: 'GET',
      });

      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.positionSeconds).toBe(0);
      expect(data.completed).toBe(false);
      expect(data.lastPlayed).toBe(null);
    });

    it('should return 400 if bookId is missing', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'GET',
      });

      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toBe('Book ID is required');
    });
  });

  describe('PUT - Mark completed/reset', () => {
    it('should mark book as completed', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      const mockProgress = {
        userId: mockUser.id,
        bookId: mockBookId,
        positionSeconds: 0,
        completed: true,
        lastPlayed: new Date('2025-12-24T10:00:00.000Z'),
      };

      (prisma.userProgress.upsert as jest.Mock).mockResolvedValue(mockProgress);

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'PUT',
        body: JSON.stringify({
          bookId: mockBookId,
          status: 'completed',
        }),
      });

      const response = await PUT(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.completed).toBe(true);
    });

    it('should reset progress to not started', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

      (prisma.userProgress.deleteMany as jest.Mock).mockResolvedValue({ count: 1 });

      const request = new NextRequest('http://localhost:3000/api/progress', {
        method: 'PUT',
        body: JSON.stringify({
          bookId: mockBookId,
          status: 'not-started',
        }),
      });

      const response = await PUT(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.positionSeconds).toBe(0);
      expect(data.completed).toBe(false);
      expect(data.lastPlayed).toBe(null);
      expect(prisma.userProgress.deleteMany).toHaveBeenCalled();
    });
  });
});
