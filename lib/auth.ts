import { NextAuthOptions } from 'next-auth';
import CredentialsProvider from 'next-auth/providers/credentials';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';
import { NextRequest } from 'next/server';
import { verifyAccessToken } from '@/lib/jwt';

export const authOptions: NextAuthOptions = {
  providers: [
    CredentialsProvider({
      name: 'Credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) {
          return null;
        }

        const user = await prisma.user.findUnique({
          where: { email: credentials.email },
        });

        if (!user) {
          return null;
        }

        const isPasswordValid = await bcrypt.compare(credentials.password, user.passwordHash);

        if (!isPasswordValid) {
          return null;
        }

        return {
          id: user.id,
          email: user.email,
        };
      },
    }),
  ],
  session: {
    strategy: 'jwt',
  },
  pages: {
    signIn: '/auth/signin',
  },
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id;
        token.email = user.email;
      }

      // Verify user still exists in database on each token refresh
      // This invalidates sessions for deleted users
      if (token.id) {
        const dbUser = await prisma.user.findUnique({
          where: { id: token.id as string },
          select: { id: true },
        });

        if (!dbUser) {
          // User was deleted - clear user info from token
          token.id = undefined;
          token.email = undefined;
        }
      }

      return token;
    },
    async session({ session, token }) {
      // If user was deleted, token.id will be undefined
      if (!token.id) {
        throw new Error('User not found');
      }

      if (session.user) {
        session.user.id = token.id as string;
        session.user.email = token.email as string;
      }
      return session;
    },
  },
};

/**
 * Get authenticated user from Bearer token in request headers
 * This supports mobile clients using JWT tokens
 * @param request - Next.js request object
 * @returns User object or null if not authenticated
 */
export async function getAuthUserFromRequest(
  request: NextRequest
): Promise<{ id: string; email: string } | null> {
  try {
    // Check for Authorization header with Bearer token
    const authHeader = request.headers.get('authorization');

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return null;
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    // Verify and decode token
    const payload = await verifyAccessToken(token);

    if (!payload) {
      return null;
    }

    return {
      id: payload.userId,
      email: payload.email,
    };
  } catch (error) {
    console.error('Failed to get auth user from request:', error);
    return null;
  }
}
