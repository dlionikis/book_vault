interface CacheEntry<T> {
  data: T;
  expiresAt: number;
}

const MAX_CACHE_SIZE = 50;
const cache = new Map<string, CacheEntry<unknown>>();

export const CACHE_1M = 60 * 1000;
export const CACHE_5M = 5 * 60 * 1000;
export const CACHE_1H = 60 * 60 * 1000;
export const CACHE_24H = 24 * 60 * 60 * 1000;

function evictExpired(): void {
  const now = Date.now();
  for (const [key, entry] of cache) {
    if (now > entry.expiresAt) cache.delete(key);
  }
}

export function getCached<T>(key: string): T | null {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    cache.delete(key);
    return null;
  }
  return entry.data as T;
}

export function setCache<T>(key: string, data: T, ttlMs: number): void {
  if (cache.size >= MAX_CACHE_SIZE) {
    evictExpired();
  }
  // If still at max after eviction, delete the oldest entry
  if (cache.size >= MAX_CACHE_SIZE) {
    const firstKey = cache.keys().next().value;
    if (firstKey !== undefined) cache.delete(firstKey);
  }
  cache.set(key, { data, expiresAt: Date.now() + ttlMs });
}

export function clearCache(): void {
  cache.clear();
}
