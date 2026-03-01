import { render, screen } from '@testing-library/react';
import { getServerSession } from 'next-auth';
import { redirect } from 'next/navigation';
import { prisma } from '@/lib/db';

jest.mock('next-auth');
jest.mock('next/navigation', () => ({
  redirect: jest.fn(),
}));
jest.mock('@/lib/db', () => ({
  prisma: {
    user: {
      findUnique: jest.fn(),
    },
  },
}));
jest.mock('@/lib/auth', () => ({
  authOptions: {},
}));

// Mock the client component to avoid importing recharts in test env
jest.mock('@/app/admin/dashboard/DashboardClient', () => {
  return function MockDashboardClient() {
    return <div data-testid="dashboard-client">Dashboard</div>;
  };
});

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockRedirect = redirect as jest.MockedFunction<typeof redirect>;

describe('AdminDashboardPage', () => {
  let AdminDashboardPage: () => Promise<JSX.Element>;

  beforeEach(async () => {
    jest.clearAllMocks();
    const mod = await import('@/app/admin/dashboard/page');
    AdminDashboardPage = mod.default;
  });

  it('redirects to signin when not authenticated', async () => {
    mockGetServerSession.mockResolvedValue(null);

    try {
      await AdminDashboardPage();
    } catch {
      // redirect throws in Next.js
    }

    expect(mockRedirect).toHaveBeenCalledWith('/auth/signin');
  });

  it('redirects to / when user is not admin', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'regular' },
    } as any);

    (prisma.user.findUnique as jest.Mock).mockResolvedValue({ isAdmin: false });

    try {
      await AdminDashboardPage();
    } catch {
      // redirect throws in Next.js
    }

    expect(mockRedirect).toHaveBeenCalledWith('/');
  });

  it('redirects to / when user not found in DB', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'deleted-user', email: 'ghost' },
    } as any);

    (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);

    try {
      await AdminDashboardPage();
    } catch {
      // redirect throws in Next.js
    }

    expect(mockRedirect).toHaveBeenCalledWith('/');
  });

  it('renders dashboard for admin users', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'admin-1', email: 'admin' },
    } as any);

    (prisma.user.findUnique as jest.Mock).mockResolvedValue({ isAdmin: true });

    const result = await AdminDashboardPage();
    render(result);

    expect(screen.getByTestId('dashboard-client')).toBeInTheDocument();
    expect(mockRedirect).not.toHaveBeenCalled();
  });

  it('queries DB with correct user ID and select', async () => {
    mockGetServerSession.mockResolvedValue({
      user: { id: 'admin-1', email: 'admin' },
    } as any);

    (prisma.user.findUnique as jest.Mock).mockResolvedValue({ isAdmin: true });

    await AdminDashboardPage();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { id: 'admin-1' },
      select: { isAdmin: true },
    });
  });
});
