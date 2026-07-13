/**
 * Tests for the images streaming endpoint
 *
 * Security-critical: this route must require authentication and must only
 * serve image content (without the extension allowlist it could stream any
 * object in the media store, including audio files).
 *
 * Fixtures are self-contained: test-data/ is gitignored so CI has none of the
 * local media files. The route reads raw bytes and derives the content type
 * from the extension, so a minimal JPEG header written to a temp dir suffices.
 */

import fs from 'fs';
import os from 'os';
import path from 'path';
import { GET } from '@/app/api/images/[...path]/route';
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';

// Mock dependencies
jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/s3', () => ({
  isS3Enabled: jest.fn(() => false),
  streamS3Object: jest.fn(),
}));

const mockGetServerSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockGetAuthUserFromRequest = getAuthUserFromRequest as jest.MockedFunction<
  typeof getAuthUserFromRequest
>;

const mockUser = { id: 'user-123', username: 'testuser' };

const JPEG_BYTES = Buffer.from('ffd8ffe000104a46494600010100000100010000ffd9', 'hex');
const BOOK_DIR = 'Test Book [FIXTURE]';
const FIXTURE_PATH = [BOOK_DIR, 'cover.jpg'];

function makeRequest(): NextRequest {
  return new NextRequest('http://localhost:3000/api/images/test');
}

describe('GET /api/images/[...path]', () => {
  const originalMediaPath = process.env.MEDIA_DATA_PATH;
  let mediaDir: string;

  beforeAll(() => {
    mediaDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bv-images-test-'));
    fs.mkdirSync(path.join(mediaDir, BOOK_DIR));
    fs.writeFileSync(path.join(mediaDir, BOOK_DIR, 'cover.jpg'), JPEG_BYTES);
    process.env.MEDIA_DATA_PATH = mediaDir;
  });

  afterAll(() => {
    if (originalMediaPath === undefined) {
      delete process.env.MEDIA_DATA_PATH;
    } else {
      process.env.MEDIA_DATA_PATH = originalMediaPath;
    }
    fs.rmSync(mediaDir, { recursive: true, force: true });
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetServerSession.mockResolvedValue(null);
    mockGetAuthUserFromRequest.mockResolvedValue(null);
  });

  it('returns 401 for unauthenticated requests', async () => {
    const response = await GET(makeRequest(), { params: { path: FIXTURE_PATH } });

    expect(response.status).toBe(401);
    const data = await response.json();
    expect(data.error).toBeDefined();
  });

  it('returns 200 with image content for authenticated requests (bearer)', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

    const response = await GET(makeRequest(), { params: { path: FIXTURE_PATH } });

    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('image/jpeg');
  });

  it('returns 200 for authenticated requests (web session)', async () => {
    mockGetServerSession.mockResolvedValue({ user: mockUser } as any);

    const response = await GET(makeRequest(), { params: { path: FIXTURE_PATH } });

    expect(response.status).toBe(200);
  });

  it('uses private caching so shared caches never store gated content', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

    const response = await GET(makeRequest(), { params: { path: FIXTURE_PATH } });

    expect(response.headers.get('Cache-Control')).toContain('private');
    expect(response.headers.get('Cache-Control')).not.toContain('public');
  });

  it('returns 404 for non-image extensions even when authenticated (audio exfiltration guard)', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

    const response = await GET(makeRequest(), {
      params: { path: [BOOK_DIR, 'audiobook.m4b'] },
    });

    expect(response.status).toBe(404);
  });

  it('returns 403 for path traversal attempts', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

    const response = await GET(makeRequest(), {
      params: { path: ['..', '..', 'etc', 'secrets.jpg'] },
    });

    expect(response.status).toBe(403);
  });

  it('returns 404 for missing files with a valid image extension', async () => {
    mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

    const response = await GET(makeRequest(), {
      params: { path: ['Nonexistent Book', 'cover.jpg'] },
    });

    expect(response.status).toBe(404);
  });
});
