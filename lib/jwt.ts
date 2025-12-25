import { SignJWT, jwtVerify } from 'jose';

// JWT payload interface
export interface JWTPayload {
  userId: string;
  email: string;
}

// Get the secret key as Uint8Array
function getSecretKey(): Uint8Array {
  const secret = process.env.NEXTAUTH_SECRET;
  if (!secret) {
    throw new Error('NEXTAUTH_SECRET is not defined');
  }
  return new TextEncoder().encode(secret);
}

/**
 * Generate an access token (JWT) for a user
 * @param userId - User ID
 * @param email - User email
 * @returns Signed JWT token
 */
export async function generateAccessToken(userId: string, email: string): Promise<string> {
  const secret = getSecretKey();
  const expiresIn = process.env.JWT_ACCESS_TOKEN_EXPIRY || '3600'; // Default 1 hour

  const token = await new SignJWT({ userId, email })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${expiresIn}s`)
    .sign(secret);

  return token;
}

/**
 * Verify and decode an access token
 * @param token - JWT token to verify
 * @returns Decoded payload or null if invalid
 */
export async function verifyAccessToken(token: string): Promise<JWTPayload | null> {
  try {
    const secret = getSecretKey();
    const { payload } = await jwtVerify(token, secret);

    // Validate payload structure
    if (typeof payload.userId === 'string' && typeof payload.email === 'string') {
      return {
        userId: payload.userId,
        email: payload.email,
      };
    }

    return null;
  } catch (error) {
    // Token is invalid or expired
    console.error('JWT verification failed:', error);
    return null;
  }
}

/**
 * Generate a refresh token (UUID)
 * @returns Random UUID string
 */
export function generateRefreshToken(): string {
  return crypto.randomUUID();
}
