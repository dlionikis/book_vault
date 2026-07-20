/**
 * SDK-level tests for the nightly availability sync (aws-sdk-client-mock).
 * Verifies the HeadObject → availability classification and that only changed
 * rows are counted as changed.
 */

import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';
import { mockClient } from 'aws-sdk-client-mock';

jest.mock('@/lib/s3', () => {
  const actual = jest.requireActual('@/lib/s3');
  return { ...actual, getS3Bucket: () => 'test-bucket', isS3Enabled: () => true };
});

jest.mock('@/lib/db', () => ({
  prisma: {
    book: { findMany: jest.fn(), update: jest.fn() },
  },
}));

import { syncAvailability } from '@/lib/sync-availability';
import { prisma } from '@/lib/db';

const s3Mock = mockClient(S3Client);

beforeEach(() => {
  jest.clearAllMocks();
  s3Mock.reset();
  (prisma.book.update as jest.Mock).mockResolvedValue({});
});

describe('syncAvailability', () => {
  it('classifies available / archived / restoring from HeadObject signals', async () => {
    (prisma.book.findMany as jest.Mock).mockResolvedValue([
      { id: 'avail', audioUrl: 'a.m4b', audioAvailability: 'AVAILABLE' },
      { id: 'arch', audioUrl: 'b.m4b', audioAvailability: 'AVAILABLE' },
      { id: 'rest', audioUrl: 'c.m4b', audioAvailability: 'AVAILABLE' },
    ]);
    s3Mock
      .on(HeadObjectCommand, { Key: 'a.m4b' })
      .resolves({ ContentLength: 1 })
      .on(HeadObjectCommand, { Key: 'b.m4b' })
      .resolves({ ArchiveStatus: 'ARCHIVE_ACCESS' })
      .on(HeadObjectCommand, { Key: 'c.m4b' })
      .resolves({ ArchiveStatus: 'ARCHIVE_ACCESS', Restore: 'ongoing-request="true"' });

    const r = await syncAvailability();

    expect(r).toMatchObject({ checked: 3, available: 1, archived: 1, restoring: 1, errors: 0 });
    // arch + rest changed from AVAILABLE; avail did not.
    expect(r.changed).toBe(2);
  });

  it('touches availabilityCheckedAt even when the value is unchanged', async () => {
    (prisma.book.findMany as jest.Mock).mockResolvedValue([
      { id: 'x', audioUrl: 'x.m4b', audioAvailability: 'AVAILABLE' },
    ]);
    s3Mock.on(HeadObjectCommand).resolves({ ContentLength: 1 });

    const r = await syncAvailability();

    expect(r.changed).toBe(0);
    expect(prisma.book.update).toHaveBeenCalledWith({
      where: { id: 'x' },
      data: { availabilityCheckedAt: expect.any(Date) },
    });
  });

  it('counts an error per failing key without aborting the sweep', async () => {
    (prisma.book.findMany as jest.Mock).mockResolvedValue([
      { id: 'ok', audioUrl: 'ok.m4b', audioAvailability: 'AVAILABLE' },
      { id: 'bad', audioUrl: 'bad.m4b', audioAvailability: 'AVAILABLE' },
    ]);
    s3Mock
      .on(HeadObjectCommand, { Key: 'ok.m4b' })
      .resolves({ ContentLength: 1 })
      .on(HeadObjectCommand, { Key: 'bad.m4b' })
      .rejects(new Error('access denied'));

    const r = await syncAvailability();

    expect(r.checked).toBe(1); // only the successful one increments checked
    expect(r.errors).toBe(1);
  });
});
