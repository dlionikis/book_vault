/**
 * SDK-level tests for the restore poller (aws-sdk-client-mock).
 *
 * Pins the Intelligent-Tiering completion semantics: ArchiveStatus ABSENT means
 * the restore finished (IT never produces an expiry-date), and a request stuck
 * past 24h is marked failed.
 */

import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';
import { mockClient } from 'aws-sdk-client-mock';

jest.mock('@/lib/s3', () => {
  const actual = jest.requireActual('@/lib/s3');
  return { ...actual, getS3Bucket: () => 'test-bucket', isS3Enabled: () => true };
});

jest.mock('@/lib/db', () => ({
  prisma: {
    mediaRestoreRequest: { findMany: jest.fn(), update: jest.fn() },
    book: { update: jest.fn() },
    $transaction: jest.fn(async (ops: unknown[]) => Promise.all(ops as Promise<unknown>[])),
  },
}));

import { pollRestoreStatus } from '@/lib/poll-restore-status';
import { prisma } from '@/lib/db';

const s3Mock = mockClient(S3Client);

const makeRestore = (over: Record<string, unknown> = {}) => ({
  id: 'req-1',
  bookId: 'book-1',
  s3Key: 'Book/audio.m4b',
  status: 'in_progress',
  requestedAt: new Date(), // recent
  requestedByUserId: 'user-1',
  book: { id: 'book-1', title: 'Test Book' },
  ...over,
});

beforeEach(() => {
  jest.clearAllMocks();
  s3Mock.reset();
  (prisma.mediaRestoreRequest.update as jest.Mock).mockResolvedValue({});
  (prisma.book.update as jest.Mock).mockResolvedValue({});
});

describe('pollRestoreStatus', () => {
  it('marks completed + book AVAILABLE when ArchiveStatus is absent', async () => {
    (prisma.mediaRestoreRequest.findMany as jest.Mock).mockResolvedValue([makeRestore()]);
    s3Mock.on(HeadObjectCommand).resolves({ ContentLength: 123 }); // no ArchiveStatus

    const result = await pollRestoreStatus();

    expect(result.completed).toBe(1);
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.mediaRestoreRequest.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'req-1' },
        data: expect.objectContaining({ status: 'completed' }),
      })
    );
    expect(prisma.book.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ audioAvailability: 'AVAILABLE' }) })
    );
  });

  it('leaves in_progress and bumps lastCheckedAt while ArchiveStatus is present', async () => {
    (prisma.mediaRestoreRequest.findMany as jest.Mock).mockResolvedValue([makeRestore()]);
    s3Mock.on(HeadObjectCommand).resolves({
      ArchiveStatus: 'ARCHIVE_ACCESS',
      Restore: 'ongoing-request="true"',
    });

    const result = await pollRestoreStatus();

    expect(result.stillRestoring).toBe(1);
    expect(result.completed).toBe(0);
    expect(prisma.mediaRestoreRequest.update).toHaveBeenCalledWith({
      where: { id: 'req-1' },
      data: { lastCheckedAt: expect.any(Date) },
    });
    expect(prisma.book.update).not.toHaveBeenCalled();
  });

  it('marks failed (and book back to ARCHIVED) after 24h without completion', async () => {
    const old = new Date(Date.now() - 25 * 3600_000);
    (prisma.mediaRestoreRequest.findMany as jest.Mock).mockResolvedValue([
      makeRestore({ requestedAt: old }),
    ]);
    s3Mock.on(HeadObjectCommand).resolves({ ArchiveStatus: 'ARCHIVE_ACCESS' });

    const result = await pollRestoreStatus();

    expect(result.failed).toBe(1);
    expect(prisma.mediaRestoreRequest.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: 'failed' }),
      })
    );
    expect(prisma.book.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ audioAvailability: 'ARCHIVED' }) })
    );
  });

  it('does not throw when the notification module is absent (Phase 6 not wired)', async () => {
    // The dynamic import of ./notification-service fails → guarded no-op.
    (prisma.mediaRestoreRequest.findMany as jest.Mock).mockResolvedValue([makeRestore()]);
    s3Mock.on(HeadObjectCommand).resolves({ ContentLength: 1 });

    await expect(pollRestoreStatus()).resolves.toMatchObject({ completed: 1 });
  });

  it('counts a HeadObject error without aborting the loop', async () => {
    (prisma.mediaRestoreRequest.findMany as jest.Mock).mockResolvedValue([
      makeRestore({ id: 'a' }),
      makeRestore({ id: 'b' }),
    ]);
    s3Mock.on(HeadObjectCommand).rejectsOnce(new Error('boom')).resolves({ ContentLength: 1 });

    const result = await pollRestoreStatus();

    expect(result.checked).toBe(2);
    expect(result.errors).toBe(1);
    expect(result.completed).toBe(1);
  });
});
