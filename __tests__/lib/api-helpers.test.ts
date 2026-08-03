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
    // requireUser re-checks the account exists on the bearer path (SEC-2).
    user: { findUnique: jest.fn() },
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
// `@/lib/api-utils` is deliberately NOT mocked. It is pure (uuid normalization,
// pagination math) so the real implementation is both cheaper and more honest
// than a stub.
//
// The previous mock reimplemented `normalizeUuid` as
// `if (!id || id === 'invalid-uuid') return null` — inventing validation the
// real function never had (it only lowercases). That made the
// "returns 400 for invalid UUID format" test pass against a fiction: the real
// helper let a malformed id through to Prisma. Mocking pure helpers hides the
// bug the test claims to cover.

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;
const mockTransformBook = transformBook as jest.MockedFunction<typeof transformBook>;

// Real UUIDs: handleEntityDetailWithBooks validates the format with isValidUuid
// (invariant 5.6), so placeholder ids like 'author-123' now correctly 400.
const AUTHOR_ID = '11111111-1111-4111-8111-111111111111';
const BOOK_ID = '22222222-2222-4222-8222-222222222222';
const SERIES_ID = '33333333-3333-4333-8333-333333333333';

describe('handleEntityDetailWithBooks', () => {
  const mockUser = { id: 'user-123', username: 'testuser' };
  const mockAuthor = {
    id: AUTHOR_ID,
    name: 'Test Author',
    asin: 'B123456789',
  };
  const mockBook = {
    id: BOOK_ID,
    title: 'Test Book',
    asin: 'B987654321',
  };
  const mockTransformedBook = {
    id: BOOK_ID,
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
    // requireUser looks the account up on the bearer path (SEC-2); default to
    // "still exists" so these tests exercise their own concern.
    (require('@/lib/db').prisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u' });
    mockTransformBook.mockReturnValue(mockTransformedBook as any);
  });

  describe('Authentication', () => {
    it('should return 401 when no session and no bearer token', async () => {
      mockGetServerSession.mockResolvedValue(null);
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(404);
      expect(data.error).toBe('Author not found');
    });

    it('should fetch entity when found', async () => {
      (prisma.author.findUnique as jest.Mock).mockResolvedValue(mockAuthor);
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(1);

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.id).toBe(AUTHOR_ID);
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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      await handleEntityDetailWithBooks(request, params, baseConfig);

      // The `book` clause excludes soft-hidden books from entity detail pages;
      // see docs/hidden-books.md.
      expect(prisma.bookAuthor.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { authorId: AUTHOR_ID, book: { hiddenAt: null } },
        })
      );
    });

    it('should apply pagination correctly', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(25);

      const request = new NextRequest(
        `http://localhost:3000/api/authors/${AUTHOR_ID}?page=2&limit=10`
      );
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(mockTransformBook).toHaveBeenCalledTimes(2);
      expect(data.books).toHaveLength(2);
    });

    it('should count total books correctly', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([{ book: mockBook }]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(42);

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.pagination.total).toBe(42);
      // Hidden books are excluded from the total too, so the count matches the
      // page the user actually sees.
      expect(prisma.bookAuthor.count).toHaveBeenCalledWith({
        where: { authorId: AUTHOR_ID, book: { hiddenAt: null } },
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

      const request = new NextRequest('http://localhost:3000/api/authors/${AUTHOR_ID}?limit=10');
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.pagination.pages).toBe(3); // ceil(25 / 10)
    });

    it('should handle page beyond total', async () => {
      (prisma.bookAuthor.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(5);

      const request = new NextRequest('http://localhost:3000/api/authors/${AUTHOR_ID}?page=10');
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(data.books).toEqual([]);
      expect(data.pagination.page).toBe(10);
    });

    it('should use custom limit from query params', async () => {
      (prisma.bookAuthor.count as jest.Mock).mockResolvedValue(100);

      const request = new NextRequest('http://localhost:3000/api/authors/${AUTHOR_ID}?limit=25');
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/series/${SERIES_ID}`);
      const params = { id: SERIES_ID };

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
      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      await handleEntityDetailWithBooks(request, params, customConfig);

      expect(prisma.author.findUnique).toHaveBeenCalledWith({
        where: { id: AUTHOR_ID },
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
      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

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

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      const response = await handleEntityDetailWithBooks(request, params, baseConfig);
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.error).toBe('Internal server error');
    });

    it('should log error with entity name', async () => {
      const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation();
      (prisma.author.findUnique as jest.Mock).mockRejectedValue(new Error('Database error'));

      const request = new NextRequest(`http://localhost:3000/api/authors/${AUTHOR_ID}`);
      const params = { id: AUTHOR_ID };

      await handleEntityDetailWithBooks(request, params, baseConfig);

      // logger.error formats a single string: "<timestamp> [ERROR] <message> <meta JSON>"
      expect(consoleErrorSpy).toHaveBeenCalledWith(
        expect.stringContaining('Error fetching author')
      );

      consoleErrorSpy.mockRestore();
    });
  });
});
