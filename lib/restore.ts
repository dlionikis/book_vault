/**
 * S3 Intelligent-Tiering archive/restore helpers.
 *
 * The most correctness-sensitive code in the restore workflow. Everything here
 * is built on the VERIFIED Intelligent-Tiering semantics (see
 * docs/plans/s3-archive-restore-workflow-v2.md — "Verified AWS Facts"):
 *
 * - Archive detection: HeadObject returns `ArchiveStatus` (ARCHIVE_ACCESS) for
 *   IT objects in the archive tier; the field is ABSENT once the object is back
 *   in Frequent/Infrequent Access. That absence is the completion signal.
 * - `RestoreObject` must NOT include `Days` — IT restores reject it. There is
 *   no temporary restored copy and no expiry: the object moves back to the
 *   Frequent Access tier permanently (until unaccessed for 90 days again).
 * - While a restore is in flight, HeadObject shows `ArchiveStatus` present AND
 *   `x-amz-restore: ongoing-request="true"` (SDK field: `Restore`).
 * - Standard-tier restores take 3-5 hours and are FREE.
 */

import { HeadObjectCommand, RestoreObjectCommand } from '@aws-sdk/client-s3';
import { getS3Client, getS3Bucket } from './s3';
import { prisma } from './db';
import { logger } from './logger';
import type { MediaRestoreRequest } from '@/lib/generated/prisma/client';

/** Standard-tier IT restores complete in 3-5 hours; use the upper bound for ETAs. */
export const RESTORE_ETA_HOURS = 5;

/** Book audio availability states (cached on Book.audioAvailability). */
export const AVAILABILITY = {
  AVAILABLE: 'AVAILABLE',
  ARCHIVED: 'ARCHIVED',
  RESTORING: 'RESTORING',
} as const;
export type Availability = (typeof AVAILABILITY)[keyof typeof AVAILABILITY];

/**
 * Parse the x-amz-restore header (SDK: HeadObjectCommandOutput.Restore).
 * Format while restoring: `ongoing-request="true"`.
 *
 * NOTE: IT restores never produce an expiry-date (no temporary copy) —
 * completion is signaled by ArchiveStatus disappearing, not by this header.
 */
export function parseRestoreHeader(header: string | undefined): { ongoingRequest: boolean } | null {
  if (!header) return null;
  return { ongoingRequest: /ongoing-request="true"/.test(header) };
}

export interface ArchiveState {
  /** Object is in the Archive Access tier (HeadObject.ArchiveStatus present). */
  archived: boolean;
  /** A restore is already in flight (x-amz-restore: ongoing-request="true"). */
  restoreOngoing: boolean;
}

/**
 * Real-time archive check for an S3 key. One HeadObject (~$0.0000004, tens of
 * ms) — always used for playback/download decisions; the cached
 * Book.audioAvailability column is for badges only.
 */
export async function getArchiveState(s3Key: string): Promise<ArchiveState> {
  const head = await getS3Client().send(
    new HeadObjectCommand({ Bucket: requireBucket(), Key: s3Key })
  );
  return {
    archived: Boolean(head.ArchiveStatus),
    restoreOngoing: parseRestoreHeader(head.Restore)?.ongoingRequest ?? false,
  };
}

/**
 * Initiate an S3 restore for an archived audio file. Idempotent:
 * - An existing in_progress DB request is returned as-is (dedup across
 *   devices/users/endpoints)
 * - S3's RestoreAlreadyInProgress error is swallowed (concurrent play taps, or
 *   a restore initiated outside the app) and a DB row is still recorded
 *
 * Also flips the book's cached availability to RESTORING in the same
 * transaction that records the request.
 */
export async function initiateRestore(
  book: { id: string; audioUrl: string },
  userId: string | null
): Promise<MediaRestoreRequest> {
  const existing = await prisma.mediaRestoreRequest.findFirst({
    where: { bookId: book.id, status: 'in_progress' },
    orderBy: { requestedAt: 'desc' },
  });
  if (existing) return existing;

  // Standard (3-5h, free) in normal operation. RESTORE_TIER=Expedited collapses
  // the feedback loop to 1-5 minutes for pipeline testing (~$0.03/GB — pennies
  // per book). Never leave Expedited set in production config.
  const tier = process.env.RESTORE_TIER === 'Expedited' ? 'Expedited' : 'Standard';

  try {
    await getS3Client().send(
      new RestoreObjectCommand({
        Bucket: requireBucket(),
        Key: book.audioUrl,
        // ⚠️ No Days element — Intelligent-Tiering restores reject it.
        RestoreRequest: {
          GlacierJobParameters: { Tier: tier },
        },
      })
    );
  } catch (error: unknown) {
    // Concurrent tap or externally-initiated restore: S3 already has one going.
    // Record it in the DB anyway so the poller tracks it to completion.
    if ((error as { name?: string }).name !== 'RestoreAlreadyInProgress') throw error;
    logger.info('Restore already in progress on S3; recording request', { bookId: book.id });
  }

  const [request] = await prisma.$transaction([
    prisma.mediaRestoreRequest.create({
      data: {
        bookId: book.id,
        s3Key: book.audioUrl,
        status: 'in_progress',
        restoreTier: tier,
        requestedByUserId: userId,
      },
    }),
    prisma.book.update({
      where: { id: book.id },
      data: { audioAvailability: AVAILABILITY.RESTORING, availabilityCheckedAt: new Date() },
    }),
  ]);

  logger.info('Restore initiated', { bookId: book.id, tier });
  return request;
}

/** Derived, never stored: single archive tier → ETA is always requestedAt + 5h. */
export function estimatedCompletion(requestedAt: Date): string {
  return new Date(requestedAt.getTime() + RESTORE_ETA_HOURS * 3600_000).toISOString();
}

/**
 * Self-heal the cached availability column (stream/restore endpoints call this
 * when the real-time HeadObject disagrees with the cache).
 */
export async function setBookAvailability(
  bookId: string,
  availability: Availability
): Promise<void> {
  await prisma.book.update({
    where: { id: bookId },
    data: { audioAvailability: availability, availabilityCheckedAt: new Date() },
  });
}

function requireBucket(): string {
  const bucket = getS3Bucket();
  if (!bucket) {
    // Callers only reach S3 paths when isS3Enabled() (which requires the
    // bucket); this guards against misconfiguration with a clear error.
    throw new Error('AWS_S3_BUCKET is not configured');
  }
  return bucket;
}
