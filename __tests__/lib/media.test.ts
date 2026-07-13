/**
 * Tests for media path utilities
 *
 * validateMediaPath is a security guard: it must reject paths outside the
 * media directory, including sibling directories that share a name prefix.
 */

import path from 'path';
import { validateMediaPath, getLocalMediaUrl, getLocalAudioUrl } from '@/lib/media';

describe('validateMediaPath', () => {
  const originalMediaPath = process.env.MEDIA_DATA_PATH;
  const mediaDir = path.join('/private/tmp', 'bv-media-test');

  beforeAll(() => {
    process.env.MEDIA_DATA_PATH = mediaDir;
  });

  afterAll(() => {
    if (originalMediaPath === undefined) {
      delete process.env.MEDIA_DATA_PATH;
    } else {
      process.env.MEDIA_DATA_PATH = originalMediaPath;
    }
  });

  it('accepts paths inside the media directory', () => {
    expect(validateMediaPath(path.join(mediaDir, 'Book [ASIN]', 'cover.jpg'))).toBe(true);
  });

  it('accepts the media directory itself', () => {
    expect(validateMediaPath(mediaDir)).toBe(true);
  });

  it('rejects sibling directories sharing a name prefix', () => {
    expect(validateMediaPath(`${mediaDir}-evil/cover.jpg`)).toBe(false);
  });

  it('rejects path traversal escaping the media directory', () => {
    expect(validateMediaPath(path.join(mediaDir, '..', 'outside.jpg'))).toBe(false);
  });

  it('rejects unrelated absolute paths', () => {
    expect(validateMediaPath('/etc/passwd')).toBe(false);
  });
});

describe('local media URL helpers', () => {
  it('returns null for null paths', () => {
    expect(getLocalMediaUrl(null)).toBeNull();
    expect(getLocalAudioUrl(null)).toBeNull();
  });

  it('URL-encodes path segments while preserving separators', () => {
    const url = getLocalAudioUrl('Book Title [ASIN]/file #1.m4b');
    expect(url).toContain('/api/audio/');
    expect(url).toContain('Book%20Title%20%5BASIN%5D/file%20%231.m4b');
  });
});
