import { parsePagination, parseBookFields } from '@/lib/api-utils';

describe('Search & Browse API Helpers', () => {
  describe('parsePagination', () => {
    it('should parse valid pagination parameters', () => {
      const result = parsePagination('2', '20');

      expect(result).toEqual({
        page: 2,
        limit: 20,
        skip: 20, // (page 2 - 1) * limit 20
      });
    });

    it('should use defaults for null parameters', () => {
      const result = parsePagination(null, null);

      expect(result).toEqual({
        page: 1,
        limit: 20,
        skip: 0,
      });
    });

    it('should enforce minimum page of 1', () => {
      const result = parsePagination('0', '20');

      expect(result.page).toBe(1);
      expect(result.skip).toBe(0);
    });

    it('should enforce minimum limit of 1', () => {
      const result = parsePagination('1', '0');

      expect(result.limit).toBe(1);
    });

    it('should enforce maximum limit of 100', () => {
      const result = parsePagination('1', '200');

      expect(result.limit).toBe(100);
    });

    it('should handle negative page numbers', () => {
      const result = parsePagination('-5', '20');

      expect(result.page).toBe(1);
      expect(result.skip).toBe(0);
    });

    it('should calculate skip correctly for various pages', () => {
      expect(parsePagination('1', '20').skip).toBe(0);
      expect(parsePagination('2', '20').skip).toBe(20);
      expect(parsePagination('3', '20').skip).toBe(40);
      expect(parsePagination('5', '50').skip).toBe(200);
    });
  });

  describe('parseBookFields', () => {
    it('should return undefined for null input (all fields)', () => {
      const result = parseBookFields(null);

      expect(result).toBeUndefined();
    });

    it('should parse simple field list', () => {
      const result = parseBookFields('id,title,coverUrl');

      expect(result).toEqual({
        id: true,
        title: true,
        coverUrl: true,
      });
    });

    it('should handle whitespace in field list', () => {
      const result = parseBookFields('id, title, coverUrl');

      expect(result).toEqual({
        id: true,
        title: true,
        coverUrl: true,
      });
    });

    it('should handle relation fields with nested include', () => {
      const result = parseBookFields('id,title,authors');

      expect(result).toHaveProperty('id', true);
      expect(result).toHaveProperty('title', true);
      expect(result).toHaveProperty('authors');
      expect(result?.authors).toEqual({ include: { author: true } });
    });

    it('should handle multiple relation fields', () => {
      const result = parseBookFields('id,authors,narrators,series');

      expect(result?.authors).toEqual({ include: { author: true } });
      expect(result?.narrators).toEqual({ include: { narrator: true } });
      expect(result?.series).toEqual({ include: { series: true } });
    });

    it('should handle chapters relation with orderBy', () => {
      const result = parseBookFields('id,chapters');

      expect(result?.chapters).toEqual({ orderBy: { chapterNumber: 'asc' } });
    });

    it('should return undefined for empty select (no valid fields)', () => {
      const result = parseBookFields('invalidField,alsoInvalid');

      expect(result).toBeUndefined();
    });

    it('should filter out invalid fields', () => {
      const result = parseBookFields('id,invalidField,title');

      expect(result).toEqual({
        id: true,
        title: true,
      });
    });

    it('should handle all common fields', () => {
      const result = parseBookFields(
        'id,asin,title,description,publisherSummary,runtimeMinutes,releaseDate,publisher,coverUrl,audioUrl,createdAt,updatedAt'
      );

      expect(result).toHaveProperty('id', true);
      expect(result).toHaveProperty('asin', true);
      expect(result).toHaveProperty('title', true);
      expect(result).toHaveProperty('description', true);
      expect(result).toHaveProperty('publisherSummary', true);
      expect(result).toHaveProperty('runtimeMinutes', true);
      expect(result).toHaveProperty('releaseDate', true);
      expect(result).toHaveProperty('publisher', true);
      expect(result).toHaveProperty('coverUrl', true);
      expect(result).toHaveProperty('audioUrl', true);
      expect(result).toHaveProperty('createdAt', true);
      expect(result).toHaveProperty('updatedAt', true);
    });
  });
});
