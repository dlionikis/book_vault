import { POST } from '@/app/api/auth/mobile/login/route';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';
import { NextRequest } from 'next/server';

// Mock dependencies
jest.mock('@/lib/db', () => ({
  prisma: {
    user: {
      findUnique: jest.fn(),
    },
    refreshToken: {
      create: jest.fn(),
    },
  },
}));

jest.mock('bcryptjs', () => ({
  compare: jest.fn(),
}));

describe('POST /api/auth/mobile/login', () => {
  const mockUser = {
    id: 'test-user-id',
    email: 'test@example.com',
    passwordHash: 'hashed-password',
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return 400 if email is missing', async () => {
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/login', {
      method: 'POST',
      body: JSON.stringify({ password: 'password123' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.error).toBe('Email and password required');
  });

  it('should return 400 if password is missing', async () => {
    const request = new NextRequest('http://localhost:3000/api/auth/mobile/login', {
      method: 'POST',
      body: JSON.stringify({ email: 'test@example.com' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.error).toBe('Email and password required');
  });

  it('should return 401 if user not found', async () => {
    (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/login', {
      method: 'POST',
      body: JSON.stringify({ email: 'nonexistent@example.com', password: 'password123' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(401);
    expect(data.error).toBe('Invalid credentials');
  });

  it('should return 401 if password is invalid', async () => {
    (prisma.user.findUnique as jest.Mock).mockResolvedValue(mockUser);
    (bcrypt.compare as jest.Mock).mockResolvedValue(false);

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/login', {
      method: 'POST',
      body: JSON.stringify({ email: 'test@example.com', password: 'wrongpassword' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(401);
    expect(data.error).toBe('Invalid credentials');
  });

  it('should return access token and refresh token on successful login', async () => {
    (prisma.user.findUnique as jest.Mock).mockResolvedValue(mockUser);
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    (prisma.refreshToken.create as jest.Mock).mockResolvedValue({
      id: 'token-id',
      userId: mockUser.id,
      token: 'refresh-token',
      expiresAt: new Date(),
    });

    const request = new NextRequest('http://localhost:3000/api/auth/mobile/login', {
      method: 'POST',
      body: JSON.stringify({ email: 'test@example.com', password: 'password123' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.accessToken).toBeDefined();
    expect(data.refreshToken).toBeDefined();
    expect(data.user).toEqual({
      id: mockUser.id,
      email: mockUser.email,
    });
    expect(data.expiresIn).toBeDefined();
  });
});
