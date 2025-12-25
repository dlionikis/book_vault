import { GET } from '@/app/api/auth/mobile/verify/route';
import { verifyAccessToken } from '@/lib/jwt';
import { NextRequest } from 'next/server';

// Mock dependencies
jest.mock('@/lib/jwt', () => ({
  verifyAccessToken: jest.fn(),
}));

describe('GET /api/auth/mobile/verify', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return invalid if no authorization header', async () => {
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/verify', {
      method: 'GET',
    });

    const response = await GET(request);
    const data = await response.json();

    expect(data.valid).toBe(false);
    expect(data.user).toBeNull();
  });

  it('should return invalid if authorization header does not start with Bearer', async () => {
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/verify', {
      method: 'GET',
      headers: {
        authorization: 'Basic invalid-token',
      },
    });

    const response = await GET(request);
    const data = await response.json();

    expect(data.valid).toBe(false);
    expect(data.user).toBeNull();
  });

  it('should return invalid if token verification fails', async () => {
    (verifyAccessToken as jest.Mock).mockResolvedValue(null);

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/verify', {
      method: 'GET',
      headers: {
        authorization: 'Bearer invalid-token',
      },
    });

    const response = await GET(request);
    const data = await response.json();

    expect(data.valid).toBe(false);
    expect(data.user).toBeNull();
  });

  it('should return valid with user data if token is valid', async () => {
    const mockPayload = {
      userId: 'test-user-id',
      email: 'test@example.com',
    };

    (verifyAccessToken as jest.Mock).mockResolvedValue(mockPayload);

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/verify', {
      method: 'GET',
      headers: {
        authorization: 'Bearer valid-token',
      },
    });

    const response = await GET(request);
    const data = await response.json();

    expect(data.valid).toBe(true);
    expect(data.user).toEqual({
      id: mockPayload.userId,
      email: mockPayload.email,
    });
  });
});
