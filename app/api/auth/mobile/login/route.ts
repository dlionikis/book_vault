import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';
import { generateAccessToken, generateRefreshToken, getAccessTokenExpiry } from '@/lib/jwt';
import { withLogging } from '@/lib/logger';

/**
 * POST /api/auth/mobile/login
 *
 * Mobile JWT-based authentication endpoint. Validates email and password, returns access
 * and refresh tokens for mobile app authentication. Access token valid for 15 minutes,
 * refresh token valid for 7 days.
 *
 * Auth: Public
 * Request Body: { email: string, password: string }
 *
 * Returns: { accessToken: string, refreshToken: string, expiresAt: string, user: { id, email, name } }
 * Errors: 400 if missing credentials, 401 if invalid credentials, 500 on server error
 *
 * @example
 * fetch('/api/auth/mobile/login', {
 *   method: 'POST',
 *   headers: { 'Content-Type': 'application/json' },
 *   body: JSON.stringify({ email: 'user@example.com', password: 'secret' })
 * })
 */
export const POST = withLogging(async (request: NextRequest) => {
  try {
    const body = await request.json();
    const { email, password } = body;

    // Validate input
    if (!email || !password) {
      return NextResponse.json({ error: 'Email and password required' }, { status: 400 });
    }

    // Find user
    const user = await prisma.user.findUnique({
      where: { email },
    });

    if (!user) {
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);

    if (!isPasswordValid) {
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }

    // Generate tokens
    const accessToken = await generateAccessToken(user.id, user.email);
    const refreshToken = generateRefreshToken();

    // Calculate expiry (30 days from now)
    const refreshTokenExpiry = parseInt(process.env.JWT_REFRESH_TOKEN_EXPIRY || '2592000');
    const expiresAt = new Date(Date.now() + refreshTokenExpiry * 1000);

    // Store refresh token
    await prisma.refreshToken.create({
      data: {
        userId: user.id,
        token: refreshToken,
        expiresAt,
      },
    });

    // Return tokens
    return NextResponse.json({
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
      },
      expiresIn: getAccessTokenExpiry(),
    });
  } catch (error) {
    console.error('Login failed:', error);
    return NextResponse.json({ error: 'Login failed' }, { status: 500 });
  }
});
