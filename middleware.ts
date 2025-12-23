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
     * - /auth/* (login, register pages)
     * - /api/auth/* (NextAuth API routes)
     * - /_next/* (Next.js internals)
     * - /favicon.ico, /robots.txt (static files)
     */
    '/((?!auth|api/auth|_next|favicon.ico|robots.txt).*)',
  ],
};
