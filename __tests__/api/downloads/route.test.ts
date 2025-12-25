/**
 * Tests for download endpoints
 * Phase 7: Offline download support
 */

import { NextRequest } from 'next/server';
import { GET as getDownloadHistory } from '@/app/api/downloads/route';
import { POST as generateDownloadUrl } from '@/app/api/downloads/[bookId]/route';
import { GET as checkEligibility } from '@/app/api/downloads/[bookId]/check/route';
import { prisma } from '@/lib/db';
import * as auth from '@/lib/auth';
import * as s3 from '@/lib/s3';
import * as rateLimit from '@/lib/rate-limit';

// Mock dependencies
jest.mock('@/lib/auth');
jest.mock('@/lib/s3');
jest.mock('@/lib/rate-limit');

const mockGetAuthUserFromRequest = auth.getAuthUserFromRequest as jest.MockedFunction<
  typeof auth.getAuthUserFromRequest
>;
const mockIsS3Enabled = s3.isS3Enabled as jest.MockedFunction<typeof s3.isS3Enabled>;
const mockGeneratePresignedUrl = s3.generatePresignedUrl as jest.MockedFunction<
  typeof s3.generatePresignedUrl
>;
const mockGetS3ObjectMetadata = s3.getS3ObjectMetadata as jest.MockedFunction<
  typeof s3.getS3ObjectMetadata
>;
const mockCheckDownloadLimit = rateLimit.checkDownloadLimit as jest.MockedFunction<
  typeof rateLimit.checkDownloadLimit
>;

describe('Download Endpoints', () => {
  const mockUser = {
    id: 'user-123',
    email: 'test@example.com',
  };

  const mockBook = {
    id: 'book-123',
    asin: 'B001234567',
    title: 'Test Book',
    audioUrl: 'books/test-book/audio.mp3',
  };

  // Clean up leftover test data once before all tests
  beforeAll(async () => {
    await prisma.userDownload.deleteMany({
      where: {
        user: {
          email: {
            in: [
              'test-downloads@example.com',
              'test-limit@example.com',
              'test-download@example.com',
              'test-ratelimit@example.com',
              'test-under-limit@example.com',
              'test-reset@example.com',
            ],
          },
        },
      },
    });

    await prisma.user.deleteMany({
      where: {
        email: {
          in: [
            'test-downloads@example.com',
            'test-limit@example.com',
            'test-download@example.com',
            'test-ratelimit@example.com',
            'test-under-limit@example.com',
            'test-reset@example.com',
          ],
        },
      },
    });

    await prisma.book.deleteMany({
      where: {
        asin: {
          in: [
            'B001234567',
            'B999999999',
            'B111111111',
            'B222222222',
            'B333333333',
            'B444444444',
            'B555555555',
            'B666666666',
            'B777777777',
            'B888888888',
          ],
        },
      },
    });
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /api/downloads (download history)', () => {
    it('should return download history with daily count', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

      // Create test book and downloads
      const book = await prisma.book.create({
        data: {
          asin: 'B001234567',
          title: 'Test Book',
          audioUrl: 'test.mp3',
        },
      });

      const user = await prisma.user.create({
        data: {
          email: 'test-downloads@example.com',
          passwordHash: 'hash',
        },
      });

      await prisma.userDownload.create({
        data: {
          userId: user.id,
          bookId: book.id,
          deviceId: 'device-1',
        },
      });

      const request = new NextRequest('http://localhost:3000/api/downloads');
      mockGetAuthUserFromRequest.mockResolvedValue({ id: user.id, email: user.email });

      const response = await getDownloadHistory(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.downloads).toHaveLength(1);
      expect(data.downloads[0].bookTitle).toBe('Test Book');
      expect(data.downloads[0].deviceId).toBe('device-1');
      expect(data.dailyCount).toBe(1);

      // Cleanup
      await prisma.userDownload.deleteMany({ where: { userId: user.id } });
      await prisma.book.delete({ where: { id: book.id } });
      await prisma.user.delete({ where: { id: user.id } });
    });

    it('should return 401 if user not authenticated', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const request = new NextRequest('http://localhost:3000/api/downloads');
      const response = await getDownloadHistory(request);

      expect(response.status).toBe(401);
    });

    it('should limit history to 50 downloads', async () => {
      const user = await prisma.user.create({
        data: {
          email: 'test-limit@example.com',
          passwordHash: 'hash',
        },
      });

      const book = await prisma.book.create({
        data: {
          asin: 'B999999999',
          title: 'Limit Test Book',
          audioUrl: 'test.mp3',
        },
      });

      // Create 60 downloads
      for (let i = 0; i < 60; i++) {
        await prisma.userDownload.create({
          data: {
            userId: user.id,
            bookId: book.id,
          },
        });
      }

      const request = new NextRequest('http://localhost:3000/api/downloads');
      mockGetAuthUserFromRequest.mockResolvedValue({ id: user.id, email: user.email });

      const response = await getDownloadHistory(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.downloads.length).toBeLessThanOrEqual(50);

      // Cleanup
      await prisma.userDownload.deleteMany({ where: { userId: user.id } });
      await prisma.book.delete({ where: { id: book.id } });
      await prisma.user.delete({ where: { id: user.id } });
    });
  });

  describe('GET /api/downloads/[bookId]/check (eligibility)', () => {
    it('should return eligible: true for valid book', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

      const book = await prisma.book.create({
        data: {
          asin: 'B111111111',
          title: 'Eligibility Test Book',
        },
      });

      const request = new NextRequest(
        `http://localhost:3000/api/downloads/${book.id}/check`
      );

      const response = await checkEligibility(request, { params: { bookId: book.id } });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.eligible).toBe(true);

      // Cleanup
      await prisma.book.delete({ where: { id: book.id } });
    });

    it('should return 404 for non-existent book', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);

      const request = new NextRequest('http://localhost:3000/api/downloads/fake-id/check');

      const response = await checkEligibility(request, { params: { bookId: 'fake-id' } });

      expect(response.status).toBe(404);
    });

    it('should return 401 if user not authenticated', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(null);

      const request = new NextRequest('http://localhost:3000/api/downloads/book-id/check');

      const response = await checkEligibility(request, { params: { bookId: 'book-id' } });

      expect(response.status).toBe(401);
    });
  });

  describe('POST /api/downloads/[bookId] (generate URL)', () => {
    it('should generate pre-signed URL for valid book', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);
      mockIsS3Enabled.mockReturnValue(true);
      mockCheckDownloadLimit.mockResolvedValue(true);
      mockGeneratePresignedUrl.mockResolvedValue(
        'https://s3.amazonaws.com/bucket/test.mp3?signature=abc'
      );
      mockGetS3ObjectMetadata.mockResolvedValue({
        size: 125829120,
        contentType: 'audio/mpeg',
      });

      const book = await prisma.book.create({
        data: {
          asin: 'B222222222',
          title: 'Download Test Book',
          audioUrl: 'books/test/audio.mp3',
        },
      });

      const user = await prisma.user.create({
        data: {
          email: 'test-download@example.com',
          passwordHash: 'hash',
        },
      });

      const request = new NextRequest(`http://localhost:3000/api/downloads/${book.id}`, {
        method: 'POST',
        body: JSON.stringify({ deviceId: 'device-123' }),
      });

      mockGetAuthUserFromRequest.mockResolvedValue({ id: user.id, email: user.email });

      const response = await generateDownloadUrl(request, { params: { bookId: book.id } });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.downloadUrl).toContain('s3.amazonaws.com');
      expect(data.expiresAt).toBeDefined();
      expect(data.fileSize).toBe(125829120);

      // Verify download was tracked
      const download = await prisma.userDownload.findFirst({
        where: { userId: user.id, bookId: book.id },
      });
      expect(download).toBeTruthy();
      expect(download?.deviceId).toBe('device-123');

      // Cleanup
      await prisma.userDownload.deleteMany({ where: { userId: user.id } });
      await prisma.book.delete({ where: { id: book.id } });
      await prisma.user.delete({ where: { id: user.id } });
    });

    it('should return 429 when download limit exceeded', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);
      mockIsS3Enabled.mockReturnValue(true);
      mockCheckDownloadLimit.mockResolvedValue(false); // Limit exceeded

      const book = await prisma.book.create({
        data: {
          asin: 'B333333333',
          title: 'Limit Test Book',
          audioUrl: 'test.mp3',
        },
      });

      const request = new NextRequest(`http://localhost:3000/api/downloads/${book.id}`, {
        method: 'POST',
        body: JSON.stringify({}),
      });

      const response = await generateDownloadUrl(request, { params: { bookId: book.id } });
      const data = await response.json();

      expect(response.status).toBe(429);
      expect(data.error).toContain('Download limit exceeded');

      // Cleanup
      await prisma.book.delete({ where: { id: book.id } });
    });

    it('should return 501 if S3 not enabled', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);
      mockIsS3Enabled.mockReturnValue(false); // S3 disabled
      mockCheckDownloadLimit.mockResolvedValue(true);

      const book = await prisma.book.create({
        data: {
          asin: 'B444444444',
          title: 'S3 Test Book',
          audioUrl: 'test.mp3',
        },
      });

      const request = new NextRequest(`http://localhost:3000/api/downloads/${book.id}`, {
        method: 'POST',
        body: JSON.stringify({}),
      });

      const response = await generateDownloadUrl(request, { params: { bookId: book.id } });
      const data = await response.json();

      expect(response.status).toBe(501);
      expect(data.error).toContain('S3 configuration');

      // Cleanup
      await prisma.book.delete({ where: { id: book.id } });
    });

    it('should return 404 for book without audio file', async () => {
      mockGetAuthUserFromRequest.mockResolvedValue(mockUser);
      mockIsS3Enabled.mockReturnValue(true);
      mockCheckDownloadLimit.mockResolvedValue(true);

      const book = await prisma.book.create({
        data: {
          asin: 'B555555555',
          title: 'No Audio Book',
          audioUrl: null,
        },
      });

      const request = new NextRequest(`http://localhost:3000/api/downloads/${book.id}`, {
        method: 'POST',
        body: JSON.stringify({}),
      });

      const response = await generateDownloadUrl(request, { params: { bookId: book.id } });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('no audio file');

      // Cleanup
      await prisma.book.delete({ where: { id: book.id } });
    });
  });

  describe('Rate Limiting', () => {
    it('should enforce 10 downloads per day limit', async () => {
      // Use the real checkDownloadLimit implementation (unmock the module)
      jest.unmock('@/lib/rate-limit');
      // Clear the module cache and re-import to get the real implementation
      jest.resetModules();
      const { checkDownloadLimit } = await import('@/lib/rate-limit');

      const user = await prisma.user.create({
        data: {
          email: 'test-ratelimit@example.com',
          passwordHash: 'hash',
        },
      });

      const book = await prisma.book.create({
        data: {
          asin: 'B666666666',
          title: 'Rate Limit Book',
          audioUrl: 'test.mp3',
        },
      });

      // Create 10 downloads in last 24 hours
      for (let i = 0; i < 10; i++) {
        await prisma.userDownload.create({
          data: {
            userId: user.id,
            bookId: book.id,
          },
        });
      }

      // Verify actual rate limit check
      const isAllowed = await checkDownloadLimit(user.id);

      expect(isAllowed).toBe(false);

      // Cleanup
      await prisma.userDownload.deleteMany({ where: { userId: user.id } });
      await prisma.book.delete({ where: { id: book.id } });
      await prisma.user.delete({ where: { id: user.id } });
    });

    it('should allow downloads when under limit', async () => {
      // Use the real checkDownloadLimit implementation
      jest.unmock('@/lib/rate-limit');
      jest.resetModules();
      const { checkDownloadLimit } = await import('@/lib/rate-limit');

      const user = await prisma.user.create({
        data: {
          email: 'test-under-limit@example.com',
          passwordHash: 'hash',
        },
      });

      const book = await prisma.book.create({
        data: {
          asin: 'B777777777',
          title: 'Under Limit Book',
          audioUrl: 'test.mp3',
        },
      });

      // Create only 5 downloads
      for (let i = 0; i < 5; i++) {
        await prisma.userDownload.create({
          data: {
            userId: user.id,
            bookId: book.id,
          },
        });
      }

      const isAllowed = await checkDownloadLimit(user.id);

      expect(isAllowed).toBe(true);

      // Cleanup
      await prisma.userDownload.deleteMany({ where: { userId: user.id } });
      await prisma.book.delete({ where: { id: book.id } });
      await prisma.user.delete({ where: { id: user.id } });
    });

    it('should reset after 24 hours', async () => {
      // Use the real checkDownloadLimit implementation
      jest.unmock('@/lib/rate-limit');
      jest.resetModules();
      const { checkDownloadLimit } = await import('@/lib/rate-limit');

      const user = await prisma.user.create({
        data: {
          email: 'test-reset@example.com',
          passwordHash: 'hash',
        },
      });

      const book = await prisma.book.create({
        data: {
          asin: 'B888888888',
          title: 'Reset Book',
          audioUrl: 'test.mp3',
        },
      });

      // Create 10 downloads from 25 hours ago
      const twentyFiveHoursAgo = new Date(Date.now() - 25 * 60 * 60 * 1000);
      for (let i = 0; i < 10; i++) {
        await prisma.userDownload.create({
          data: {
            userId: user.id,
            bookId: book.id,
            downloadedAt: twentyFiveHoursAgo,
          },
        });
      }

      const isAllowed = await checkDownloadLimit(user.id);

      expect(isAllowed).toBe(true); // Old downloads don't count

      // Cleanup
      await prisma.userDownload.deleteMany({ where: { userId: user.id } });
      await prisma.book.delete({ where: { id: book.id } });
      await prisma.user.delete({ where: { id: user.id } });
    });
  });
});
