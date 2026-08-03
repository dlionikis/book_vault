import { POST } from '@/app/api/progress/batch/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

// Mock dependencies
jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    // requireUser re-checks the account exists on the bearer path (SEC-2).
    user: { findUnique: jest.fn() },
    userProgress: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
    },
    $transaction: jest.fn(),
  },
}));
jest.mock('@/lib/rate-limit', () => ({
  checkRateLimit: jest.fn(() => true),
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;

describe('POST /api/progress/batch', () => {
  const mockUser = {
    id: 'user-123',
    username: 'testuser',
  };

  const mockBook1 = 'book-123';
  const mockBook2 = 'book-456';

  beforeEach(() => {
    jest.clearAllMocks();
    // requireUser looks the account up on the bearer path (SEC-2); default to
    // "still exists" so these tests exercise their own concern.
    (require('@/lib/db').prisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u' });
  });

  it('should return 401 if not authenticated', async () => {
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(null);

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({ updates: [] }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(401);
    expect(data.error).toBe('Unauthorized');
  });

  it('should return 400 if updates array is missing', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({}),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.error).toBe('Updates array required');
  });

  it('should return 400 if updates array is empty', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({ updates: [] }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.error).toBe('Updates array required');
  });

  it('should batch update progress with no conflicts', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const updates = [
      {
        bookId: mockBook1,
        positionSeconds: 120,
        timestamp: '2025-12-24T10:00:00.000Z',
      },
      {
        bookId: mockBook2,
        positionSeconds: 300,
        timestamp: '2025-12-24T10:05:00.000Z',
      },
    ];

    // Mock transaction to execute callback
    (prisma.$transaction as jest.Mock).mockImplementation(async (callback) => {
      return await callback({
        userProgress: {
          findUnique: jest.fn().mockResolvedValue(null),
          upsert: jest.fn().mockResolvedValue({}),
        },
      });
    });

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({ updates }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.updated).toBe(2);
    expect(data.conflicts).toBe(0);
    expect(data.details).toHaveLength(2);
    expect(data.details[0].status).toBe('updated');
    expect(data.details[1].status).toBe('updated');
  });

  it('should reject updates with older timestamps (conflicts)', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const clientTimestamp = new Date('2025-12-24T10:00:00.000Z');
    const serverTimestamp = new Date('2025-12-24T11:00:00.000Z'); // Newer than client

    const updates = [
      {
        bookId: mockBook1,
        positionSeconds: 120,
        timestamp: clientTimestamp.toISOString(),
      },
    ];

    // Mock transaction with existing newer progress
    (prisma.$transaction as jest.Mock).mockImplementation(async (callback) => {
      return await callback({
        userProgress: {
          findUnique: jest.fn().mockResolvedValue({
            userId: mockUser.id,
            bookId: mockBook1,
            positionSeconds: 200,
            lastPlayed: serverTimestamp,
          }),
          upsert: jest.fn(),
        },
      });
    });

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({ updates }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.updated).toBe(0);
    expect(data.conflicts).toBe(1);
    expect(data.details[0].status).toBe('conflict');
  });

  it('should handle mix of updates and conflicts', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const updates = [
      {
        bookId: mockBook1,
        positionSeconds: 120,
        timestamp: '2025-12-24T12:00:00.000Z', // Newer - should update
      },
      {
        bookId: mockBook2,
        positionSeconds: 300,
        timestamp: '2025-12-24T09:00:00.000Z', // Older - conflict
      },
    ];

    // Mock transaction
    (prisma.$transaction as jest.Mock).mockImplementation(async (callback) => {
      const mockFindUnique = jest.fn();
      // First call: no existing progress
      mockFindUnique.mockResolvedValueOnce(null);
      // Second call: existing newer progress
      mockFindUnique.mockResolvedValueOnce({
        userId: mockUser.id,
        bookId: mockBook2,
        positionSeconds: 400,
        lastPlayed: new Date('2025-12-24T10:00:00.000Z'),
      });

      return await callback({
        userProgress: {
          findUnique: mockFindUnique,
          upsert: jest.fn().mockResolvedValue({}),
        },
      });
    });

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({ updates }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.updated).toBe(1);
    expect(data.conflicts).toBe(1);
    expect(data.details).toHaveLength(2);
  });

  it('should support mobile auth with Bearer token', async () => {
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

    const updates = [
      {
        bookId: mockBook1,
        positionSeconds: 120,
        timestamp: '2025-12-24T10:00:00.000Z',
      },
    ];

    (prisma.$transaction as jest.Mock).mockImplementation(async (callback) => {
      return await callback({
        userProgress: {
          findUnique: jest.fn().mockResolvedValue(null),
          upsert: jest.fn().mockResolvedValue({}),
        },
      });
    });

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-token',
      },
      body: JSON.stringify({ updates }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(mockGetAuthUserFromRequest).toHaveBeenCalledWith(request);
  });

  it('should skip invalid entries in batch', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const updates = [
      {
        bookId: mockBook1,
        positionSeconds: 120,
        timestamp: '2025-12-24T10:00:00.000Z',
      },
      {
        // Missing bookId - should be skipped
        positionSeconds: 200,
        timestamp: '2025-12-24T10:01:00.000Z',
      } as any,
      {
        bookId: mockBook2,
        // Missing positionSeconds - should be skipped
        timestamp: '2025-12-24T10:02:00.000Z',
      } as any,
    ];

    (prisma.$transaction as jest.Mock).mockImplementation(async (callback) => {
      return await callback({
        userProgress: {
          findUnique: jest.fn().mockResolvedValue(null),
          upsert: jest.fn().mockResolvedValue({}),
        },
      });
    });

    const request = new NextRequest('http://localhost:3000/api/progress/batch', {
      method: 'POST',
      body: JSON.stringify({ updates }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.updated).toBe(1); // Only first valid update
    expect(data.details).toHaveLength(1);
  });
});
