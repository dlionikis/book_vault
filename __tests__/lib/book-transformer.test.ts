/**
 * Book Transformer Tests
 *
 * Ensures transformBook() includes all required fields from the OpenAPI spec
 */

import { transformBook, BookWithIncludes } from '@/lib/book-transformer';

// Mock the media helpers - now async
jest.mock('@/lib/media', () => ({
  getCoverUrl: async (url: string) => (url ? `https://example.com/covers/${url}` : null),
  getAudioUrl: async (url: string) => (url ? `https://example.com/audio/${url}` : null),
}));

describe('book-transformer', () => {
  const mockBook: BookWithIncludes = {
    id: '550e8400-e29b-41d4-a716-446655440000',
    asin: 'B002V5D1CG',
    title: 'The Name of the Wind',
    description: null,
    publisherSummary: 'A great book',
    runtimeMinutes: 1068,
    releaseDate: new Date('2008-04-01'),
    publisher: 'DAW',
    coverUrl: 'cover.jpg',
    audioUrl: 'audio.m4b',
    metadata: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    audioAvailability: 'AVAILABLE',
    availabilityCheckedAt: null,
    authors: [
      {
        bookId: '550e8400-e29b-41d4-a716-446655440000',
        authorId: 'author-1',
        author: {
          id: 'author-1',
          name: 'Patrick Rothfuss',
          asin: 'AUTHOR1',
          createdAt: new Date(),
        },
      },
    ],
    narrators: [
      {
        bookId: '550e8400-e29b-41d4-a716-446655440000',
        narratorId: 'narrator-1',
        narrator: {
          id: 'narrator-1',
          name: 'Nick Podehl',
          asin: 'NARRATOR1',
          createdAt: new Date(),
        },
      },
    ],
    series: [
      {
        bookId: '550e8400-e29b-41d4-a716-446655440000',
        seriesId: 'series-1',
        sequence: 1,
        series: {
          id: 'series-1',
          title: 'The Kingkiller Chronicle',
          asin: 'SERIES1',
          createdAt: new Date(),
        },
      },
    ],
    categories: [
      {
        bookId: '550e8400-e29b-41d4-a716-446655440000',
        categoryId: 'category-1',
        category: {
          id: 'category-1',
          name: 'Fantasy',
          level: 1,
          parentId: null,
          createdAt: new Date(),
        },
      },
    ],
  };

  describe('transformBook', () => {
    it('should include all required fields from OpenAPI spec', async () => {
      const result = await transformBook(mockBook);

      // Required fields
      expect(result).toHaveProperty('id');
      expect(result).toHaveProperty('asin');
      expect(result).toHaveProperty('title');
      expect(result).toHaveProperty('runtimeMinutes');
      expect(result).toHaveProperty('coverUrl');
      expect(result).toHaveProperty('audioUrl');
      expect(result).toHaveProperty('authors');

      // Optional fields (but should always be present)
      expect(result).toHaveProperty('publisherSummary');
      expect(result).toHaveProperty('releaseDate');
      expect(result).toHaveProperty('publisher');
      expect(result).toHaveProperty('narrators');
      expect(result).toHaveProperty('series');
      expect(result).toHaveProperty('categories');
    });

    it('should transform all fields correctly', async () => {
      const result = await transformBook(mockBook);

      expect(result.id).toBe('550e8400-e29b-41d4-a716-446655440000');
      expect(result.asin).toBe('B002V5D1CG');
      expect(result.title).toBe('The Name of the Wind');
      expect(result.publisherSummary).toBe('A great book');
      expect(result.runtimeMinutes).toBe(1068);
      expect(result.releaseDate).toBe('2008-04-01');
      expect(result.publisher).toBe('DAW');
      expect(result.coverUrl).toBe('https://example.com/covers/cover.jpg');
      expect(result.audioUrl).toBe('https://example.com/audio/audio.m4b');
    });

    it('should transform authors correctly', async () => {
      const result = await transformBook(mockBook);

      expect(result.authors).toHaveLength(1);
      expect(result.authors[0]).toEqual({
        id: 'author-1',
        name: 'Patrick Rothfuss',
        asin: 'AUTHOR1',
      });
    });

    it('should transform narrators correctly', async () => {
      const result = await transformBook(mockBook);

      expect(result.narrators).toHaveLength(1);
      expect(result.narrators[0]).toEqual({
        id: 'narrator-1',
        name: 'Nick Podehl',
        asin: 'NARRATOR1',
      });
    });

    it('should transform series correctly', async () => {
      const result = await transformBook(mockBook);

      expect(result.series).toHaveLength(1);
      expect(result.series[0]).toEqual({
        id: 'series-1',
        title: 'The Kingkiller Chronicle',
        asin: 'SERIES1',
        sequence: 1,
      });
    });

    it('should transform categories correctly', async () => {
      const result = await transformBook(mockBook);

      expect(result.categories).toHaveLength(1);
      expect(result.categories[0]).toEqual({
        id: 'category-1',
        name: 'Fantasy',
      });
    });

    it('should handle empty arrays', async () => {
      const bookWithoutRelations: BookWithIncludes = {
        ...mockBook,
        authors: [],
        narrators: [],
        series: [],
        categories: [],
      };

      const result = await transformBook(bookWithoutRelations);

      expect(result.authors).toEqual([]);
      expect(result.narrators).toEqual([]);
      expect(result.series).toEqual([]);
      expect(result.categories).toEqual([]);
    });

    it('should not include Prisma metadata fields', async () => {
      const result = await transformBook(mockBook);

      // Should NOT include createdAt, updatedAt, or join table fields
      expect(result).not.toHaveProperty('createdAt');
      expect(result).not.toHaveProperty('updatedAt');
      expect(result).not.toHaveProperty('bookId');
      expect(result).not.toHaveProperty('authorId');
    });
  });
});
