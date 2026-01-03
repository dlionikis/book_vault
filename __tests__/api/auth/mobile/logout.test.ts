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
    expect(data.message).toBe('Logged out successfully');
    // Token should be normalized to lowercase
    expect(prisma.refreshToken.deleteMany).toHaveBeenCalledWith({
      where: { token: 'token-to-delete' },
    });
  });

  it('should normalize uppercase UUID tokens to lowercase for deletion', async () => {
    // This test ensures iOS compatibility - Swift's UUID type encodes as uppercase
    // but the backend stores lowercase UUIDs from crypto.randomUUID()
    const lowercaseToken = '698a4976-f7ac-4040-b5a8-39309998b8b0';
    const uppercaseToken = '698A4976-F7AC-4040-B5A8-39309998B8B0';

    (prisma.refreshToken.deleteMany as jest.Mock).mockResolvedValue({ count: 1 });

    // iOS sends uppercase UUID
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/logout', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: uppercaseToken }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.message).toBe('Logged out successfully');

    // Verify the deletion was performed with lowercase token
    expect(prisma.refreshToken.deleteMany).toHaveBeenCalledWith({
      where: { token: lowercaseToken },
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
    expect(data.message).toBe('Logged out successfully');
  });
});
