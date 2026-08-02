import { render, screen } from '@testing-library/react';
import BrowseAuthorsPage from '@/app/browse/authors/page';
import { prisma } from '@/lib/db';

// Mock Prisma Client
jest.mock('@/lib/db', () => ({
  prisma: {
    author: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
    $disconnect: jest.fn(),
  },
}));

// Mock components
jest.mock('@/components/BackButton', () => {
  return function MockBackButton() {
    return <button data-testid="back-button">Back</button>;
  };
});

// Mock next/link
jest.mock('next/link', () => {
  return function MockLink({ children, href }: { children: React.ReactNode; href: string }) {
    return <a href={href}>{children}</a>;
  };
});

describe('Browse Authors Page', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders authors list from database', async () => {
    const mockAuthors = [
      {
        id: 'author-1',
        name: 'Brandon Sanderson',
        asin: 'AUTH001',
        createdAt: new Date(),
        _count: { books: 3 },
      },
      {
        id: 'author-2',
        name: 'V.E. Schwab',
        asin: 'AUTH002',
        createdAt: new Date(),
        _count: { books: 2 },
      },
    ];

    (prisma.author.findMany as jest.Mock).mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    // The page must go through the shared query, which filters hidden books out
    // of both the listing and the bookCount. Asserting the filter rather than
    // the full call shape keeps this from breaking on unrelated query tweaks.
    expect(prisma.author.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { books: { some: { book: { hiddenAt: null } } } },
        include: { _count: { select: { books: { where: { book: { hiddenAt: null } } } } } },
        orderBy: { name: 'asc' },
      })
    );

    // Check rendered content
    expect(screen.getByText('Brandon Sanderson')).toBeInTheDocument();
    expect(screen.getByText('V.E. Schwab')).toBeInTheDocument();
    expect(screen.getByText('3 books')).toBeInTheDocument();
    expect(screen.getByText('2 books')).toBeInTheDocument();
  });

  it('displays correct book count for authors', async () => {
    const mockAuthors = [
      {
        id: 'author-1',
        name: 'Single Book Author',
        asin: 'AUTH001',
        createdAt: new Date(),
        _count: { books: 1 },
      },
    ];

    (prisma.author.findMany as jest.Mock).mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(screen.getByText('1 book')).toBeInTheDocument();
  });

  it('displays total author count in header', async () => {
    const mockAuthors = [
      {
        id: 'author-1',
        name: 'Author 1',
        asin: 'AUTH001',
        createdAt: new Date(),
        _count: { books: 0 },
      },
      {
        id: 'author-2',
        name: 'Author 2',
        asin: 'AUTH002',
        createdAt: new Date(),
        _count: { books: 0 },
      },
      {
        id: 'author-3',
        name: 'Author 3',
        asin: 'AUTH003',
        createdAt: new Date(),
        _count: { books: 0 },
      },
    ];

    (prisma.author.findMany as jest.Mock).mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(screen.getByText('3 authors')).toBeInTheDocument();
  });

  it('displays singular "author" when count is 1', async () => {
    const mockAuthors = [
      {
        id: 'author-1',
        name: 'Only Author',
        asin: 'AUTH001',
        createdAt: new Date(),
        _count: { books: 0 },
      },
    ];

    (prisma.author.findMany as jest.Mock).mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(screen.getByText('1 author')).toBeInTheDocument();
  });

  it('links to individual author pages', async () => {
    const mockAuthors = [
      {
        id: 'author-123',
        name: 'Test Author',
        asin: 'AUTH001',
        createdAt: new Date(),
        _count: { books: 1 },
      },
    ];

    (prisma.author.findMany as jest.Mock).mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    const { container } = render(page);

    const link = container.querySelector('a[href="/authors/author-123"]');
    expect(link).toBeInTheDocument();
  });

  it('shows empty state when no authors exist', async () => {
    (prisma.author.findMany as jest.Mock).mockResolvedValue([]);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(screen.getByText('No authors found')).toBeInTheDocument();
    expect(screen.getByText('0 authors')).toBeInTheDocument();
  });

  it('sorts authors alphabetically by name', async () => {
    const mockAuthors = [
      {
        id: 'author-1',
        name: 'Alice Author',
        asin: 'AUTH001',
        createdAt: new Date(),
        _count: { books: 0 },
      },
      {
        id: 'author-2',
        name: 'Bob Author',
        asin: 'AUTH002',
        createdAt: new Date(),
        _count: { books: 0 },
      },
      {
        id: 'author-3',
        name: 'Charlie Author',
        asin: 'AUTH003',
        createdAt: new Date(),
        _count: { books: 0 },
      },
    ];

    (prisma.author.findMany as jest.Mock).mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(prisma.author.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        orderBy: {
          name: 'asc',
        },
      })
    );
  });

  it('renders back button', async () => {
    (prisma.author.findMany as jest.Mock).mockResolvedValue([]);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(screen.getByTestId('back-button')).toBeInTheDocument();
  });

  it('handles error gracefully', async () => {
    (prisma.author.findMany as jest.Mock).mockRejectedValue(new Error('Database error'));

    const page = await BrowseAuthorsPage();
    render(page);

    // When error occurs, should return empty array and show no authors
    expect(screen.getByText('0 authors')).toBeInTheDocument();
  });
});
