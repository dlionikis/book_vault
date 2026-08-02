import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { transformBook } from '@/lib/book-transformer';

// Mock dependencies
jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: {
    author: {
      findUnique: jest.fn(),
    },
    // The join table is resolved by entityKind inside lib/queries/entity-books,
    // so every kind the specs can reach needs a delegate here.
    bookAuthor: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
    bookNarrator: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
    bookSeries: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
    bookCategory: {
      findMany: jest.fn(),
      count: jest.fn(),
    },
  },
}));
jest.mock('@/lib/book-transformer');
jest.mock('@/lib/api-utils', () => ({
  normalizeUuid: jest.fn((id) => {
    // Simple UUID validation for tests
    if (!id || id === 'invalid-uuid') return null;
    return id;
  }),
  buildPagination: jest.fn((page, limit, total) => ({
    page,
    limit,
    total,
    pages: Math.ceil(total / limit),
  })),
  // Mirrors the real parsePagination (caps limit at 100).
  parsePagination: jest.fn((pageParam, limitParam) => {
    const page = Math.max(1, parseInt(pageParam || '1'));
    const limit = Math.min(100, Math.max(1, parseInt(limitParam || '20')));
    return { page, limit, skip: (page - 1) * limit };
  }),
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockTransformBook = transformBook as jest.MockedFunction<typeof transformBook>;

describe('handleEntityDetailWithBooks', () => {
  const mockUser = { id: 'user-123', username: 'testuser' };
  const mockAuthor = {
    id: 'author-123',
    name: 'Test Author',
    asin: 'B123456789',
  };
  const mockBook = {
    id: 'book-123',
    title: 'Test Book',
    asin: 'B987654321',
  };
  const mockTransformedBook = {
    id: 'book-123',
    title: 'Test Book',
    coverUrl: 'http://localhost:3000/api/images/test.jpg',
    audioUrl: 'http://localhost:3000/api/audio/test.mp3',
  };

  const baseConfig = {
    entityModel: prisma.author,
    entityKind: 'author' as const,
    entityName: 'Author',
    getResponseFields: (author: any) => ({
      id: author.id,
      name: author.name,
      asin: author.asin,
    }),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockTransformBook.mockReturnValue(mockTransformedBook as any);
  });

  describe('Authentication', () => {
    it('should return 401 when no session and no bearer token', async () => {
      mockGetServerSession.mockResolvedValue(null);
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(401);
      expect(data).toEqual({ error: 'Unauthorized' });
    });

    it('should accept valid session auth', async () => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
      mockGetAuthUserFromRequest.mockResolvedValue(null);
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);

      expect(response.status).toBe(200);
      expect(mockGetServerSession).toHaveBeenCalled();
    });

    it('should accept valid bearer token auth', async () => {
      mockGetServerSession.mockResolvedValue(null);
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);

      expect(response.status).toBe(200);
      expect(mockGetAuthUserFromRequest).toHaveBeenCalled();
    });
  });

  describe('Validation', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
    });

    it('should return 400 for invalid UUID format', async () => {
      const request = new NextRequest('http://localhost:3000/api/authors/invalid-uuid');
      const params = { id: 'invalid-uuid' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('Invalid author ID format');
    });

    it('should accept valid UUID', async () => {
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);

      expect(response.status).toBe(200);
    });
  });

  describe('Entity Fetching', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
    });

    it('should return 404 when entity not found', async () => {
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(null);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(404);
      expect(data.error).toBe('Author not found');
    });

    it('should fetch entity when found', async () => {
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.id).toBe('author-123');
      expect(data.name).toBe('Test Author');
    });
  });

  describe('Book Fetching', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
    });

    it('should fetch books with correct join table filter', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      await handleEntityDetailWithBooks(request, params, baseConfig);

      // The `book` clause excludes soft-hidden books from entity detail pages;
      // see docs/hidden-books.md.
      expect(prisma.bookAuthor.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { authorId: 'author-123', book: { hiddenAt: null } },
        })
      );
    });

    it('should apply pagination correctly', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(25);

      const request = new NextRequest(
        'http://localhost:3000/api/authors/author-123?page=2&limit=10'
      );
      const params = { id: 'author-123' };

      await handleEntityDetailWithBooks(request, params, baseConfig);

      expect(prisma.bookAuthor.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 10,
          take: 10,
        })
      );
    });

    it('should transform books with transformBook()', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([
        { book: mockBook },
        { book: { ...mockBook, id: 'book-456' } },
      ]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(2);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(mockTransformBook).toHaveBeenCalledTimes(2);
      expect(data.books).toHaveLength(2);
    });

    it('should count total books correctly', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(42);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.pagination.total).toBe(42);
      // Hidden books are excluded from the total too, so the count matches the
      // page the user actually sees.
      expect(prisma.bookAuthor.count).toHaveBeenCalledWith({
        where: { authorId: 'author-123', book: { hiddenAt: null } },
      });
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
    });

    it('should calculate pages correctly', async () => {
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(25);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123?limit=10');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.pagination.pages).toBe(3); // ceil(25 / 10)
    });

    it('should handle page beyond total', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(5);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123?page=10');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.books).toEqual([]);
      expect(data.pagination.page).toBe(10);
    });

    it('should use custom limit from query params', async () => {
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(100);

      const request = new NextRequest('http://localhost:3000/api/authors/author-123?limit=25');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.pagination.limit).toBe(25);
      expect(data.pagination.pages).toBe(4); // ceil(100 / 25)
    });
  });

  describe('Customization', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);
    });

    it('orders series books by in-series sequence', async () => {
      (prisma.bookSeries.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookSeries.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest('http://localhost:3000/api/series/series-123');
      const params = { id: 'series-123' };

      await handleEntityDetailWithBooks(request, params, {
        ...baseConfig,
        entityKind: 'series' as const,
        entityName: 'Series',
      });

      expect(prisma.bookSeries.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          orderBy: { sequence: 'asc' },
        })
      );
    });

    it('orders non-series books by title', async () => {
      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      await handleEntityDetailWithBooks(request, params, baseConfig);

      expect(prisma.bookAuthor.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          orderBy: { book: { title: 'asc' } },
        })
      );
    });

    it('should include custom entity relations when provided', async () => {
      const customConfig = {
        ...baseConfig,
        entityInclude: { parent: true },
      };

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      await handleEntityDetailWithBooks(request, params, customConfig);

      expect(prisma.author.findUnique).toHaveBeenCalledWith({
        where: { id: 'author-123' },
        include: { parent: true },
      });
    });
  });

  describe('Response Structure', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);
    });

    it('should return correct response shape', async () => {
      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data).toHaveProperty('id');
      expect(data).toHaveProperty('name');
      expect(data).toHaveProperty('asin');
      expect(data).toHaveProperty('books');
      expect(data).toHaveProperty('pagination');
      expect(data.pagination).toHaveProperty('page');
      expect(data.pagination).toHaveProperty('limit');
      expect(data.pagination).toHaveProperty('total');
      expect(data.pagination).toHaveProperty('pages');
    });

    it('should only include fields from getResponseFields()', async () => {
      const customConfig = {
        ...baseConfig,
        getResponseFields: (author: any) => ({
          id: author.id,
          name: author.name,
          // Intentionally omit 'asin'
        }),
      };

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, customConfig);
      const data = await response.json();

      expect(data).toHaveProperty('id');
      expect(data).toHaveProperty('name');
      expect(data).not.toHaveProperty('asin');
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      mockGetServerSession.mockResolvedValue({ user: mockUser } as any);
    });

    it('should return 500 on database error', async () => {
      (prisma.author.findUnique as jest.Mock).mockRejectedValue(new Error('Database error'));

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.error).toBe('Internal server error');
    });

    it('should log error with entity name', async () => {
      const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation();
      (prisma.author.findUnique as jest.Mock).mockRejectedValue(new Error('Database error'));

      const request = new NextRequest('http://localhost:3000/api/authors/author-123');
      const params = { id: 'author-123' };

      await handleEntityDetailWithBooks(request, params, baseConfig);

      // logger.error formats a single string: "<timestamp> [ERROR] <message> <meta JSON>"
      expect(consoleErrorSpy).toHaveBeenCalledWith(
        expect.stringContaining('Error fetching author')
      );

      consoleErrorSpy.mockRestore();
    });
  });
});
