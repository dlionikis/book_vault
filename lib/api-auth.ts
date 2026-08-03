import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

export interface AuthedUser {
  id: string;
  username: string;
}

export type RequireUserResult =
  { user: AuthedUser; error?: never } | { user?: never; error: NextResponse };

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
  if (session?.user) {
    return { user: session.user as AuthedUser };
  }

  const mobileUser = await getAuthUserFromRequest(request);
  if (!mobileUser) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  }

  // Confirm the account still exists (SEC-2).
  //
  // A bearer token is valid on signature alone for its full lifetime
  // (JWT_ACCESS_TOKEN_EXPIRY, default 1h), so without this a deleted user keeps
  // full read access for up to an hour after deletion. Refresh is already
  // DB-backed and refresh_tokens cascade on delete, so they cannot renew — this
  // closes the remaining window.
  //
  // Same lookup requireAdmin already performs on this path (lib/admin-auth.ts),
  // so the cost is a primary-key hit we were paying on admin routes anyway
  // (~1ms). Web sessions are exempt: NextAuth JWTs carry no DB identity to
  // re-check here and are revoked by rotating NEXTAUTH_SECRET.
  const dbUser = await prisma.user.findUnique({
    where: { id: mobileUser.id },
    select: { id: true },
  });

  if (!dbUser) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  }

  return { user: mobileUser };
}
