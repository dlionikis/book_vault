import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import { generateAccessToken } from '@/lib/jwt';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { refreshToken } = body;

    // Validate input
    if (!refreshToken) {
      return NextResponse.json({ error: 'Refresh token required' }, { status: 400 });
    }

    // Find refresh token
    const tokenRecord = await prisma.refreshToken.findUnique({
      where: { token: refreshToken },
      include: { user: true },
    });

    if (!tokenRecord) {
      return NextResponse.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    // Check if token is expired
    if (tokenRecord.expiresAt < new Date()) {
      // Delete expired token
      await prisma.refreshToken.delete({
        where: { id: tokenRecord.id },
      });

      return NextResponse.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    // Generate new access token
    const accessToken = await generateAccessToken(tokenRecord.user.id, tokenRecord.user.email);

    // Return new access token
    return NextResponse.json({
      accessToken,
      expiresIn: parseInt(process.env.JWT_ACCESS_TOKEN_EXPIRY || '3600'),
    });
  } catch (error) {
    console.error('Token refresh failed:', error);
    return NextResponse.json({ error: 'Token refresh failed' }, { status: 500 });
  }
}
