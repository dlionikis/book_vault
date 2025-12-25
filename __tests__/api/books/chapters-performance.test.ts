/**
 * @jest-environment node
 */

import { GET } from '@/app/api/books/[id]/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { prisma } from '@/lib/db';

// Mock NextAuth
jest.mock('next-auth');
const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;

// Mock prisma
jest.mock('@/lib/db', () => ({
  prisma: {
    book: {
      findUnique: jest.fn(),
    },
  },
}));

describe('Chapter Performance Tests', () => {
  const mockSession = {
    user: {
      id: 'test-user-id',
      email: 'test@example.com',
    },
    expires: '2025-12-31',
  };

  const mockBookId = 'test-book-id';

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetServerSession.mockResolvedValue(mockSession);
  });

  it('fetches book with ?include=chapters returns chapters array', async () => {
    const mockBook = {
      id: mockBookId,
      asin: 'TEST123',
      title: 'Test Book',
      description: 'Test Description',
      publisherSummary: null,
      runtimeMinutes: 300,
      releaseDate: new Date('2025-01-01'),
      publisher: 'Test Publisher',
      coverUrl: 'test-cover.jpg',
      audioUrl: 'test-audio.mp3',
      metadata: null,
      createdAt: new Date('2025-01-01'),
      updatedAt: new Date('2025-01-01'),
      authors: [],
      narrators: [],
      series: [],
      categories: [],
      chapters: [
        {
          id: 'chapter-1',
          chapterNumber: 1,
          title: 'Chapter 1',
          startTime: 0,
          endTime: 100.5,
          duration: 100.5,
        },
        {
          id: 'chapter-2',
          chapterNumber: 2,
          title: 'Chapter 2',
          startTime: 100.5,
          endTime: 200.75,
          duration: 100.25,
        },
      ],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const request = new NextRequest(
      `http://localhost:3000/api/books/${mockBookId}?include=chapters`
    );
    const params = { id: mockBookId };

    const response = await GET(request, { params });
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.chapters).toBeDefined();
    expect(Array.isArray(data.chapters)).toBe(true);
    expect(data.chapters.length).toBe(2);
    expect(data.chapters[0].chapterNumber).toBe(1);
    expect(data.chapters[0].title).toBe('Chapter 1');
    expect(data.chapters[0].startTime).toBe(0);
    expect(data.chapters[0].endTime).toBe(100.5);
    expect(data.chapters[0].duration).toBe(100.5);

    // Verify caching header is set
    expect(response.headers.get('Cache-Control')).toBe('public, max-age=86400');
  });

  it('fetches book without query param omits chapters', async () => {
    const mockBook = {
      id: mockBookId,
      asin: 'TEST123',
      title: 'Test Book',
      description: 'Test Description',
      publisherSummary: null,
      runtimeMinutes: 300,
      releaseDate: new Date('2025-01-01'),
      publisher: 'Test Publisher',
      coverUrl: 'test-cover.jpg',
      audioUrl: 'test-audio.mp3',
      metadata: null,
      createdAt: new Date('2025-01-01'),
      updatedAt: new Date('2025-01-01'),
      authors: [],
      narrators: [],
      series: [],
      categories: [],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const request = new NextRequest(`http://localhost:3000/api/books/${mockBookId}`);
    const params = { id: mockBookId };

    const response = await GET(request, { params });
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.chapters).toBeUndefined();

    // Verify no caching header when chapters not included
    expect(response.headers.get('Cache-Control')).toBeNull();
  });

  it('chapter timestamps are in correct format (seconds, decimal)', async () => {
    const mockBook = {
      id: mockBookId,
      asin: 'TEST123',
      title: 'Test Book',
      description: 'Test Description',
      publisherSummary: null,
      runtimeMinutes: 300,
      releaseDate: new Date('2025-01-01'),
      publisher: 'Test Publisher',
      coverUrl: 'test-cover.jpg',
      audioUrl: 'test-audio.mp3',
      metadata: null,
      createdAt: new Date('2025-01-01'),
      updatedAt: new Date('2025-01-01'),
      authors: [],
      narrators: [],
      series: [],
      categories: [],
      chapters: [
        {
          id: 'chapter-1',
          chapterNumber: 1,
          title: 'Chapter 1',
          startTime: 123.45, // Decimal seconds
          endTime: 456.78,
          duration: 333.33,
        },
      ],
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const request = new NextRequest(
      `http://localhost:3000/api/books/${mockBookId}?include=chapters`
    );
    const params = { id: mockBookId };

    const response = await GET(request, { params });
    const data = await response.json();

    expect(data.chapters[0].startTime).toBe(123.45);
    expect(data.chapters[0].endTime).toBe(456.78);
    expect(data.chapters[0].duration).toBe(333.33);

    // Verify all are numbers, not strings
    expect(typeof data.chapters[0].startTime).toBe('number');
    expect(typeof data.chapters[0].endTime).toBe('number');
    expect(typeof data.chapters[0].duration).toBe('number');
  });

  it('handles books with many chapters (50+)', async () => {
    // Create mock book with 50 chapters
    const chapters = Array.from({ length: 50 }, (_, i) => ({
      id: `chapter-${i + 1}`,
      chapterNumber: i + 1,
      title: `Chapter ${i + 1}`,
      startTime: i * 100,
      endTime: (i + 1) * 100,
      duration: 100,
    }));

    const mockBook = {
      id: mockBookId,
      asin: 'TEST123',
      title: 'Test Book',
      description: 'Test Description',
      publisherSummary: null,
      runtimeMinutes: 5000,
      releaseDate: new Date('2025-01-01'),
      publisher: 'Test Publisher',
      coverUrl: 'test-cover.jpg',
      audioUrl: 'test-audio.mp3',
      metadata: null,
      createdAt: new Date('2025-01-01'),
      updatedAt: new Date('2025-01-01'),
      authors: [],
      narrators: [],
      series: [],
      categories: [],
      chapters,
    };

    (prisma.book.findUnique as jest.Mock).mockResolvedValue(mockBook);

    const request = new NextRequest(
      `http://localhost:3000/api/books/${mockBookId}?include=chapters`
    );
    const params = { id: mockBookId };

    const startTime = Date.now();
    const response = await GET(request, { params });
    const duration = Date.now() - startTime;
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.chapters.length).toBe(50);

    // Performance check: should complete reasonably fast
    // Note: This is mocked data, so actual DB query performance
    // would be tested in integration tests
    expect(duration).toBeLessThan(1000); // Under 1 second for API processing
  });

  it('returns 401 when not authenticated', async () => {
    mockGetServerSession.mockResolvedValue(null);

    const request = new NextRequest(
      `http://localhost:3000/api/books/${mockBookId}?include=chapters`
    );
    const params = { id: mockBookId };

    const response = await GET(request, { params });
    const data = await response.json();

    expect(response.status).toBe(401);
    expect(data.error).toBe('Unauthorized');
  });

  it('returns 404 when book not found', async () => {
    (prisma.book.findUnique as jest.Mock).mockResolvedValue(null);

    const request = new NextRequest(
      `http://localhost:3000/api/books/${mockBookId}?include=chapters`
    );
    const params = { id: mockBookId };

    const response = await GET(request, { params });
    const data = await response.json();

    expect(response.status).toBe(404);
    expect(data.error).toBe('Book not found');
  });
});
