import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

interface AdminUser {
  id: string;
  username: string;
  isAdmin: boolean;
}

type AdminAuthResult = { user: AdminUser; error: null } | { user: null; error: NextResponse };

/**
 * Require admin privileges for an API route.
 * Supports both web sessions (reads isAdmin from JWT) and Bearer tokens (queries DB).
 */
export async function requireAdmin(request: NextRequest): Promise<AdminAuthResult> {
  // Try web session first (isAdmin is in the JWT, no DB hit)
  const session = await getServerSession(authOptions);
  if (session?.user) {
    if (!session.user.isAdmin) {
      return {
        user: null,
        error: NextResponse.json({ error: 'Forbidden: admin access required' }, { status: 403 }),
      };
    }
    return {
      user: {
        id: session.user.id,
        username: (session.user as any).username ?? session.user.email,
        isAdmin: true,
      },
      error: null,
    };
  }

  // Try Bearer token (mobile) - must query DB for isAdmin
  const mobileUser = await getAuthUserFromRequest(request);
  if (!mobileUser) {
    return {
      user: null,
      error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }),
    };
  }

  const dbUser = await prisma.user.findUnique({
    where: { id: mobileUser.id },
    select: { isAdmin: true },
  });

  if (!dbUser?.isAdmin) {
    return {
      user: null,
      error: NextResponse.json({ error: 'Forbidden: admin access required' }, { status: 403 }),
    };
  }

  return {
    user: { ...mobileUser, isAdmin: true },
    error: null,
  };
}
