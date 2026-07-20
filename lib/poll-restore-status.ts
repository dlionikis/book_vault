/**
 * Restore-status poller (every 5 min via EventBridge).
 *
 * For each in_progress MediaRestoreRequest, HeadObjects the key. Completion
 * signal is **ArchiveStatus disappearing** (Intelligent-Tiering restores never
 * produce an expiry-date). On completion: mark the request completed, flip the
 * book to AVAILABLE, and notify the requesting user. Requests stuck past 24h
 * (Standard tier finishes in 3-5h) are marked failed.
 *
 * Runs via /api/cron/poll-restores (EventBridge) or directly:
 * `npx tsx scripts/poll-restore-status.ts`.
 */

import { HeadObjectCommand } from '@aws-sdk/client-s3';
import { getS3Client, getS3Bucket, isS3Enabled } from './s3';
import { prisma } from './db';
import { logger } from './logger';
import { AVAILABILITY } from './restore';
import { NotificationService } from './notification-service';

const STUCK_THRESHOLD_MS = 24 * 3600_000; // 3-5h expected; 24h = something is wrong

export interface PollResult {
  checked: number;
  completed: number;
  stillRestoring: number;
  failed: number;
  errors: number;
}

/**
 * Notify the requesting user that a restore finished. NotificationService
 * self-guards when push isn't configured (no SNS platform ARN); we additionally
 * catch here so a notification failure never breaks the poll loop.
 */
async function notifyRestoreComplete(
  userId: string,
  bookId: string,
  bookTitle: string
): Promise<void> {
  try {
    await NotificationService.sendRestoreComplete(userId, bookId, bookTitle);
  } catch (error) {
    logger.error('Restore-complete notification failed', { bookId, error: String(error) });
  }
}

export async function pollRestoreStatus(): Promise<PollResult> {
  const result: PollResult = { checked: 0, completed: 0, stillRestoring: 0, failed: 0, errors: 0 };

  if (!isS3Enabled()) {
    logger.info('poll-restore-status skipped (S3 disabled)');
    return result;
  }
  const bucket = getS3Bucket();
  if (!bucket) throw new Error('AWS_S3_BUCKET is not configured');

  const active = await prisma.mediaRestoreRequest.findMany({
    where: { status: 'in_progress' },
    include: { book: { select: { id: true, title: true } } },
  });
  logger.info('poll-restore-status: checking active restores', { count: active.length });

  const client = getS3Client();

  for (const restore of active) {
    result.checked++;
    try {
      const head = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: restore.s3Key }));

      if (!head.ArchiveStatus) {
        // Back in the Frequent Access tier — restore complete.
        await prisma.$transaction([
          prisma.mediaRestoreRequest.update({
            where: { id: restore.id },
            data: { status: 'completed', completedAt: new Date(), lastCheckedAt: new Date() },
          }),
          prisma.book.update({
            where: { id: restore.bookId },
            data: { audioAvailability: AVAILABILITY.AVAILABLE, availabilityCheckedAt: new Date() },
          }),
        ]);
        result.completed++;
        logger.info('Restore complete', { bookId: restore.bookId, title: restore.book.title });

        if (restore.requestedByUserId) {
          await notifyRestoreComplete(
            restore.requestedByUserId,
            restore.book.id,
            restore.book.title
          );
        }
        continue;
      }

      // Still restoring — bump lastCheckedAt; fail if stuck past the threshold.
      if (Date.now() - restore.requestedAt.getTime() > STUCK_THRESHOLD_MS) {
        await prisma.$transaction([
          prisma.mediaRestoreRequest.update({
            where: { id: restore.id },
            data: {
              status: 'failed',
              errorMessage: 'Restore did not complete within 24 hours',
              lastCheckedAt: new Date(),
            },
          }),
          // Reflect the failure in the cached column so the UI stops showing
          // "restoring" — the next play attempt / nightly sync re-derives it.
          prisma.book.update({
            where: { id: restore.bookId },
            data: { audioAvailability: AVAILABILITY.ARCHIVED, availabilityCheckedAt: new Date() },
          }),
        ]);
        result.failed++;
        logger.error('Restore stuck >24h, marked failed', {
          bookId: restore.bookId,
          title: restore.book.title,
        });
        continue;
      }

      await prisma.mediaRestoreRequest.update({
        where: { id: restore.id },
        data: { lastCheckedAt: new Date() },
      });
      result.stillRestoring++;
    } catch (error) {
      result.errors++;
      logger.error('poll-restore-status: check failed', {
        restoreId: restore.id,
        error: String(error),
      });
    }
  }

  logger.info('poll-restore-status complete', { ...result });
  return result;
}
