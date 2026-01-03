import { NextRequest, NextResponse } from 'next/server';
import { verifyAccessToken } from '@/lib/jwt';
import { withLogging } from '@/lib/logger';

export const GET = withLogging(async (request: NextRequest) => {
  try {
    // Extract Bearer token from Authorization header
    const authHeader = request.headers.get('authorization');

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json({
        valid: false,
        user: null,
      });
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    // Verify token
    const payload = await verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json({
        valid: false,
        user: null,
      });
    }

    // Return success
    return NextResponse.json({
      valid: true,
      user: {
        id: payload.userId,
        email: payload.email,
      },
    });
  } catch (error) {
    console.error('Token verification failed:', error);
    return NextResponse.json({
      valid: false,
      user: null,
    });
  }
});
