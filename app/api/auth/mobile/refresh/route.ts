import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import { generateAccessToken } from '@/lib/jwt';
import { logger, startTimer } from '@/lib/logger';

export async function POST(request: NextRequest) {
  const timer = startTimer();

  try {
    const body = await request.json();
    const { refreshToken } = body;

    // Validate input
    if (!refreshToken) {
      logger.request('POST', '/api/auth/mobile/refresh', 400, timer());
      return NextResponse.json({ error: 'Refresh token required' }, { status: 400 });
    }

    // Find refresh token
    const tokenRecord = await prisma.refreshToken.findUnique({
      where: { token: refreshToken },
      include: { user: true },
    });

    if (!tokenRecord) {
      logger.info('Token refresh failed - invalid token');
      logger.request('POST', '/api/auth/mobile/refresh', 401, timer());
      return NextResponse.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    // Check if token is expired
    if (tokenRecord.expiresAt < new Date()) {
      // Delete expired token
      await prisma.refreshToken.delete({
        where: { id: tokenRecord.id },
      });

      logger.info('Token refresh failed - token expired', { userId: tokenRecord.user.id });
      logger.request('POST', '/api/auth/mobile/refresh', 401, timer());
      return NextResponse.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    // Generate new access token
    const accessToken = await generateAccessToken(tokenRecord.user.id, tokenRecord.user.email);

    logger.info('Token refresh successful', { userId: tokenRecord.user.id });
    logger.request('POST', '/api/auth/mobile/refresh', 200, timer());

    // Return new access token
    return NextResponse.json({
      accessToken,
      expiresIn: parseInt(process.env.JWT_ACCESS_TOKEN_EXPIRY || '3600'),
    });
  } catch (error) {
    logger.error('Token refresh failed', { error: String(error) });
    logger.request('POST', '/api/auth/mobile/refresh', 500, timer());
    return NextResponse.json({ error: 'Token refresh failed' }, { status: 500 });
  }
}
