import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import { withLogging } from '@/lib/logger';

export const POST = withLogging(async (request: NextRequest) => {
  try {
    const body = await request.json();
    const { refreshToken } = body;

    // Validate input
    if (!refreshToken) {
      return NextResponse.json({ error: 'Refresh token required' }, { status: 400 });
    }

    // Normalize token to lowercase (iOS Swift UUID encodes as uppercase,
    // but we store lowercase UUIDs from crypto.randomUUID())
    const normalizedToken = refreshToken.toLowerCase();

    // Delete refresh token
    await prisma.refreshToken.deleteMany({
      where: { token: normalizedToken },
    });

    return NextResponse.json({ message: 'Logged out successfully' });
  } catch (error) {
    console.error('Logout failed:', error);
    return NextResponse.json({ error: 'Logout failed' }, { status: 500 });
  }
});
