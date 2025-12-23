import { render, screen } from '@testing-library/react';
import Home from '@/app/page';
import { PrismaClient } from '@prisma/client';

// Mock Prisma Client
jest.mock('@prisma/client', () => {
  const mockPrismaClient = {
    book: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
    $disconnect: jest.fn(),
  };
  return {
    PrismaClient: jest.fn(() => mockPrismaClient),
  };
});

// Mock next/navigation
jest.mock('next/navigation', () => ({
  useRouter: () => ({
    push: jest.fn(),
  }),
  useSearchParams: () => ({
    get: jest.fn(),
  }),
  usePathname: () => '/books',
}));

// Mock components
jest.mock('@/components/BookGrid', () => {
  return function MockBookGrid({ books }: { books: any[] }) {
    return (
      <div data-testid="book-grid">
        {books.map((book) => (
          <div key={book.id} data-testid="book-item">
            {book.title}
          </div>
        ))}
      </div>
    );
  };
});

jest.mock('@/components/SearchBar', () => {
  return function MockSearchBar() {
    return <div data-testid="search-bar">Search</div>;
  };
});

jest.mock('@/components/SortDropdown', () => {
  return function MockSortDropdown() {
    return <div data-testid="sort-dropdown">Sort</div>;
  };
});

jest.mock('@/components/Pagination', () => {
  return function MockPagination() {
    return <div data-testid="pagination">Pagination</div>;
  };
});

describe('Home Page', () => {
  let mockPrisma: any;

  beforeEach(() => {
    mockPrisma = new PrismaClient();
    jest.clearAllMocks();
  });

  it('renders home page with books from database', async () => {
    const mockBooks = [
      {
        id: '1',
        asin: 'B001',
        title: 'Test Book 1',
        publisherSummary: 'Summary 1',
        runtimeMinutes: 300,
        releaseDate: new Date('2024-01-01'),
        publisher: 'Test Publisher',
        coverUrl: '/cover1.jpg',
        audioUrl: '/audio1.m4b',
        createdAt: new Date(),
        updatedAt: new Date(),
        description: null,
        metadata: null,
        authors: [{ author: { id: 'a1', name: 'Author 1', asin: 'AUTH1', createdAt: new Date() } }],
        narrators: [
          { narrator: { id: 'n1', name: 'Narrator 1', asin: 'NARR1', createdAt: new Date() } },
        ],
        series: [],
      },
      {
        id: '2',
        asin: 'B002',
        title: 'Test Book 2',
        publisherSummary: 'Summary 2',
        runtimeMinutes: 400,
        releaseDate: new Date('2024-02-01'),
        publisher: 'Test Publisher',
        coverUrl: '/cover2.jpg',
        audioUrl: '/audio2.m4b',
        createdAt: new Date(),
        updatedAt: new Date(),
        description: null,
        metadata: null,
        authors: [{ author: { id: 'a2', name: 'Author 2', asin: 'AUTH2', createdAt: new Date() } }],
        narrators: [
          { narrator: { id: 'n2', name: 'Narrator 2', asin: 'NARR2', createdAt: new Date() } },
        ],
        series: [],
      },
    ];

    mockPrisma.book.findMany.mockResolvedValue(mockBooks);
    mockPrisma.book.count.mockResolvedValue(2);

    const searchParams = Promise.resolve({ page: '1' });
    const page = await Home({ searchParams });
    const { container } = render(page);

    expect(mockPrisma.book.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        skip: 0,
        take: 20,
        include: expect.objectContaining({
          authors: expect.any(Object),
          narrators: expect.any(Object),
          series: expect.any(Object),
        }),
        orderBy: { title: 'asc' },
      })
    );

    expect(mockPrisma.book.count).toHaveBeenCalled();
    expect(screen.getByText('Test Book 1')).toBeInTheDocument();
    expect(screen.getByText('Test Book 2')).toBeInTheDocument();
  });

  it('handles pagination parameters', async () => {
    const mockBooks = [
      {
        id: '21',
        asin: 'B021',
        title: 'Page 2 Book',
        publisherSummary: 'Summary',
        runtimeMinutes: 300,
        releaseDate: new Date('2024-01-01'),
        publisher: 'Test Publisher',
        coverUrl: '/cover.jpg',
        audioUrl: '/audio.m4b',
        createdAt: new Date(),
        updatedAt: new Date(),
        description: null,
        metadata: null,
        authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
        narrators: [
          { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
        ],
        series: [],
      },
    ];

    mockPrisma.book.findMany.mockResolvedValue(mockBooks);
    mockPrisma.book.count.mockResolvedValue(30);

    const searchParams = Promise.resolve({ page: '2' });
    const page = await Home({ searchParams });
    render(page);

    // Should skip first 20 books (page 2)
    expect(mockPrisma.book.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        skip: 20,
        take: 20,
      })
    );
  });

  it('handles sort parameter for title', async () => {
    mockPrisma.book.findMany.mockResolvedValue([]);
    mockPrisma.book.count.mockResolvedValue(0);

    const searchParams = Promise.resolve({ page: '1', sort: 'title' });
    const page = await Home({ searchParams });
    render(page);

    expect(mockPrisma.book.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        orderBy: { title: 'asc' },
      })
    );
  });

  it('displays total book count', async () => {
    mockPrisma.book.findMany.mockResolvedValue([]);
    mockPrisma.book.count.mockResolvedValue(42);

    const searchParams = Promise.resolve({ page: '1' });
    const page = await Home({ searchParams });
    render(page);

    expect(screen.getByText(/42 books/i)).toBeInTheDocument();
  });

  it('renders browse navigation links', async () => {
    mockPrisma.book.findMany.mockResolvedValue([]);
    mockPrisma.book.count.mockResolvedValue(0);

    const searchParams = Promise.resolve({ page: '1' });
    const page = await Home({ searchParams });
    render(page);

    expect(screen.getByText('Browse Authors')).toBeInTheDocument();
    expect(screen.getByText('Browse Narrators')).toBeInTheDocument();
    expect(screen.getByText('Browse Series')).toBeInTheDocument();
    expect(screen.getByText('Browse Categories')).toBeInTheDocument();
  });

  it('renders search bar and sort dropdown', async () => {
    mockPrisma.book.findMany.mockResolvedValue([]);
    mockPrisma.book.count.mockResolvedValue(0);

    const searchParams = Promise.resolve({ page: '1' });
    const page = await Home({ searchParams });
    render(page);

    expect(screen.getByTestId('search-bar')).toBeInTheDocument();
    expect(screen.getByTestId('sort-dropdown')).toBeInTheDocument();
  });
});
