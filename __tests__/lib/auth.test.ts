/**
 * Tests for bearer-token authentication (mobile auth path) — uses REAL jose.
 *
 * getAuthUserFromRequest is the gate on every mobile API call, so its behavior
 * is pinned here with real signed tokens rather than stubs.
 */

import { NextRequest } from 'next/server';
import { getAuthUserFromRequest } from '@/lib/auth';
import { generateAccessToken } from '@/lib/jwt';

// lib/auth imports the Prisma singleton for authOptions; an empty mock both
// prevents a real client from being constructed AND proves structurally that
// the bearer path never queries the database (any access would throw).
jest.mock('@/lib/db', () => ({ prisma: {} }));

function requestWithAuth(headerValue?: string): NextRequest {
  return new NextRequest('http://localhost:3000/api/books', {
    headers: headerValue ? { authorization: headerValue } : {},
  });
}

describe('getAuthUserFromRequest', () => {
  let consoleErrorSpy: jest.SpyInstance;

  beforeEach(() => {
    consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleErrorSpy.mockRestore();
    delete process.env.JWT_ACCESS_TOKEN_EXPIRY;
  });

  it('resolves the user from a valid bearer token', async () => {
    const token = await generateAccessToken('user-123', 'testuser');

    const user = await getAuthUserFromRequest(requestWithAuth(`Bearer ${token}`));

    expect(user).toEqual({ id: 'user-123', username: 'testuser' });
  });

  it('returns null when the Authorization header is missing', async () => {
    expect(await getAuthUserFromRequest(requestWithAuth())).toBeNull();
  });

  it('returns null for non-Bearer schemes', async () => {
    expect(await getAuthUserFromRequest(requestWithAuth('Basic dXNlcjpwYXNz'))).toBeNull();
  });

  it('returns null for an expired token', async () => {
    process.env.JWT_ACCESS_TOKEN_EXPIRY = '-10';
    const token = await generateAccessToken('user-123', 'testuser');

    expect(await getAuthUserFromRequest(requestWithAuth(`Bearer ${token}`))).toBeNull();
  });

  it('returns null for a malformed token', async () => {
    expect(await getAuthUserFromRequest(requestWithAuth('Bearer not-a-jwt'))).toBeNull();
  });

  it('resolves a valid token WITHOUT a database lookup (revocation happens at refresh)', async () => {
    // Decision D2 (docs/plans/pre-restore-hardening-plan.md): access tokens are
    // accepted for their full lifetime (<=1h) even if the user was deleted;
    // the refresh endpoint is the revocation point. The empty prisma mock above
    // guarantees this test fails if a DB call is ever added to the bearer path
    // without revisiting that decision.
    const token = await generateAccessToken('deleted-user-id', 'ghost');

    const user = await getAuthUserFromRequest(requestWithAuth(`Bearer ${token}`));

    expect(user).toEqual({ id: 'deleted-user-id', username: 'ghost' });
  });
});
