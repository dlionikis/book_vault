/**
 * NextAuth type augmentations for Book Vault.
 *
 * Purpose: Extend NextAuth's default types to include our custom user fields.
 *
 * Why needed?
 * - NextAuth's default Session.user only has name, email, and image
 * - We need user.id to be available in session for database queries
 * - TypeScript requires us to explicitly declare custom fields via module augmentation
 *
 * How it works:
 * - These declarations merge with NextAuth's built-in types
 * - The callbacks in [...nextauth]/route.ts populate these fields
 * - Components can then access session.user.id with full type safety
 */

import 'next-auth';

declare module 'next-auth' {
  /**
   * Session object returned by useSession() and getServerSession().
   * Extended to include user ID for database operations.
   */
  interface Session {
    user: {
      /** User's UUID from database, required for all user-scoped queries */
      id: string;

      /** User's email address */
      email: string;

      /** Whether the user has admin privileges */
      isAdmin?: boolean;
    };
  }

  /**
   * User object returned by authentication providers.
   * Extended to include database ID.
   */
  interface User {
    /** User's UUID from database */
    id: string;

    /** User's email address */
    email: string;
  }
}

declare module 'next-auth/jwt' {
  /**
   * JWT token payload for NextAuth session tokens.
   * Extended to persist user ID and email across requests.
   *
   * Note: These fields are optional because they're only set after successful authentication.
   */
  interface JWT {
    /** User's database ID, set by jwt() callback */
    id?: string;

    /** User's email, set by jwt() callback */
    email?: string;

    /** Whether the user has admin privileges */
    isAdmin?: boolean;
  }
}
