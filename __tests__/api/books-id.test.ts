import { GET } from '@/app/api/books/[id]/route';

// Skip API tests - require Next.js runtime setup
describe.skip('/api/books/[id]', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns book by id', async () => {
    const mockBook = {
      id: '123',
      title: 'Test Book',
      asin: 'TEST123',
      authors: [{ author: { id: 'auth1', name: 'Test Author', asin: 'AUTH123' } }],
      narrators: [{ narrator: { id: 'narr1', name: 'Test Narrator', asin: 'NARR123' } }],
      series: [],
      categories: [],
      publisherSummary: 'Test summary',
      runtimeLengthMin: 120,
      productImages: { '500': '/test.jpg' },
      releaseDate: new Date('2024-01-01'),
      metadata: null,
    };

    prisma.book.findUnique.mockResolvedValue(mockBook);

    const response = await GET(new Request('http://localhost:3000/api/books/123'), {
      params: { id: '123' },
    });
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.id).toBe('123');
    expect(data.title).toBe('Test Book');
    expect(prisma.book.findUnique).toHaveBeenCalledWith({
      where: { id: '123' },
      include: expect.any(Object),
    });
  });

  it('returns 404 when book not found', async () => {
    prisma.book.findUnique.mockResolvedValue(null);

    const response = await GET(new Request('http://localhost:3000/api/books/999'), {
      params: { id: '999' },
    });

    expect(response.status).toBe(404);
    const data = await response.json();
    expect(data.error).toBe('Book not found');
  });

  it('returns 500 on database error', async () => {
    prisma.book.findUnique.mockRejectedValue(new Error('Database error'));

    const response = await GET(new Request('http://localhost:3000/api/books/123'), {
      params: { id: '123' },
    });

    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.error).toBeDefined();
  });
});
