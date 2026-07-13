/**
 * Tests for JWT generation and verification — uses REAL jose (no stub).
 *
 * These pin the security-critical behavior: signature verification, expiry,
 * claim validation, and secret handling. NEXTAUTH_SECRET is set to a
 * deterministic value in jest.setup.js.
 */

import { SignJWT } from 'jose';
import {
  generateAccessToken,
  verifyAccessToken,
  generateRefreshToken,
  getAccessTokenExpiry,
} from '@/lib/jwt';

const USER_ID = 'user-123';
const USERNAME = 'testuser';

function secretKey(secret: string): Uint8Array {
  return new TextEncoder().encode(secret);
}

describe('lib/jwt', () => {
  let consoleErrorSpy: jest.SpyInstance;

  beforeEach(() => {
    // verifyAccessToken logs expected failures; keep test output clean
    consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleErrorSpy.mockRestore();
    delete process.env.JWT_ACCESS_TOKEN_EXPIRY;
  });

  describe('sign/verify roundtrip', () => {
    it('verifies a freshly generated token and returns its claims', async () => {
      const token = await generateAccessToken(USER_ID, USERNAME);

      const payload = await verifyAccessToken(token);

      expect(payload).toEqual({ userId: USER_ID, username: USERNAME });
    });

    it('produces a three-part JWT', async () => {
      const token = await generateAccessToken(USER_ID, USERNAME);
      expect(token.split('.')).toHaveLength(3);
    });
  });

  describe('rejection cases', () => {
    it('rejects an expired token', async () => {
      process.env.JWT_ACCESS_TOKEN_EXPIRY = '-10';
      const token = await generateAccessToken(USER_ID, USERNAME);

      expect(await verifyAccessToken(token)).toBeNull();
    });

    it('rejects a tampered token', async () => {
      const token = await generateAccessToken(USER_ID, USERNAME);
      const [header, payload, signature] = token.split('.');
      // Flip a character in the payload; signature no longer matches
      const tamperedPayload = payload[0] === 'A' ? `B${payload.slice(1)}` : `A${payload.slice(1)}`;
      const tampered = [header, tamperedPayload, signature].join('.');

      expect(await verifyAccessToken(tampered)).toBeNull();
    });

    it('rejects a token signed with a different secret', async () => {
      const foreignToken = await new SignJWT({ userId: USER_ID, username: USERNAME })
        .setProtectedHeader({ alg: 'HS256' })
        .setIssuedAt()
        .setExpirationTime('1h')
        .sign(secretKey('some-other-secret'));

      expect(await verifyAccessToken(foreignToken)).toBeNull();
    });

    it('rejects a validly signed token missing required claims', async () => {
      const missingUsername = await new SignJWT({ userId: USER_ID })
        .setProtectedHeader({ alg: 'HS256' })
        .setIssuedAt()
        .setExpirationTime('1h')
        .sign(secretKey(process.env.NEXTAUTH_SECRET!));

      expect(await verifyAccessToken(missingUsername)).toBeNull();
    });

    it('rejects garbage input', async () => {
      expect(await verifyAccessToken('not-a-jwt')).toBeNull();
      expect(await verifyAccessToken('')).toBeNull();
    });
  });

  describe('getAccessTokenExpiry', () => {
    it('defaults to 1 hour', () => {
      expect(getAccessTokenExpiry()).toBe(3600);
    });

    it('honors the JWT_ACCESS_TOKEN_EXPIRY override', () => {
      process.env.JWT_ACCESS_TOKEN_EXPIRY = '600';
      expect(getAccessTokenExpiry()).toBe(600);
    });
  });

  describe('generateRefreshToken', () => {
    it('returns a UUID', () => {
      expect(generateRefreshToken()).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      );
    });

    it('returns a different value each call', () => {
      expect(generateRefreshToken()).not.toBe(generateRefreshToken());
    });
  });
});
