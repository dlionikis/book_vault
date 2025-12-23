import { withAuth } from 'next-auth/middleware';
import { NextResponse } from 'next/server';

export default withAuth(
  function middleware(req) {
    return NextResponse.next();
  },
  {
    callbacks: {
      authorized: ({ token }) => !!token,
    },
    pages: {
      signIn: '/auth/login',
    },
  }
);

// Protect all routes except auth pages and API routes
export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - /auth/login (login page allowed)
     * - /api/* (all API routes)
     * - /_next/* (Next.js internals)
     * - /favicon.ico, /robots.txt (static files)
     * Note: /auth/register is intentionally protected (admin-only user creation)
     */
    '/((?!api|auth/login|_next|favicon.ico|robots.txt).*)',
  ],
};
