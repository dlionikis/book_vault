import { withAuth } from 'next-auth/middleware';
import { NextResponse, NextRequest } from 'next/server';

// Add CORS headers to response
function addCorsHeaders(response: NextResponse): NextResponse {
  response.headers.set('Access-Control-Allow-Origin', process.env.MOBILE_CORS_ORIGIN || '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  response.headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  return response;
}

export default function middleware(req: NextRequest) {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    const response = NextResponse.json({}, { status: 200 });
    return addCorsHeaders(response);
  }

  // For API routes, add CORS headers and skip auth check
  if (req.nextUrl.pathname.startsWith('/api/')) {
    const response = NextResponse.next();
    return addCorsHeaders(response);
  }

  // For non-API routes, use NextAuth middleware
  return (
    withAuth(
      function authMiddleware() {
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
    ) as any
  )(req);
}

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
