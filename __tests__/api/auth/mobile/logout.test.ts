import { POST } from '@/app/api/auth/mobile/logout/route';
import { prisma } from '@/lib/db';
import { NextRequest } from 'next/server';

// Mock dependencies
jest.mock('@/lib/db', () => ({
  prisma: {
    refreshToken: {
      deleteMany: jest.fn(),
    },
  },
}));

describe('POST /api/auth/mobile/logout', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return 400 if refresh token is missing', async () => {
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/logout', {
      method: 'POST',
      body: JSON.stringify({}),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.error).toBe('Refresh token required');
  });

  it('should delete refresh token and return success', async () => {
    (prisma.refreshToken.deleteMany as jest.Mock).mockResolvedValue({ count: 1 });

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/logout', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: 'token-to-delete' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(prisma.refreshToken.deleteMany).toHaveBeenCalledWith({
      where: { token: 'token-to-delete' },
    });
  });

  it('should return success even if token does not exist', async () => {
    (prisma.refreshToken.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/logout', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: 'nonexistent-token' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
  });
});
