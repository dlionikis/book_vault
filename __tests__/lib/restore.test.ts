/**
 * SDK-level tests for lib/restore.ts using aws-sdk-client-mock.
 *
 * These pin the verified Intelligent-Tiering semantics that the whole restore
 * workflow depends on — most importantly that RestoreObject is sent WITHOUT a
 * `Days` element (IT restores reject it) and that restore initiation is
 * idempotent (DB dedup + RestoreAlreadyInProgress swallowing).
 */

import { S3Client, HeadObjectCommand, RestoreObjectCommand } from '@aws-sdk/client-s3';
import { mockClient } from 'aws-sdk-client-mock';
import { prisma } from '@/lib/db';

// Keep the real S3 client (aws-sdk-client-mock stubs its prototype), but pin
// the bucket: lib/s3 reads AWS_S3_BUCKET at module load, which is unset in
// tests.
jest.mock('@/lib/s3', () => {
  const actual = jest.requireActual('@/lib/s3');
  return { ...actual, getS3Bucket: () => 'test-bucket' };
});

jest.mock('@/lib/db', () => ({
  prisma: {
    mediaRestoreRequest: {
      findFirst: jest.fn(),
      create: jest.fn(),
    },
    book: {
      update: jest.fn(),
    },
    $transaction: jest.fn(async (ops: unknown[]) => Promise.all(ops as Promise<unknown>[])),
  },
}));

import {
  initiateRestore,
  getArchiveState,
  parseRestoreHeader,
  estimatedCompletion,
  RESTORE_ETA_HOURS,
} from '@/lib/restore';

const s3Mock = mockClient(S3Client);

const BOOK = { id: 'book-1', audioUrl: 'Book Title [ASIN]/audio.m4b' };

describe('parseRestoreHeader', () => {
  it('returns null when the header is absent', () => {
    expect(parseRestoreHeader(undefined)).toBeNull();
  });

  it('detects an ongoing restore', () => {
    expect(parseRestoreHeader('ongoing-request="true"')).toEqual({ ongoingRequest: true });
  });

  it('treats any other value as not ongoing', () => {
    // IT restores never produce expiry-date, but be liberal in what we accept.
    expect(parseRestoreHeader('ongoing-request="false"')).toEqual({ ongoingRequest: false });
  });
});

describe('estimatedCompletion', () => {
  it('is requestedAt + the standard-tier upper bound', () => {
    const requestedAt = new Date('2026-07-19T12:00:00.000Z');
    expect(estimatedCompletion(requestedAt)).toBe('2026-07-19T17:00:00.000Z');
    expect(RESTORE_ETA_HOURS).toBe(5);
  });
});

describe('getArchiveState', () => {
  beforeEach(() => {
    s3Mock.reset();
  });

  it('reports archived when HeadObject has ArchiveStatus', async () => {
    s3Mock.on(HeadObjectCommand).resolves({ ArchiveStatus: 'ARCHIVE_ACCESS' });

    await expect(getArchiveState(BOOK.audioUrl)).resolves.toEqual({
      archived: true,
      restoreOngoing: false,
    });
  });

  it('reports an in-flight restore from the x-amz-restore header', async () => {
    s3Mock.on(HeadObjectCommand).resolves({
      ArchiveStatus: 'ARCHIVE_ACCESS',
      Restore: 'ongoing-request="true"',
    });

    await expect(getArchiveState(BOOK.audioUrl)).resolves.toEqual({
      archived: true,
      restoreOngoing: true,
    });
  });

  it('reports available when ArchiveStatus is absent (the IT completion signal)', async () => {
    s3Mock.on(HeadObjectCommand).resolves({ ContentLength: 123 });

    await expect(getArchiveState(BOOK.audioUrl)).resolves.toEqual({
      archived: false,
      restoreOngoing: false,
    });
  });
});

describe('initiateRestore', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    s3Mock.reset();
    delete process.env.RESTORE_TIER;
    (prisma.mediaRestoreRequest.findFirst as jest.Mock).mockResolvedValue(null);
    (prisma.mediaRestoreRequest.create as jest.Mock).mockResolvedValue({
      id: 'req-1',
      requestedAt: new Date(),
    });
    (prisma.book.update as jest.Mock).mockResolvedValue({});
  });

  it('sends RestoreObject WITHOUT Days (Intelligent-Tiering rejects it)', async () => {
    s3Mock.on(RestoreObjectCommand).resolves({});

    await initiateRestore(BOOK, 'user-1');

    const calls = s3Mock.commandCalls(RestoreObjectCommand);
    expect(calls).toHaveLength(1);
    const input = calls[0].args[0].input;
    expect(input.Bucket).toBe('test-bucket');
    expect(input.Key).toBe(BOOK.audioUrl);
    expect(input.RestoreRequest).toEqual({ GlacierJobParameters: { Tier: 'Standard' } });
    // The load-bearing assertion: no Days element anywhere.
    expect(input.RestoreRequest).not.toHaveProperty('Days');
  });

  it('dedupes against an existing in_progress request (no S3 call, no new row)', async () => {
    const existing = { id: 'req-existing', requestedAt: new Date(), status: 'in_progress' };
    (prisma.mediaRestoreRequest.findFirst as jest.Mock).mockResolvedValue(existing);

    const result = await initiateRestore(BOOK, 'user-1');

    expect(result).toBe(existing);
    expect(s3Mock.commandCalls(RestoreObjectCommand)).toHaveLength(0);
    expect(prisma.mediaRestoreRequest.create).not.toHaveBeenCalled();
  });

  it('swallows RestoreAlreadyInProgress and still records the request', async () => {
    const err = new Error('restore already in progress');
    err.name = 'RestoreAlreadyInProgress';
    s3Mock.on(RestoreObjectCommand).rejects(err);

    await expect(initiateRestore(BOOK, 'user-1')).resolves.toMatchObject({ id: 'req-1' });
    expect(prisma.mediaRestoreRequest.create).toHaveBeenCalled();
  });

  it('rethrows any other S3 error without recording a request', async () => {
    const err = new Error('access denied');
    err.name = 'AccessDenied';
    s3Mock.on(RestoreObjectCommand).rejects(err);

    await expect(initiateRestore(BOOK, 'user-1')).rejects.toThrow('access denied');
    expect(prisma.mediaRestoreRequest.create).not.toHaveBeenCalled();
  });

  it('records the request and flips the book to RESTORING in one transaction', async () => {
    s3Mock.on(RestoreObjectCommand).resolves({});

    await initiateRestore(BOOK, 'user-1');

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.mediaRestoreRequest.create).toHaveBeenCalledWith({
      data: {
        bookId: BOOK.id,
        s3Key: BOOK.audioUrl,
        status: 'in_progress',
        restoreTier: 'Standard',
        requestedByUserId: 'user-1',
      },
    });
    expect(prisma.book.update).toHaveBeenCalledWith({
      where: { id: BOOK.id },
      data: { audioAvailability: 'RESTORING', availabilityCheckedAt: expect.any(Date) },
    });
  });

  it('honors the RESTORE_TIER=Expedited testing override', async () => {
    process.env.RESTORE_TIER = 'Expedited';
    s3Mock.on(RestoreObjectCommand).resolves({});

    await initiateRestore(BOOK, null);

    const input = s3Mock.commandCalls(RestoreObjectCommand)[0].args[0].input;
    expect(input.RestoreRequest?.GlacierJobParameters?.Tier).toBe('Expedited');
    // System-initiated / test restores may have no user
    expect(prisma.mediaRestoreRequest.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ requestedByUserId: null, restoreTier: 'Expedited' }),
    });
  });
});
