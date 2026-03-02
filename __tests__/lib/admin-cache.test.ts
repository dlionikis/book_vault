import { getCached, setCache, clearCache, CACHE_5M, CACHE_1H, CACHE_24H } from '@/lib/admin-cache';

describe('admin-cache', () => {
  beforeEach(() => {
    clearCache();
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('returns null for a cache miss', () => {
    expect(getCached('nonexistent')).toBeNull();
  });

  it('stores and retrieves cached data', () => {
    const data = { foo: 'bar' };
    setCache('test-key', data, CACHE_1H);
    expect(getCached('test-key')).toEqual(data);
  });

  it('returns null for expired entries', () => {
    setCache('expiring', { value: 1 }, CACHE_5M);
    expect(getCached('expiring')).toEqual({ value: 1 });

    // Advance time past the TTL
    jest.advanceTimersByTime(CACHE_5M + 1);
    expect(getCached('expiring')).toBeNull();
  });

  it('overwrites existing entries', () => {
    setCache('key', 'first', CACHE_1H);
    setCache('key', 'second', CACHE_1H);
    expect(getCached('key')).toBe('second');
  });

  it('exports correct TTL constants', () => {
    expect(CACHE_5M).toBe(5 * 60 * 1000);
    expect(CACHE_1H).toBe(60 * 60 * 1000);
    expect(CACHE_24H).toBe(24 * 60 * 60 * 1000);
  });

  it('evicts oldest entry when cache exceeds max size', () => {
    // Fill cache to max (50 entries)
    for (let i = 0; i < 50; i++) {
      setCache(`key-${i}`, i, CACHE_1H);
    }

    // Adding one more should evict the first entry
    setCache('key-50', 50, CACHE_1H);
    expect(getCached('key-0')).toBeNull();
    expect(getCached('key-50')).toBe(50);
  });

  it('clears all entries with clearCache', () => {
    setCache('a', 1, CACHE_1H);
    setCache('b', 2, CACHE_1H);
    clearCache();
    expect(getCached('a')).toBeNull();
    expect(getCached('b')).toBeNull();
  });
});
