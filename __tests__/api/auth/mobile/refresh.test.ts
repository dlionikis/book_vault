import { POST } from '@/app/api/auth/mobile/refresh/route';
import { prisma } from '@/lib/db';
import { NextRequest } from 'next/server';

// Mock dependencies
jest.mock('@/lib/db', () => ({
  prisma: {
    refreshToken: {
      findUnique: jest.fn(),
      delete: jest.fn(),
      create: jest.fn(),
    },
    $transaction: jest.fn((operations) => Promise.all(operations)),
  },
}));

describe('POST /api/auth/mobile/refresh', () => {
  const mockUser = {
    id: 'test-user-id',
    email: 'test@example.com',
  };

  const mockRefreshToken = {
    id: 'token-id',
    userId: mockUser.id,
    token: 'valid-refresh-token',
    expiresAt: new Date(Date.now() + 86400000), // 1 day from now
    user: mockUser,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return 400 if refresh token is missing', async () => {
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/refresh', {
      method: 'POST',
      body: JSON.stringify({}),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.error).toBe('Refresh token required');
  });

  it('should return 401 if refresh token is invalid', async () => {
    (prisma.refreshToken.findUnique as jest.Mock).mockResolvedValue(null);

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: 'invalid-token' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(401);
    expect(data.error).toBe('Invalid or expired refresh token');
  });

  it('should return 401 and delete token if expired', async () => {
    const expiredToken = {
      ...mockRefreshToken,
      expiresAt: new Date(Date.now() - 86400000), // 1 day ago
    };

    (prisma.refreshToken.findUnique as jest.Mock).mockResolvedValue(expiredToken);
    (prisma.refreshToken.delete as jest.Mock).mockResolvedValue(expiredToken);

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: 'expired-token' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(401);
    expect(data.error).toBe('Invalid or expired refresh token');
    expect(prisma.refreshToken.delete).toHaveBeenCalledWith({
      where: { id: expiredToken.id },
    });
  });

  it('should return new access token and rotated refresh token on successful refresh', async () => {
    (prisma.refreshToken.findUnique as jest.Mock).mockResolvedValue(mockRefreshToken);
    (prisma.refreshToken.delete as jest.Mock).mockResolvedValue(mockRefreshToken);
    (prisma.refreshToken.create as jest.Mock).mockResolvedValue({ id: 'new-token-id' });

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: 'valid-refresh-token' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.accessToken).toBeDefined();
    expect(data.refreshToken).toBeDefined();
    expect(data.expiresIn).toBeDefined();
    // Verify token rotation occurred
    expect(prisma.$transaction).toHaveBeenCalled();
  });

  it('should normalize uppercase UUID tokens to lowercase for lookup', async () => {
    // This test ensures iOS compatibility - Swift's UUID type encodes as uppercase
    // but the backend stores lowercase UUIDs from crypto.randomUUID()
    const lowercaseToken = '698a4976-f7ac-4040-b5a8-39309998b8b0';
    const uppercaseToken = '698A4976-F7AC-4040-B5A8-39309998B8B0';

    const tokenRecord = {
      ...mockRefreshToken,
      token: lowercaseToken,
    };

    (prisma.refreshToken.findUnique as jest.Mock).mockResolvedValue(tokenRecord);
    (prisma.refreshToken.delete as jest.Mock).mockResolvedValue(tokenRecord);
    (prisma.refreshToken.create as jest.Mock).mockResolvedValue({ id: 'new-token-id' });

    // iOS sends uppercase UUID
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: uppercaseToken }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.accessToken).toBeDefined();
    expect(data.refreshToken).toBeDefined();

    // Verify the lookup was performed with lowercase token
    expect(prisma.refreshToken.findUnique).toHaveBeenCalledWith({
      where: { token: lowercaseToken },
      include: { user: true },
    });
  });
});
