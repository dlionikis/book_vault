import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import { generateAccessToken, generateRefreshToken, getAccessTokenExpiry } from '@/lib/jwt';
import { logger, withLogging } from '@/lib/logger';
import { checkIpRateLimit } from '@/lib/rate-limit';

export const POST = withLogging(async (request: NextRequest) => {
  try {
    // Pre-auth endpoint: a refresh token is bearer-equivalent, so guessing is
    // worth throttling. The ceiling is generous enough for the iOS app's own
    // refresh traffic, including the shared coordinator retrying.
    if (!checkIpRateLimit(request, 'refresh', 30)) {
      return NextResponse.json(
        { error: 'Too many refresh attempts. Please try again later.' },
        { status: 429 }
      );
    }

    const body = await request.json();
    const { refreshToken } = body;

    // Validate input
    if (!refreshToken) {
      return NextResponse.json({ error: 'Refresh token required' }, { status: 400 });
    }

    // Normalize token to lowercase (iOS Swift UUID encodes as uppercase,
    // but we store lowercase UUIDs from crypto.randomUUID())
    const normalizedToken = refreshToken.toLowerCase();

    // Find refresh token
    const tokenRecord = await prisma.refreshToken.findUnique({
      where: { token: normalizedToken },
      include: { user: true },
    });

    if (!tokenRecord) {
      logger.info('Token refresh failed - invalid token');
      return NextResponse.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    // Check if token is expired
    if (tokenRecord.expiresAt < new Date()) {
      // Delete expired token
      await prisma.refreshToken.delete({
        where: { id: tokenRecord.id },
      });

      logger.info('Token refresh failed - token expired', { userId: tokenRecord.user.id });
      return NextResponse.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    // Generate new access token
    const accessToken = await generateAccessToken(tokenRecord.user.id, tokenRecord.user.username);

    // Rotate refresh token for security (invalidate old, create new)
    const newRefreshToken = generateRefreshToken();
    const refreshTokenExpiry = parseInt(process.env.JWT_REFRESH_TOKEN_EXPIRY || '2592000');
    const expiresAt = new Date(Date.now() + refreshTokenExpiry * 1000);

    // Delete old token and create new one in a transaction
    await prisma.$transaction([
      prisma.refreshToken.delete({
        where: { id: tokenRecord.id },
      }),
      prisma.refreshToken.create({
        data: {
          userId: tokenRecord.user.id,
          token: newRefreshToken,
          expiresAt,
        },
      }),
    ]);

    logger.info('Token refresh successful', { userId: tokenRecord.user.id });

    // Return new access token and rotated refresh token
    return NextResponse.json({
      accessToken,
      refreshToken: newRefreshToken,
      expiresIn: getAccessTokenExpiry(),
    });
  } catch (error) {
    logger.error('Token refresh failed', { error: String(error) });
    return NextResponse.json({ error: 'Token refresh failed' }, { status: 500 });
  }
});
