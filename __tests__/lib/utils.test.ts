import { formatRuntime } from '@/lib/utils/formatRuntime';
import { calculateRating } from '@/lib/utils/ratings';

describe('Utility Functions', () => {
  describe('formatRuntime', () => {
    it('formats minutes into hours and minutes', () => {
      expect(formatRuntime(90)).toBe('1h 30m');
    });

    it('handles exact hours', () => {
      expect(formatRuntime(120)).toBe('2h 0m');
    });

    it('handles less than an hour', () => {
      expect(formatRuntime(45)).toBe('0h 45m');
    });

    it('handles zero', () => {
      expect(formatRuntime(0)).toBe('0h 0m');
    });

    it('handles large runtimes', () => {
      expect(formatRuntime(1000)).toBe('16h 40m');
    });

    it('handles undefined', () => {
      expect(formatRuntime(undefined)).toBe('0h 0m');
    });
  });

  describe('calculateRating', () => {
    it('calculates average rating from reviews', () => {
      const reviews = [{ rating: 5 }, { rating: 4 }, { rating: 3 }];
      expect(calculateRating(reviews)).toBe(4);
    });

    it('returns 0 for empty reviews', () => {
      expect(calculateRating([])).toBe(0);
    });

    it('rounds to one decimal place', () => {
      const reviews = [{ rating: 5 }, { rating: 4 }, { rating: 4 }];
      expect(calculateRating(reviews)).toBe(4.3);
    });
  });
});
