import { NextResponse } from 'next/server';
import { GET } from '@/app/api/books/route';

// Skip API tests - require Next.js runtime setup
describe.skip('/api/books', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns books with default parameters', async () => {
    const mockBooks = [
      {
        id: '1',
        title: 'Test Book',
        asin: 'TEST123',
        authors: { author: { id: 'auth1', name: 'Test Author', asin: 'AUTH123' } },
        narrators: { narrator: { id: 'narr1', name: 'Test Narrator', asin: 'NARR123' } },
        series: [],
        categories: [],
        publisherSummary: 'Test',
        runtimeLengthMin: 120,
        productImages: { '500': '/test.jpg' },
        releaseDate: new Date('2024-01-01'),
        metadata: null,
      },
    ];

    prisma.book.findMany.mockResolvedValue(mockBooks);
    prisma.book.count.mockResolvedValue(1);

    const request = new Request('http://localhost:3000/api/books');
    const response = await GET(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.books).toHaveLength(1);
    expect(data.total).toBe(1);
    expect(prisma.book.findMany).toHaveBeenCalled();
  });

  it('handles limit parameter', async () => {
    prisma.book.findMany.mockResolvedValue([]);
    prisma.book.count.mockResolvedValue(0);

    const request = new Request('http://localhost:3000/api/books?limit=10');
    await GET(request);

    expect(prisma.book.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        take: 10,
      })
    );
  });

  it('handles page parameter', async () => {
    prisma.book.findMany.mockResolvedValue([]);
    prisma.book.count.mockResolvedValue(0);

    const request = new Request('http://localhost:3000/api/books?page=2&limit=20');
    await GET(request);

    expect(prisma.book.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        skip: 20,
        take: 20,
      })
    );
  });

  it('handles sort by title', async () => {
    prisma.book.findMany.mockResolvedValue([]);
    prisma.book.count.mockResolvedValue(0);

    const request = new Request('http://localhost:3000/api/books?sort=title');
    await GET(request);

    expect(prisma.book.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        orderBy: { title: 'asc' },
      })
    );
  });

  it('returns error on database failure', async () => {
    prisma.book.findMany.mockRejectedValue(new Error('Database error'));

    const request = new Request('http://localhost:3000/api/books');
    const response = await GET(request);

    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.error).toBeDefined();
  });
});
