import { formatRuntime } from '@/lib/utils/formatRuntime';
import { formatTime } from '@/lib/utils/formatTime';
import { calculateRating } from '@/lib/utils/ratings';

describe('Utility Functions', () => {
  describe('formatTime', () => {
    it('formats sub-hour durations as M:SS', () => {
      expect(formatTime(125)).toBe('2:05');
    });

    it('formats hour-plus durations as H:MM:SS', () => {
      expect(formatTime(3725)).toBe('1:02:05');
    });

    it('pads to H:MM:SS with forceHours (player timestamps)', () => {
      expect(formatTime(125, { forceHours: true })).toBe('0:02:05');
    });

    it('handles zero and non-finite input', () => {
      expect(formatTime(0)).toBe('0:00');
      expect(formatTime(NaN, { forceHours: true })).toBe('0:00:00');
      expect(formatTime(Infinity)).toBe('0:00');
    });
  });

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

    it('returns null for zero (callers render nothing)', () => {
      expect(formatRuntime(0)).toBeNull();
    });

    it('handles large runtimes', () => {
      expect(formatRuntime(1000)).toBe('16h 40m');
    });

    it('returns null for undefined', () => {
      expect(formatRuntime(undefined)).toBeNull();
    });

    it('returns null for null', () => {
      expect(formatRuntime(null)).toBeNull();
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
