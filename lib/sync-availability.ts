/**
 * Nightly availability sync.
 *
 * HeadObjects every book's audio key and caches the result in
 * Book.audioAvailability (badges only — playback still HeadObjects at play time
 * via the stream endpoint). Uses the VERIFIED Intelligent-Tiering signals from
 * lib/restore: ArchiveStatus present = archived; + x-amz-restore
 * ongoing-request="true" = restoring; absent = available.
 *
 * Runs via the /api/cron/sync-availability route (EventBridge, nightly) or
 * directly: `npx tsx scripts/sync-availability.ts`.
 */

import { HeadObjectCommand } from '@aws-sdk/client-s3';
import { getS3Client, getS3Bucket, isS3Enabled } from './s3';
import { prisma } from './db';
import { logger } from './logger';
import { parseRestoreHeader, AVAILABILITY, type Availability } from './restore';

/** How many HeadObjects to run concurrently. 691 books / 10 ≈ a few seconds. */
const CONCURRENCY = 10;

export interface SyncResult {
  checked: number;
  available: number;
  archived: number;
  restoring: number;
  errors: number;
  /** Books whose cached availability actually changed this run. */
  changed: number;
}

function classify(head: { ArchiveStatus?: string; Restore?: string }): Availability {
  if (!head.ArchiveStatus) return AVAILABILITY.AVAILABLE;
  return parseRestoreHeader(head.Restore)?.ongoingRequest
    ? AVAILABILITY.RESTORING
    : AVAILABILITY.ARCHIVED;
}

export async function syncAvailability(): Promise<SyncResult> {
  if (!isS3Enabled()) {
    // Local files never archive; nothing to sync.
    logger.info('sync-availability skipped (S3 disabled)');
    return { checked: 0, available: 0, archived: 0, restoring: 0, errors: 0, changed: 0 };
  }

  const bucket = getS3Bucket();
  if (!bucket) throw new Error('AWS_S3_BUCKET is not configured');

  const books = await prisma.book.findMany({
    where: { audioUrl: { not: null } },
    select: { id: true, audioUrl: true, audioAvailability: true },
  });

  const result: SyncResult = {
    checked: 0,
    available: 0,
    archived: 0,
    restoring: 0,
    errors: 0,
    changed: 0,
  };
  const client = getS3Client();

  // Simple concurrency window over the book list.
  for (let i = 0; i < books.length; i += CONCURRENCY) {
    const batch = books.slice(i, i + CONCURRENCY);
    await Promise.all(
      batch.map(async (book) => {
        try {
          const head = await client.send(
            new HeadObjectCommand({ Bucket: bucket, Key: book.audioUrl! })
          );
          const availability = classify(head);
          result.checked++;
          if (availability === AVAILABILITY.AVAILABLE) result.available++;
          else if (availability === AVAILABILITY.ARCHIVED) result.archived++;
          else result.restoring++;

          if (book.audioAvailability !== availability) {
            await prisma.book.update({
              where: { id: book.id },
              data: { audioAvailability: availability, availabilityCheckedAt: new Date() },
            });
            result.changed++;
          } else {
            // Touch the timestamp so staleness is measurable even when unchanged.
            await prisma.book.update({
              where: { id: book.id },
              data: { availabilityCheckedAt: new Date() },
            });
          }
        } catch (error) {
          // Don't fail the whole sweep for one bad key.
          result.errors++;
          logger.error('sync-availability: HeadObject failed', {
            bookId: book.id,
            error: String(error),
          });
        }
      })
    );
  }

  logger.info('sync-availability complete', { ...result });
  return result;
}
