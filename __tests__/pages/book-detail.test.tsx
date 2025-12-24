import { render, screen } from '@testing-library/react';
import BookDetailPage from '@/app/books/[id]/page';
import { notFound } from 'next/navigation';
import { getServerSession } from 'next-auth';
import { prisma } from '@/lib/db';

// Mock Prisma Client
jest.mock('@/lib/db', () => ({
  prisma: {
    book: {
      findUnique: jest.fn(),
    },
    userList: {
      findFirst: jest.fn(),
    },
    userListBook: {
      findFirst: jest.fn(),
    },
    userProgress: {
      findUnique: jest.fn(),
    },
    $disconnect: jest.fn(),
  },
}));

// Mock next/navigation
jest.mock('next/navigation', () => ({
  notFound: jest.fn(),
  useRouter: () => ({
    push: jest.fn(),
  }),
}));

// Mock next-auth
jest.mock('next-auth', () => ({
  getServerSession: jest.fn(),
}));

// Mock auth config
jest.mock('@/lib/auth', () => ({
  authOptions: {},
}));

// Mock components
jest.mock('@/components/BackButton', () => {
  return function MockBackButton() {
    return <button data-testid="back-button">Back</button>;
  };
});

jest.mock('@/components/AddToLibraryButton', () => {
  return function MockAddToLibraryButton() {
    return <button data-testid="add-to-library">Add to Library</button>;
  };
});

jest.mock('@/components/ProgressControls', () => {
  return function MockProgressControls() {
    return <div data-testid="progress-controls">Progress Controls</div>;
  };
});

// Mock next/image
jest.mock('next/image', () => ({
  __esModule: true,
  default: (props: any) => {
    return <img {...props} />;
  },
}));

describe('Book Detail Page', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (notFound as jest.Mock).mockImplementation(() => {
      throw new Error('Not Found');
    });

    // Mock getServerSession to return no session by default
    (getServerSession as jest.Mock).mockResolvedValue(null);

    // Mock userList and userListBook queries to return null by default (not in library)
    (prisma.userList.findFirst as jest.Mock).mockResolvedValue(null);
    (prisma.userListBook.findFirst as jest.Mock).mockResolvedValue(null);
    (prisma.userProgress.findUnique as jest.Mock).mockResolvedValue(null);
  });

  it('renders book details from database', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B00VVZPEX6',
      title: 'A Darker Shade of Magic',
      description: 'Test description',
      publisherSummary: '<p>A thrilling fantasy novel</p>',
      runtimeMinutes: 483,
      releaseDate: new Date('2015-02-24'),
      publisher: 'Macmillan Audio',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: {
        customer_reviews: [
          {
            id: 'review-1',
            author_name: 'John Doe',
            title: 'Great book!',
            body: 'I loved this book.',
            submission_date: '2024-01-01',
            ratings: {
              overall_rating: 5,
              performance_rating: 5,
              story_rating: 5,
            },
            review_content_scores: {
              num_helpful_votes: 10,
              num_unhelpful_votes: 0,
            },
          },
        ],
      },
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [
        {
          author: {
            id: 'author-1',
            name: 'V.E. Schwab',
            asin: 'AUTH001',
            createdAt: new Date(),
          },
        },
      ],
      narrators: [
        {
          narrator: {
            id: 'narrator-1',
            name: 'Steven Crossley',
            asin: 'NARR001',
            createdAt: new Date(),
          },
        },
      ],
      series: [
        {
          series: {
            id: 'series-1',
            title: 'Shades of Magic',
            asin: 'SER001',
            createdAt: new Date(),
          },
          sequence: '1',
        },
      ],
      categories: [
        {
          category: {
            id: 'cat-1',
            name: 'Fantasy',
            level: 1,
            parentId: null,
            createdAt: new Date(),
          },
        },
      ],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    render(page);

    // Check that Prisma was called with correct parameters
    expect(prisma.book.findUnique).toHaveBeenCalledWith({
      where: { id: 'book-1' },
      include: expect.objectContaining({
        authors: expect.any(Object),
        narrators: expect.any(Object),
        series: expect.any(Object),
        categories: expect.any(Object),
      }),
    });

    // Check rendered content
    expect(screen.getAllByText('A Darker Shade of Magic')).toHaveLength(2); // Header and play button
    expect(screen.getAllByText('V.E. Schwab')).toHaveLength(2); // Author section and play button
    expect(screen.getByText('Steven Crossley')).toBeInTheDocument();
    expect(screen.getByText(/Shades of Magic/)).toBeInTheDocument();
    expect(screen.getByText('Fantasy')).toBeInTheDocument();
  });

  it('displays customer reviews when present in metadata', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B001',
      title: 'Test Book',
      publisherSummary: 'Summary',
      runtimeMinutes: 300,
      releaseDate: new Date(),
      publisher: 'Publisher',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: {
        customer_reviews: [
          {
            id: 'review-1',
            author_name: 'Jane Smith',
            title: 'Excellent audiobook',
            body: 'The narration was superb and the story was captivating.',
            submission_date: '2024-01-15',
            ratings: {
              overall_rating: 5,
              performance_rating: 5,
              story_rating: 4,
            },
            review_content_scores: {
              num_helpful_votes: 25,
              num_unhelpful_votes: 2,
            },
          },
        ],
      },
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
      narrators: [
        { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
      ],
      series: [],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    render(page);

    expect(screen.getByText('Customer Reviews (1)')).toBeInTheDocument();
    expect(screen.getByText('Excellent audiobook')).toBeInTheDocument();
    expect(screen.getByText('Jane Smith')).toBeInTheDocument();
    expect(screen.getByText(/The narration was superb/)).toBeInTheDocument();
    expect(screen.getByText(/25 people found this helpful/)).toBeInTheDocument();
  });

  it('calls notFound when book does not exist', async () => {
    (prisma.book.findUnique as jest.Mock).mockResolvedValue(null);

    const params = { id: 'nonexistent-id' };

    await expect(async () => {
      await BookDetailPage({ params });
    }).rejects.toThrow('Not Found');

    expect(notFound).toHaveBeenCalled();
  });

  it('displays runtime in hours and minutes', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B001',
      title: 'Test Book',
      publisherSummary: 'Summary',
      runtimeMinutes: 125, // 2 hr 5 min
      releaseDate: new Date(),
      publisher: 'Publisher',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
      narrators: [
        { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
      ],
      series: [],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    render(page);

    expect(screen.getByText('2 hr 5 min')).toBeInTheDocument();
  });

  it('displays series information with sequence number', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B001',
      title: 'Test Book',
      publisherSummary: 'Summary',
      runtimeMinutes: 300,
      releaseDate: new Date(),
      publisher: 'Publisher',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
      narrators: [
        { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
      ],
      series: [
        {
          series: {
            id: 'series-1',
            title: 'Epic Fantasy Series',
            asin: 'SER001',
            createdAt: new Date(),
          },
          sequence: '3',
        },
      ],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    render(page);

    expect(screen.getByText(/Epic Fantasy Series #3/)).toBeInTheDocument();
  });

  it('renders play button when audioUrl exists', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B001',
      title: 'Test Book',
      publisherSummary: 'Summary',
      runtimeMinutes: 300,
      releaseDate: new Date(),
      publisher: 'Publisher',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
      narrators: [
        { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
      ],
      series: [],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    render(page);

    expect(screen.getByText('Play Book')).toBeInTheDocument();
  });

  it('renders publisher summary as HTML', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B001',
      title: 'Test Book',
      publisherSummary: '<p>This is <strong>bold</strong> text</p>',
      runtimeMinutes: 300,
      releaseDate: new Date(),
      publisher: 'Publisher',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
      narrators: [
        { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
      ],
      series: [],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    const { container } = render(page);

    // Check that HTML is rendered (look for the strong tag)
    expect(container.querySelector('strong')).toBeInTheDocument();
    expect(screen.getByText('bold')).toBeInTheDocument();
  });

  it('renders Add to Library button', async () => {
    const mockBook = {
      id: 'book-1',
      asin: 'B001',
      title: 'Test Book',
      publisherSummary: 'Summary',
      runtimeMinutes: 300,
      releaseDate: new Date(),
      publisher: 'Publisher',
      coverUrl: '/cover.jpg',
      audioUrl: '/audio.m4b',
      metadata: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      authors: [{ author: { id: 'a1', name: 'Author', asin: 'AUTH1', createdAt: new Date() } }],
      narrators: [
        { narrator: { id: 'n1', name: 'Narrator', asin: 'NARR1', createdAt: new Date() } },
      ],
      series: [],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const params = { id: 'book-1' };
    const page = await BookDetailPage({ params });
    render(page);

    expect(screen.getByTestId('add-to-library')).toBeInTheDocument();
  });
});
