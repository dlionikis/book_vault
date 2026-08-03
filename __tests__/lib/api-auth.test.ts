import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    user: {
      findUnique: jest.fn(),
    },
  },
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockFindUnique = prisma.user.findUnique as jest.Mock;

function makeRequest(url = 'http://localhost:3000/api/books') {
  return new NextRequest(url, { method: 'GET' });
}

describe('requireUser', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(null);
  });

  // Invariant 5.1: the four auth combinations.
  it('401s when there is neither a session nor a bearer token', async () => {
    const result = await requireUser(makeRequest());

    expect(result.error?.status).toBe(401);
    expect(result.user).toBeUndefined();
  });

  it('accepts a web session without touching the database', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'user-1', username: 'web' },
    } as never);

    const result = await requireUser(makeRequest());

    expect(result.error).toBeUndefined();
    expect(result.user?.id).toBe('user-1');
    // NextAuth JWTs carry no DB identity to re-check; revocation is by rotating
    // NEXTAUTH_SECRET. Keeping this path DB-free avoids a query on every
    // authenticated web request.
    expect(mockFindUnique).not.toHaveBeenCalled();
  });

  it('accepts a bearer token when the account still exists', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue({ id: 'user-2', username: 'mobile' });
    mockFindUnique.mockResolvedValue({ id: 'user-2' });

    const result = await requireUser(makeRequest());

    expect(result.error).toBeUndefined();
    expect(result.user?.id).toBe('user-2');
    expect(mockFindUnique).toHaveBeenCalledWith({
      where: { id: 'user-2' },
      select: { id: true },
    });
  });

  // SEC-2. A signed access token stays cryptographically valid for its full
  // lifetime (default 1h), so without the DB check a deleted user would keep
  // full read access until it expired.
  it('401s for a bearer token whose account has been deleted', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue({ id: 'deleted-user', username: 'ghost' });
    mockFindUnique.mockResolvedValue(null);

    const result = await requireUser(makeRequest());

    expect(result.error?.status).toBe(401);
    expect(result.user).toBeUndefined();
  });

  it('prefers the session and skips the bearer path when both are present', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'session-user', username: 'web' },
    } as never);
    mockGetAuthUserFromRequest.mockResolvedValue({ id: 'bearer-user', username: 'mobile' });

    const result = await requireUser(makeRequest());

    expect(result.user?.id).toBe('session-user');
    expect(mockGetAuthUserFromRequest).not.toHaveBeenCalled();
  });
});
