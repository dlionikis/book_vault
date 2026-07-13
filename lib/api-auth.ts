import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';

export interface AuthedUser {
  id: string;
  username: string;
}

export type RequireUserResult =
  | { user: AuthedUser; error?: never }
  | { user?: never; error: NextResponse };

/**
 * Require an authenticated user for an API route.
 * Dual auth: web session cookie OR mobile Bearer token.
 *
 * Mirrors requireAdmin's discriminated-union shape (lib/admin-auth.ts):
 *
 * ```typescript
 * const auth = await requireUser(request);
 * if (auth.error) return auth.error;
 * const user = auth.user;
 * ```
 */
export async function requireUser(request: NextRequest): Promise<RequireUserResult> {
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = (session?.user as AuthedUser | undefined) || mobileUser;

  if (!user) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  }

  return { user };
}
