/**
 * Tests for the audio streaming endpoint.
 *
 * Core media surface: this is the range-request path iOS seeking depends on,
 * so both the S3 (production) and local-filesystem (dev) branches are covered,
 * including partial-content (206) and range-not-satisfiable (416).
 *
 * Auth is exercised through the requireUser seam (the route calls it directly).
 */

import { Readable } from 'stream';
import { GET } from '@/app/api/audio/[...path]/route';
import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { isS3Enabled, streamS3ObjectWithRange, getS3ObjectMetadata } from '@/lib/s3';
import { validateMediaPath } from '@/lib/media';
import * as fs from 'fs';

// Factory (not auto-mock): the real module transitively imports lib/db →
// Prisma, which can't initialize in the test env. A stub avoids loading it.
jest.mock('@/lib/api-auth', () => ({ requireUser: jest.fn() }));
jest.mock('@/lib/s3', () => ({
  isS3Enabled: jest.fn(),
  streamS3ObjectWithRange: jest.fn(),
  getS3ObjectMetadata: jest.fn(),
}));
jest.mock('@/lib/media', () => ({
  getAbsoluteMediaPath: jest.fn(() => '/media'),
  validateMediaPath: jest.fn(() => true),
}));
jest.mock('fs', () => ({
  statSync: jest.fn(),
  createReadStream: jest.fn(),
}));

const mockRequireUser = requireUser as jest.MockedFunction<typeof requireUser>;
const mockIsS3Enabled = isS3Enabled as jest.MockedFunction<typeof isS3Enabled>;
const mockStreamRange = streamS3ObjectWithRange as jest.MockedFunction<
  typeof streamS3ObjectWithRange
>;
const mockGetMetadata = getS3ObjectMetadata as jest.MockedFunction<typeof getS3ObjectMetadata>;
const mockValidatePath = validateMediaPath as jest.MockedFunction<typeof validateMediaPath>;
const mockStatSync = fs.statSync as jest.MockedFunction<typeof fs.statSync>;
const mockCreateReadStream = fs.createReadStream as jest.MockedFunction<typeof fs.createReadStream>;

const PATH = ['Book Title [ASIN]', 'audio.m4b'];

function makeRequest(range?: string): NextRequest {
  const headers: Record<string, string> = {};
  if (range) headers.range = range;
  return new NextRequest('http://localhost:3000/api/audio/x', { headers });
}

function authOk() {
  mockRequireUser.mockResolvedValue({ user: { id: 'user-123', username: 'testuser' } });
}

describe('GET /api/audio/[...path]', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockValidatePath.mockReturnValue(true);
  });

  // MARK: - Auth

  it('returns 401 when unauthenticated', async () => {
    mockRequireUser.mockResolvedValue({
      error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }),
    });

    const res = await GET(makeRequest(), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(401);
    expect(mockIsS3Enabled).not.toHaveBeenCalled();
  });

  it('allows session-authenticated users (local branch full stream)', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(false);
    mockStatSync.mockReturnValue({ size: 5000 } as fs.Stats);
    mockCreateReadStream.mockReturnValue(Readable.from(['data']) as any);

    const res = await GET(makeRequest(), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(200);
    expect(res.headers.get('Accept-Ranges')).toBe('bytes');
  });

  // MARK: - S3 branch (production)

  it('S3: streams full file (200) when no range requested', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(true);
    mockGetMetadata.mockResolvedValue({ size: 5000, contentType: 'audio/mp4' });
    mockStreamRange.mockResolvedValue({
      stream: Readable.from(['x']) as any,
      contentType: 'audio/mp4',
      contentLength: 5000,
      totalSize: 5000,
    });

    const res = await GET(makeRequest(), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('audio/mp4');
    expect(res.headers.get('Content-Length')).toBe('5000');
    expect(mockGetMetadata).toHaveBeenCalled();
  });

  it('S3: valid range returns 206 with Content-Range', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(true);
    mockGetMetadata.mockResolvedValue({ size: 5000, contentType: 'audio/mp4' });
    mockStreamRange.mockResolvedValue({
      stream: Readable.from(['x']) as any,
      contentType: 'audio/mp4',
      contentLength: 1024,
      totalSize: 5000,
    });

    const res = await GET(makeRequest('bytes=0-1023'), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(206);
    expect(res.headers.get('Content-Range')).toBe('bytes 0-1023/5000');
    expect(res.headers.get('Accept-Ranges')).toBe('bytes');
    expect(mockStreamRange).toHaveBeenCalledWith(expect.any(String), { start: 0, end: 1023 });
  });

  it('S3: range beyond file size returns 416', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(true);
    mockGetMetadata.mockResolvedValue({ size: 5000, contentType: 'audio/mp4' });

    const res = await GET(makeRequest('bytes=6000-7000'), {
      params: Promise.resolve({ path: PATH }),
    });

    expect(res.status).toBe(416);
    expect(mockStreamRange).not.toHaveBeenCalled();
  });

  it('S3: missing object (NoSuchKey) returns 404', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(true);
    const err: any = new Error('nope');
    err.name = 'NoSuchKey';
    mockGetMetadata.mockRejectedValue(err);

    const res = await GET(makeRequest(), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(404);
  });

  // MARK: - Local branch (development)

  it('local: path traversal returns 403', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(false);
    mockValidatePath.mockReturnValue(false);

    const res = await GET(makeRequest(), {
      params: Promise.resolve({ path: ['..', '..', 'etc', 'passwd'] }),
    });

    expect(res.status).toBe(403);
    expect(mockStatSync).not.toHaveBeenCalled();
  });

  it('local: missing file returns 404', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(false);
    mockStatSync.mockImplementation(() => {
      throw new Error('ENOENT');
    });

    const res = await GET(makeRequest(), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(404);
  });

  it('local: valid range returns 206 and reads the requested byte range', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(false);
    mockStatSync.mockReturnValue({ size: 5000 } as fs.Stats);
    mockCreateReadStream.mockReturnValue(Readable.from(['chunk']) as any);

    const res = await GET(makeRequest('bytes=100-199'), {
      params: Promise.resolve({ path: PATH }),
    });

    expect(res.status).toBe(206);
    expect(res.headers.get('Content-Range')).toBe('bytes 100-199/5000');
    expect(res.headers.get('Content-Length')).toBe('100');
    expect(mockCreateReadStream).toHaveBeenCalledWith(expect.any(String), { start: 100, end: 199 });
  });

  it('local: range beyond file size returns 416', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(false);
    mockStatSync.mockReturnValue({ size: 5000 } as fs.Stats);

    const res = await GET(makeRequest('bytes=9000-9999'), {
      params: Promise.resolve({ path: PATH }),
    });

    expect(res.status).toBe(416);
    expect(mockCreateReadStream).not.toHaveBeenCalled();
  });

  it('local: open-ended range defaults end to last byte (206)', async () => {
    authOk();
    mockIsS3Enabled.mockReturnValue(false);
    mockStatSync.mockReturnValue({ size: 5000 } as fs.Stats);
    mockCreateReadStream.mockReturnValue(Readable.from(['chunk']) as any);

    const res = await GET(makeRequest('bytes=4000-'), { params: Promise.resolve({ path: PATH }) });

    expect(res.status).toBe(206);
    expect(res.headers.get('Content-Range')).toBe('bytes 4000-4999/5000');
    expect(mockCreateReadStream).toHaveBeenCalledWith(expect.any(String), {
      start: 4000,
      end: 4999,
    });
  });
});
