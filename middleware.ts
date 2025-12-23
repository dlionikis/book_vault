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

// Protect all routes except login page
// API endpoints have their own authentication checks
export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - /auth/login (login page)
     * - /api/* (API routes check auth internally)
     * - /_next/* (Next.js internals)
     * - /favicon.ico, /robots.txt (static files)
     */
    '/((?!api|auth/login|_next|favicon.ico|robots.txt).*)',
  ],
};
