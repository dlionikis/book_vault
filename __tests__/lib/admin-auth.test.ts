import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { requireAdmin } from '@/lib/admin-auth';
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

describe('requireAdmin', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  function makeRequest(url = 'http://localhost:3000/api/admin/costs') {
    return new NextRequest(url, { method: 'GET' });
  }

  describe('web session auth', () => {
    it('allows admin users via session', async () => {
      mockGetServerSession.mockResolvedValue({
        user: { id: 'user-1', email: 'admin', isAdmin: true, username: 'admin' },
      } as any);

      const { user, error } = await requireAdmin(makeRequest());

      expect(error).toBeNull();
      expect(user).toEqual({
        id: 'user-1',
        username: 'admin',
        isAdmin: true,
      });
    });

    it('returns 403 for non-admin session users', async () => {
      mockGetServerSession.mockResolvedValue({
        user: { id: 'user-2', email: 'regular', isAdmin: false },
      } as any);

      const { user, error } = await requireAdmin(makeRequest());

      expect(user).toBeNull();
      expect(error).not.toBeNull();
      const body = await error!.json();
      expect(error!.status).toBe(403);
      expect(body.error).toContain('admin');
    });

    it('returns 403 for session users without isAdmin field', async () => {
      mockGetServerSession.mockResolvedValue({
        user: { id: 'user-3', email: 'nofield' },
      } as any);

      const { user, error } = await requireAdmin(makeRequest());

      expect(user).toBeNull();
      expect(error!.status).toBe(403);
    });
  });

  describe('Bearer token auth', () => {
    beforeEach(() => {
      // No web session
      mockGetServerSession.mockResolvedValue(null);
    });

    it('returns 401 when no session and no Bearer token', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const { user, error } = await requireAdmin(makeRequest());

      expect(user).toBeNull();
      expect(error!.status).toBe(401);
    });

    it('allows admin users via Bearer token after DB check', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue({
        id: 'mobile-1',
        username: 'mobileadmin',
      });
      (prisma.user.findUnique as jest.Mock).mockResolvedValue({ isAdmin: true });

      const { user, error } = await requireAdmin(makeRequest());

      expect(error).toBeNull();
      expect(user).toEqual({
        id: 'mobile-1',
        username: 'mobileadmin',
        isAdmin: true,
      });
      expect(prisma.user.findUnique).toHaveBeenCalledWith({
        where: { id: 'mobile-1' },
        select: { isAdmin: true },
      });
    });

    it('returns 403 for non-admin Bearer token users', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue({
        id: 'mobile-2',
        username: 'mobileuser',
      });
      (prisma.user.findUnique as jest.Mock).mockResolvedValue({ isAdmin: false });

      const { user, error } = await requireAdmin(makeRequest());

      expect(user).toBeNull();
      expect(error!.status).toBe(403);
    });

    it('returns 403 when user not found in DB', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue({
        id: 'deleted-user',
        username: 'ghost',
      });
      (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);

      const { user, error } = await requireAdmin(makeRequest());

      expect(user).toBeNull();
      expect(error!.status).toBe(403);
    });
  });
});
