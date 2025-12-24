import { render, screen } from '@testing-library/react';
import ContinueListeningButton from '@/components/ContinueListeningButton';
import { prisma } from '@/lib/db';

// Mock Prisma
jest.mock('@/lib/db', () => ({
  prisma: {
    userProgress: {
      findFirst: jest.fn(),
    },
  },
}));

// Mock next-auth
jest.mock('next-auth', () => ({
  getServerSession: jest.fn(),
}));

// Mock next/link
jest.mock('next/link', () => {
  return function MockLink({ children, href }: { children: React.ReactNode; href: string }) {
    return <a href={href}>{children}</a>;
  };
});

// Mock next/image
jest.mock('next/image', () => {
  return function MockImage({ src, alt, fill }: { src: string; alt: string; fill?: boolean }) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt={alt} data-fill={fill} />;
  };
});

describe('ContinueListeningButton', () => {
  const { getServerSession } = require('next-auth');

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns null when user is not authenticated', async () => {
    getServerSession.mockResolvedValue(null);

    const component = await ContinueListeningButton();
    const { container } = render(component);

    expect(container.firstChild).toBeNull();
  });

  it('returns null when user has no in-progress books', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(null);

    const component = await ContinueListeningButton();
    const { container } = render(component);

    expect(container.firstChild).toBeNull();
  });

  it('renders continue listening button with book details', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    const mockProgress = {
      userId: 'user-1',
      bookId: 'book-1',
      positionSeconds: 3600, // 1 hour into a 2 hour book
      completed: false,
      lastPlayed: new Date(),
      book: {
        id: 'book-1',
        title: 'Test Audiobook',
        coverUrl: 'covers/test-book.jpg',
        runtimeMinutes: 120, // 2 hours
        authors: [
          {
            author: {
              name: 'John Doe',
            },
          },
          {
            author: {
              name: 'Jane Smith',
            },
          },
        ],
      },
    };

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(mockProgress);

    const component = await ContinueListeningButton();
    render(component);

    // Check for book title
    expect(screen.getByText('Test Audiobook')).toBeInTheDocument();

    // Check for authors
    expect(screen.getByText('John Doe, Jane Smith')).toBeInTheDocument();

    // Check for progress percentage (3600 seconds / 7200 seconds = 50%)
    expect(screen.getByText('50%')).toBeInTheDocument();

    // Check for "Continue Listening" label
    expect(screen.getByText('Continue Listening')).toBeInTheDocument();

    // Check for link to playback page
    const link = screen.getByRole('link');
    expect(link).toHaveAttribute('href', '/books/book-1/play');

    // Check for book cover image
    const image = screen.getByAltText('Cover of Test Audiobook');
    expect(image).toHaveAttribute('src', '/api/images/covers/test-book.jpg');
  });

  it('handles books with no cover image', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    const mockProgress = {
      userId: 'user-1',
      bookId: 'book-2',
      positionSeconds: 1800,
      completed: false,
      lastPlayed: new Date(),
      book: {
        id: 'book-2',
        title: 'Book Without Cover',
        coverUrl: null,
        runtimeMinutes: 60,
        authors: [
          {
            author: {
              name: 'Author Name',
            },
          },
        ],
      },
    };

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(mockProgress);

    const component = await ContinueListeningButton();
    const { container } = render(component);

    // Should render placeholder icon instead of image
    expect(screen.queryByAltText(/Cover of/)).not.toBeInTheDocument();
    // Check for SVG placeholder
    const svg = container.querySelector('svg');
    expect(svg).toBeInTheDocument();
  });

  it('handles books with no authors', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    const mockProgress = {
      userId: 'user-1',
      bookId: 'book-3',
      positionSeconds: 100,
      completed: false,
      lastPlayed: new Date(),
      book: {
        id: 'book-3',
        title: 'Book Without Authors',
        coverUrl: 'covers/test.jpg',
        runtimeMinutes: 100,
        authors: [],
      },
    };

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(mockProgress);

    const component = await ContinueListeningButton();
    render(component);

    expect(screen.getByText('Book Without Authors')).toBeInTheDocument();
    // Author section should not be rendered
    expect(screen.queryByText(',')).not.toBeInTheDocument();
  });

  it('calculates progress percentage correctly for edge cases', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    // Test: 0% progress
    const mockProgressZero = {
      userId: 'user-1',
      bookId: 'book-4',
      positionSeconds: 1, // Just started
      completed: false,
      lastPlayed: new Date(),
      book: {
        id: 'book-4',
        title: 'Just Started',
        coverUrl: null,
        runtimeMinutes: 100,
        authors: [],
      },
    };

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(mockProgressZero);

    const component = await ContinueListeningButton();
    const { unmount } = render(component);

    // 1 second / 6000 seconds = 0.016%, rounds to 0%
    expect(screen.getByText('0%')).toBeInTheDocument();

    unmount();

    // Test: Nearly complete (99%)
    const mockProgressNearComplete = {
      userId: 'user-1',
      bookId: 'book-5',
      positionSeconds: 5940, // 99 minutes into 100 minute book
      completed: false,
      lastPlayed: new Date(),
      book: {
        id: 'book-5',
        title: 'Nearly Done',
        coverUrl: null,
        runtimeMinutes: 100,
        authors: [],
      },
    };

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(mockProgressNearComplete);

    const component2 = await ContinueListeningButton();
    render(component2);

    // 5940 / 6000 = 99%
    expect(screen.getByText('99%')).toBeInTheDocument();
  });

  it('queries for most recent in-progress book', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    (prisma.userProgress.findFirst as jest.Mock).mockResolvedValue(null);

    await ContinueListeningButton();

    expect(prisma.userProgress.findFirst).toHaveBeenCalledWith({
      where: {
        userId: 'user-1',
        positionSeconds: {
          gt: 0,
        },
        completed: false,
      },
      orderBy: {
        lastPlayed: 'desc',
      },
      include: {
        book: {
          include: {
            authors: {
              include: {
                author: true,
              },
            },
          },
        },
      },
    });
  });

  it('handles database errors gracefully', async () => {
    getServerSession.mockResolvedValue({
      user: { id: 'user-1', email: 'test@example.com' },
    });

    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation();

    (prisma.userProgress.findFirst as jest.Mock).mockRejectedValue(new Error('Database error'));

    const component = await ContinueListeningButton();
    const { container } = render(component);

    // Should return null on error
    expect(container.firstChild).toBeNull();

    // Should log error
    expect(consoleErrorSpy).toHaveBeenCalledWith(
      'Error fetching most recent book:',
      expect.any(Error)
    );

    consoleErrorSpy.mockRestore();
  });
});
