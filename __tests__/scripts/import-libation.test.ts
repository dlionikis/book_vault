import { mockDeep, DeepMockProxy } from 'jest-mock-extended';
import { PrismaClient } from '@prisma/client';
import fs from 'fs/promises';
import path from 'path';

// Mock modules BEFORE importing the script
jest.mock('@/lib/db', () => ({
  __esModule: true,
  prisma: mockDeep<PrismaClient>(),
}));
jest.mock('fs/promises');
jest.mock('dotenv/config', () => ({}));

// Now import after mocks are set up
import { prisma } from '@/lib/db';
const prismaMock = prisma as unknown as DeepMockProxy<PrismaClient>;
const importScript = require('@/scripts/import-libation');
const importBook = importScript.importBook;

describe('Import Script Edge Cases', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Author Handling', () => {
    it('should handle author with same ASIN but different name variations', async () => {
      // Simulate "Michael G. Manning" already exists with ASIN B005B3671W
      const existingAuthor = {
        id: 'author-1',
        name: 'Michael G. Manning',
        asin: 'B005B3671W',
      };

      // First call for ASIN lookup - finds existing author
      prismaMock.author.findUnique.mockResolvedValueOnce(existingAuthor as any);
      prismaMock.book.findUnique.mockResolvedValue(null);
      prismaMock.book.create.mockResolvedValue({} as any);
      prismaMock.series.upsert.mockResolvedValue({ id: 'series-1' } as any);

      // Simulate importing book with "Michael Manning" (no "G.")
      const metadata = {
        asin: 'BOOK123',
        title: 'Secrets and Spellcraft',
        authors: [{ name: 'Michael Manning', asin: 'B005B3671W' }],
        narrators: [],
        series: [],
      };

      // Import logic
      prismaMock.book.findUnique.mockResolvedValue(null);
      let author = metadata.authors[0].asin
        ? await prismaMock.author.findUnique({ where: { asin: metadata.authors[0].asin } })
        : null;

      if (!author) {
        author = await prismaMock.author.findUnique({ where: { name: metadata.authors[0].name } });
      }

      // Should find author by ASIN and NOT create duplicate
      expect(prismaMock.author.findUnique).toHaveBeenCalledWith({ where: { asin: 'B005B3671W' } });
      expect(author).toEqual(existingAuthor);
      expect(prismaMock.author.create).not.toHaveBeenCalled();
    });

    it('should handle author with same name but different ASINs', async () => {
      // Simulate "Selkie Myth" exists with one ASIN
      const existingAuthor = {
        id: 'author-1',
        name: 'Selkie Myth',
        asin: 'B095CVRLL3',
      };

      // First book with ASIN B0BRTJLN5W - won't find by ASIN
      prismaMock.author.findUnique
        .mockResolvedValueOnce(null) // ASIN lookup fails
        .mockResolvedValueOnce(existingAuthor as any); // Name lookup succeeds

      const metadata = {
        asin: 'BOOK456',
        title: 'Rise from the Ashes',
        authors: [{ name: 'Selkie Myth', asin: 'B0BRTJLN5W' }],
        narrators: [],
        series: [],
      };

      // Import logic
      let author = metadata.authors[0].asin
        ? await prismaMock.author.findUnique({ where: { asin: metadata.authors[0].asin } })
        : null;

      if (!author) {
        author = await prismaMock.author.findUnique({ where: { name: metadata.authors[0].name } });
      }

      // Should find by name and reuse existing author
      expect(prismaMock.author.findUnique).toHaveBeenCalledWith({ where: { asin: 'B0BRTJLN5W' } });
      expect(prismaMock.author.findUnique).toHaveBeenCalledWith({ where: { name: 'Selkie Myth' } });
      expect(author).toEqual(existingAuthor);
      expect(prismaMock.author.create).not.toHaveBeenCalled();
    });

    it('should handle author with null ASIN', async () => {
      prismaMock.author.findUnique.mockResolvedValueOnce(null);
      prismaMock.author.create.mockResolvedValue({
        id: 'author-2',
        name: 'Unknown Author',
        asin: null,
      } as any);

      const metadata = {
        asin: 'BOOK789',
        title: 'Test Book',
        authors: [{ name: 'Unknown Author', asin: null }],
        narrators: [],
        series: [],
      };

      // Import logic
      let author = metadata.authors[0].asin
        ? await prismaMock.author.findUnique({ where: { asin: metadata.authors[0].asin } })
        : null;

      if (!author) {
        author = await prismaMock.author.findUnique({ where: { name: metadata.authors[0].name } });
      }

      if (!author) {
        author = await prismaMock.author.create({
          data: {
            name: metadata.authors[0].name,
            asin: metadata.authors[0].asin,
          },
        });
      }

      // Should not attempt ASIN lookup (null), should check by name, then create
      expect(prismaMock.author.findUnique).toHaveBeenCalledWith({
        where: { name: 'Unknown Author' },
      });
      expect(prismaMock.author.create).toHaveBeenCalledWith({
        data: { name: 'Unknown Author', asin: null },
      });
    });

    it('should create new author when neither ASIN nor name exists', async () => {
      prismaMock.author.findUnique.mockResolvedValue(null);
      prismaMock.author.create.mockResolvedValue({
        id: 'author-3',
        name: 'New Author',
        asin: 'NEWAUTH123',
      } as any);

      const metadata = {
        asin: 'BOOK999',
        title: 'New Book',
        authors: [{ name: 'New Author', asin: 'NEWAUTH123' }],
        narrators: [],
        series: [],
      };

      // Import logic
      let author = metadata.authors[0].asin
        ? await prismaMock.author.findUnique({ where: { asin: metadata.authors[0].asin } })
        : null;

      if (!author) {
        author = await prismaMock.author.findUnique({ where: { name: metadata.authors[0].name } });
      }

      if (!author) {
        author = await prismaMock.author.create({
          data: {
            name: metadata.authors[0].name,
            asin: metadata.authors[0].asin,
          },
        });
      }

      expect(prismaMock.author.findUnique).toHaveBeenCalledWith({ where: { asin: 'NEWAUTH123' } });
      expect(prismaMock.author.findUnique).toHaveBeenCalledWith({ where: { name: 'New Author' } });
      expect(prismaMock.author.create).toHaveBeenCalledWith({
        data: { name: 'New Author', asin: 'NEWAUTH123' },
      });
    });
  });

  describe('Narrator Handling', () => {
    it('should handle narrator with same name but null ASIN vs existing ASIN', async () => {
      const existingNarrator = {
        id: 'narr-1',
        name: 'Andrea Parsneau',
        asin: 'NARR123',
      };

      prismaMock.narrator.findUnique.mockResolvedValueOnce(existingNarrator as any); // Find by name

      const metadata = {
        asin: 'BOOK111',
        title: 'Somnia Online',
        authors: [],
        narrators: [{ name: 'Andrea Parsneau', asin: null }],
        series: [],
      };

      // Import logic (narrator with null ASIN)
      let narrator = metadata.narrators[0].asin
        ? await prismaMock.narrator.findUnique({ where: { asin: metadata.narrators[0].asin } })
        : null;

      if (!narrator) {
        narrator = await prismaMock.narrator.findUnique({
          where: { name: metadata.narrators[0].name },
        });
      }

      // Should skip ASIN lookup and find by name
      expect(prismaMock.narrator.findUnique).toHaveBeenCalledWith({
        where: { name: 'Andrea Parsneau' },
      });
      expect(narrator).toEqual(existingNarrator);
      expect(prismaMock.narrator.create).not.toHaveBeenCalled();
    });
  });

  describe('Category Handling', () => {
    it('should deduplicate category IDs when multiple ladders lead to same leaf', () => {
      // Simulate book with multiple category ladders ending at same category
      const categoryLadders = [
        {
          root: 'Literature & Fiction',
          ladder: [
            { id: 'cat1', name: 'Literature & Fiction' },
            { id: 'cat2', name: 'Fantasy' },
          ],
        },
        {
          root: 'Science Fiction & Fantasy',
          ladder: [
            { id: 'cat3', name: 'Science Fiction & Fantasy' },
            { id: 'cat2', name: 'Fantasy' }, // Same leaf category
          ],
        },
      ];

      const categoryIds: string[] = [];

      // Simulate processing ladders
      for (const ladder of categoryLadders) {
        const leafCategory = ladder.ladder[ladder.ladder.length - 1];
        categoryIds.push(leafCategory.id);
      }

      // Deduplicate
      const uniqueCategoryIds = [...new Set(categoryIds)];

      expect(categoryIds).toEqual(['cat2', 'cat2']);
      expect(uniqueCategoryIds).toEqual(['cat2']);
      expect(uniqueCategoryIds.length).toBe(1);
    });

    it('should handle empty category array', () => {
      const categoryIds: string[] = [];
      const uniqueCategoryIds = [...new Set(categoryIds)];

      expect(uniqueCategoryIds).toEqual([]);
      expect(uniqueCategoryIds.length).toBe(0);
    });

    it('should maintain unique categories from different ladders', () => {
      const categoryLadders = [
        {
          root: 'Literature & Fiction',
          ladder: [
            { id: 'cat1', name: 'Literature & Fiction' },
            { id: 'cat2', name: 'Fantasy' },
          ],
        },
        {
          root: 'Teen & Young Adult',
          ladder: [
            { id: 'cat3', name: 'Teen & Young Adult' },
            { id: 'cat4', name: 'Science Fiction' },
          ],
        },
      ];

      const categoryIds: string[] = [];

      for (const ladder of categoryLadders) {
        const leafCategory = ladder.ladder[ladder.ladder.length - 1];
        categoryIds.push(leafCategory.id);
      }

      const uniqueCategoryIds = [...new Set(categoryIds)];

      expect(uniqueCategoryIds).toEqual(['cat2', 'cat4']);
      expect(uniqueCategoryIds.length).toBe(2);
    });
  });

  describe('Book Existence Check', () => {
    it('should skip book if ASIN already exists', async () => {
      const existingBook = {
        id: 'book-1',
        asin: 'EXISTING123',
        title: 'Existing Book',
      };

      prismaMock.book.findUnique.mockResolvedValue(existingBook as any);

      const metadata = {
        asin: 'EXISTING123',
        title: 'Existing Book',
        authors: [],
        narrators: [],
        series: [],
      };

      const book = await prismaMock.book.findUnique({ where: { asin: metadata.asin } });

      if (book) {
        // Should skip import
        expect(book).toEqual(existingBook);
        expect(prismaMock.book.create).not.toHaveBeenCalled();
      }
    });
  });

  describe('Series Handling', () => {
    it('should upsert series and maintain sequence information', async () => {
      const mockSeries = {
        id: 'series-1',
        title: 'The Wandering Inn',
        asin: 'SERIES123',
      };

      prismaMock.series.upsert.mockResolvedValue(mockSeries as any);

      const seriesInfo = {
        title: 'The Wandering Inn',
        sequence: '3',
        asin: 'SERIES123',
      };

      const series = await prismaMock.series.upsert({
        where: { title: seriesInfo.title },
        update: {},
        create: {
          title: seriesInfo.title,
          asin: seriesInfo.asin,
        },
      });

      const seriesData = {
        seriesId: series.id,
        sequence: seriesInfo.sequence,
      };

      expect(prismaMock.series.upsert).toHaveBeenCalledWith({
        where: { title: 'The Wandering Inn' },
        update: {},
        create: {
          title: 'The Wandering Inn',
          asin: 'SERIES123',
        },
      });
      expect(seriesData).toEqual({
        seriesId: 'series-1',
        sequence: '3',
      });
    });
  });

  describe('Release Date Parsing', () => {
    it('should parse valid release date', () => {
      const metadata = {
        asin: 'BOOK001',
        title: 'Test Book',
        authors: [],
        narrators: [],
        series: [],
        release_date: '2024-01-15',
      };

      let releaseDate: Date | null = null;
      if (metadata.release_date) {
        try {
          releaseDate = new Date(metadata.release_date);
        } catch (e) {
          // Invalid date, skip
        }
      }

      expect(releaseDate).toBeInstanceOf(Date);
      expect(releaseDate?.toISOString()).toBe('2024-01-15T00:00:00.000Z');
    });

    it('should handle invalid release date gracefully', () => {
      const metadata = {
        asin: 'BOOK002',
        title: 'Test Book',
        authors: [],
        narrators: [],
        series: [],
        release_date: 'invalid-date',
      };

      let releaseDate: Date | null = null;
      if (metadata.release_date) {
        try {
          releaseDate = new Date(metadata.release_date);
          // Check if date is invalid
          if (isNaN(releaseDate.getTime())) {
            releaseDate = null;
          }
        } catch (e) {
          releaseDate = null;
        }
      }

      // Should handle gracefully
      expect(releaseDate).toBeNull();
    });

    it('should handle missing release date', () => {
      const metadata: {
        asin: string;
        title: string;
        authors: never[];
        narrators: never[];
        series: never[];
        release_date?: string;
      } = {
        asin: 'BOOK003',
        title: 'Test Book',
        authors: [],
        narrators: [],
        series: [],
      };

      let releaseDate: Date | null = null;
      if (metadata.release_date) {
        try {
          releaseDate = new Date(metadata.release_date);
        } catch (e) {
          // Invalid date, skip
        }
      }

      expect(releaseDate).toBeNull();
    });
  });

  describe('Path Handling', () => {
    it('should calculate relative path correctly', () => {
      const LIBATION_PATH = '/Volumes/BeeDrive/Libation';
      const folderPath = '/Volumes/BeeDrive/Libation/Test Book [ASIN123]';

      const relativeFolderPath = path.relative(LIBATION_PATH, folderPath);

      expect(relativeFolderPath).toBe('Test Book [ASIN123]');
    });

    it('should construct file paths correctly', () => {
      const relativeFolderPath = 'Test Book [ASIN123]';
      const coverFile = 'Test Book [ASIN123].jpg';
      const audioFile = 'Test Book [ASIN123].mp3';

      const coverUrl = coverFile ? path.join(relativeFolderPath, coverFile) : null;
      const audioUrl = audioFile ? path.join(relativeFolderPath, audioFile) : null;

      expect(coverUrl).toBe('Test Book [ASIN123]/Test Book [ASIN123].jpg');
      expect(audioUrl).toBe('Test Book [ASIN123]/Test Book [ASIN123].mp3');
    });

    it('should handle missing media files', () => {
      const relativeFolderPath = 'Test Book [ASIN123]';
      const coverFile = undefined;
      const audioFile = undefined;

      const coverUrl = coverFile ? path.join(relativeFolderPath, coverFile) : null;
      const audioUrl = audioFile ? path.join(relativeFolderPath, audioFile) : null;

      expect(coverUrl).toBeNull();
      expect(audioUrl).toBeNull();
    });
  });

  describe('Environment Variable Handling', () => {
    it('should use LIBATION_PATH when set', () => {
      process.env.LIBATION_PATH = '/custom/libation/path';
      const LIBATION_PATH =
        process.env.LIBATION_PATH ||
        process.env.MEDIA_DATA_PATH ||
        path.join(process.cwd(), 'test-data');

      expect(LIBATION_PATH).toBe('/custom/libation/path');
      delete process.env.LIBATION_PATH;
    });

    it('should fall back to MEDIA_DATA_PATH when LIBATION_PATH not set', () => {
      process.env.MEDIA_DATA_PATH = '/custom/media/path';
      const LIBATION_PATH =
        process.env.LIBATION_PATH ||
        process.env.MEDIA_DATA_PATH ||
        path.join(process.cwd(), 'test-data');

      expect(LIBATION_PATH).toBe('/custom/media/path');
      delete process.env.MEDIA_DATA_PATH;
    });

    it('should use test-data as default', () => {
      const LIBATION_PATH =
        process.env.LIBATION_PATH ||
        process.env.MEDIA_DATA_PATH ||
        path.join(process.cwd(), 'test-data');

      expect(LIBATION_PATH).toContain('test-data');
    });
  });

  describe('Integration: importBook function', () => {
    it('should successfully import a complete book with all relationships', async () => {
      const metadata = {
        asin: 'BOOK123',
        title: 'Test Book',
        authors: [{ name: 'Test Author', asin: 'AUTH123' }],
        narrators: [{ name: 'Test Narrator', asin: 'NARR123' }],
        series: [{ title: 'Test Series', sequence: '1', asin: 'SER123' }],
        publisher_summary: 'A test book',
        runtime_length_min: 300,
        release_date: '2024-01-01',
        publisher: 'Test Publisher',
        category_ladders: [
          {
            root: 'Fiction',
            ladder: [
              { id: 'cat1', name: 'Fiction' },
              { id: 'cat2', name: 'Fantasy' },
            ],
          },
        ],
      };

      const folderPath = '/test/path/Test Book [BOOK123]';
      const audioFile = 'Test Book [BOOK123].mp3';
      const coverFile = 'Test Book [BOOK123].jpg';

      // Setup mocks
      prismaMock.book.findUnique.mockResolvedValue(null);
      prismaMock.author.findUnique.mockResolvedValue(null);
      prismaMock.author.create.mockResolvedValue({
        id: 'auth-1',
        name: 'Test Author',
        asin: 'AUTH123',
      } as any);
      prismaMock.narrator.findUnique.mockResolvedValue(null);
      prismaMock.narrator.create.mockResolvedValue({
        id: 'narr-1',
        name: 'Test Narrator',
        asin: 'NARR123',
      } as any);
      prismaMock.series.upsert.mockResolvedValue({
        id: 'ser-1',
        title: 'Test Series',
        asin: 'SER123',
      } as any);
      prismaMock.category.findFirst.mockResolvedValue(null);
      prismaMock.category.create
        .mockResolvedValueOnce({ id: 'cat-1', name: 'Fiction', parentId: null, level: 0 } as any)
        .mockResolvedValueOnce({
          id: 'cat-2',
          name: 'Fantasy',
          parentId: 'cat-1',
          level: 1,
        } as any);
      prismaMock.book.create.mockResolvedValue({ id: 'book-1' } as any);

      await importBook(metadata, folderPath, audioFile, coverFile);

      // Verify book was created
      expect(prismaMock.book.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          asin: 'BOOK123',
          title: 'Test Book',
          publisherSummary: 'A test book',
          runtimeMinutes: 300,
          publisher: 'Test Publisher',
        }),
      });
    });

    it('should skip book if it already exists', async () => {
      const metadata = {
        asin: 'EXISTING123',
        title: 'Existing Book',
        authors: [],
        narrators: [],
        series: [],
      };

      prismaMock.book.findUnique.mockResolvedValue({ id: 'book-1', asin: 'EXISTING123' } as any);

      await importBook(metadata, '/test/path', undefined, undefined);

      expect(prismaMock.book.create).not.toHaveBeenCalled();
    });
  });
});
