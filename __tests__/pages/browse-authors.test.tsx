import { render, screen } from '@testing-library/react';
import BrowseAuthorsPage from '@/app/browse/authors/page';
import { PrismaClient } from '@prisma/client';

// Mock Prisma Client
jest.mock('@prisma/client', () => {
  const mockPrismaClient = {
    author: {
      findMany: jest.fn(),
    },
    $disconnect: jest.fn(),
  };
  return {
    PrismaClient: jest.fn(() => mockPrismaClient),
  };
});

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
  let mockPrisma: any;

  beforeEach(() => {
    mockPrisma = new PrismaClient();
    jest.clearAllMocks();
  });

  it('renders authors list from database', async () => {
    const mockAuthors = [
      {
        id: 'author-1',
        name: 'Brandon Sanderson',
        asin: 'AUTH001',
        createdAt: new Date(),
        books: [
          { book: { id: 'b1', title: 'Book 1' } },
          { book: { id: 'b2', title: 'Book 2' } },
          { book: { id: 'b3', title: 'Book 3' } },
        ],
      },
      {
        id: 'author-2',
        name: 'V.E. Schwab',
        asin: 'AUTH002',
        createdAt: new Date(),
        books: [{ book: { id: 'b4', title: 'Book 4' } }, { book: { id: 'b5', title: 'Book 5' } }],
      },
    ];

    mockPrisma.author.findMany.mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    // Check Prisma query
    expect(mockPrisma.author.findMany).toHaveBeenCalledWith({
      include: {
        books: {
          include: {
            book: true,
          },
        },
      },
      orderBy: {
        name: 'asc',
      },
    });

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
        books: [{ book: { id: 'b1', title: 'Book 1' } }],
      },
    ];

    mockPrisma.author.findMany.mockResolvedValue(mockAuthors);

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
        books: [],
      },
      {
        id: 'author-2',
        name: 'Author 2',
        asin: 'AUTH002',
        createdAt: new Date(),
        books: [],
      },
      {
        id: 'author-3',
        name: 'Author 3',
        asin: 'AUTH003',
        createdAt: new Date(),
        books: [],
      },
    ];

    mockPrisma.author.findMany.mockResolvedValue(mockAuthors);

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
        books: [],
      },
    ];

    mockPrisma.author.findMany.mockResolvedValue(mockAuthors);

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
        books: [{ book: { id: 'b1', title: 'Book 1' } }],
      },
    ];

    mockPrisma.author.findMany.mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    const { container } = render(page);

    const link = container.querySelector('a[href="/authors/author-123"]');
    expect(link).toBeInTheDocument();
  });

  it('shows empty state when no authors exist', async () => {
    mockPrisma.author.findMany.mockResolvedValue([]);

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
        books: [],
      },
      {
        id: 'author-2',
        name: 'Bob Author',
        asin: 'AUTH002',
        createdAt: new Date(),
        books: [],
      },
      {
        id: 'author-3',
        name: 'Charlie Author',
        asin: 'AUTH003',
        createdAt: new Date(),
        books: [],
      },
    ];

    mockPrisma.author.findMany.mockResolvedValue(mockAuthors);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(mockPrisma.author.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        orderBy: {
          name: 'asc',
        },
      })
    );
  });

  it('renders back button', async () => {
    mockPrisma.author.findMany.mockResolvedValue([]);

    const page = await BrowseAuthorsPage();
    render(page);

    expect(screen.getByTestId('back-button')).toBeInTheDocument();
  });

  it('handles error gracefully', async () => {
    mockPrisma.author.findMany.mockRejectedValue(new Error('Database error'));

    const page = await BrowseAuthorsPage();
    render(page);

    // When error occurs, should return empty array and show no authors
    expect(screen.getByText('0 authors')).toBeInTheDocument();
  });
});
