# S3 Archive Restore Workflow - Updated Implementation Plan

> **Created**: January 2, 2026
> **Updated**: July 12, 2026 (revised for verified S3 Intelligent-Tiering semantics; added development & testing workflow); **July 19, 2026** (accuracy re-verified against current code — see the accuracy-review section below; Phase 0 marked complete)
> **Status**: **Phase 0 ✅ complete** (PR #88, deployed); Phases 1–8 not started
> **Priority**: High — a HeadObject sample on July 12, 2026 showed **5 of 8 audio files already in ARCHIVE_ACCESS**. A large portion of the library is currently unstreamable in production.
> **Dependencies**: S3 Intelligent-Tiering with Archive Access tier (already enabled — verified)

---

## Accuracy review — July 19, 2026

Every load-bearing claim was re-verified against the current tree. **The core of the plan is sound**: the verified AWS/IT facts, the architecture (cached column for badges + HeadObject at play time), the schema, phases 1–8, cost analysis, and testing strategy all hold. What changed:

1. **Phase 0 shipped (PR #88)** and matches the design: `GET /api/books/{id}/stream` exists (with the `status` discriminator so Phase 2's 202 is non-breaking), `S3_ENABLED` hybrid-mode override in `isS3Enabled()`, `getS3Client()`/`getS3Bucket()` exported from `lib/s3.ts`, `BookStreamResponse` in the OpenAPI spec, web `PlaybackClient` fetches the URL on demand (with `audioUrl`-prop fallback), iOS `APIClient.getBookStream` wired into `AudioPlayerManager`, and `__tests__/api/books/stream.test.ts` exists. **Rollout step 3 (nulling `audioUrl` in `transformBook`) is deliberately NOT done** — old installed iOS builds still stream from `book.audioUrl`; hold until all devices run the updated app.
2. **The code samples below predate the hardening and Next 16 — do not copy them literally.** New routes must use `requireUser(request)` (never inline `getServerSession`/`getAuthUserFromRequest` — hardening invariant), `normalizeUuid` + `isValidUuid` for id params, and the Next 16 async-params signature (`props: { params: Promise<{ id: string }> }` + `await props.params`). **The merged stream route (`app/api/books/[id]/stream/route.ts`) is the canonical template.**
3. **§5.3's "single ECS task" premise is false** — `book-vault-spot` currently runs **desiredCount 2**. The in-process `setInterval`/`instrumentation.ts` fallback would double-run every job (double `RestoreObject`s are harmless — DB dedup — but the poller would double-send push notifications). **Use EventBridge Scheduler; the in-process fallback is struck.**
4. **The iOS `DownloadManager` DI prerequisite is already met** — its eligibility/URL-generation calls were routed through the injected `APIClientProtocol` in the hardening (#79), so Phase 7's 202-handling in `DownloadManager` is mock-testable as-is.
5. **§2.7 verified**: the chapters route already degrades without a 500 — extraction failures are caught and return `200 { chapters: [], source: 'error' }`. ffprobe now runs via `execFile` with a 30s timeout (so an archived file's failing HTTP reads can't hang the handler).
6. **New deps to add when Phase 2/6 start**: `aws-sdk-client-mock` (devDep) and `@aws-sdk/client-sns` — pin SNS to the same `^3.1000` family as the existing `@aws-sdk/*` deps. Neither is installed yet.
7. **Contract-test side effects**: new response schemas in `__tests__/helpers/api-schemas.ts` must use **zod 4** forms (`z.uuid()`, `z.iso.datetime()` — not the removed `z.string().uuid()` style). The runtime is Node 24 / Next 16 / React 19 / Prisma 6; Phase 1's migrations run on Prisma 6 (the Prisma 7 move is a separate plan and does not block this).
8. **Fold-ins from the July 19 architecture review**: build the restore UI with `dark:` variants from the start, and take the D-5 items (route `error.tsx`/`loading.tsx` boundaries, a shared client-fetch helper with user-visible error states) alongside Phase 4 — the restore UI lands on exactly those surfaces.

---

## Overview

When S3 Intelligent-Tiering moves audiobook audio files to the Archive Access tier (after 90 days of no access), they become temporarily unavailable for streaming. This plan covers the full restore pipeline:

1. Detect archived books and surface availability status across all UIs
2. Let users request restores (single book or full series)
3. Background polling to detect restore completion
4. Push notifications via AWS SNS + APNs when books are ready
5. Graceful UX on both web and iOS

**Only audio files (`.m4b`) are subject to archiving.** Verified July 2026: audio files were uploaded with the `INTELLIGENT_TIERING` storage class; cover images, metadata JSON, and cue files are `STANDARD` and never archive — browsing always works instantly.

---

## Verified AWS Facts (July 12, 2026)

These were confirmed against the live `book-vault-media` bucket and current AWS behavior. **The rest of this plan depends on them — do not re-introduce Glacier storage-class assumptions.**

1. **Bucket config**: One Intelligent-Tiering configuration (`ArchiveConfig`), `ARCHIVE_ACCESS` after 90 days. **Deep Archive is NOT enabled** — there is exactly one archive tier, and restores always take ~3-5 hours (Standard tier).
2. **Detection is easy**: `HeadObject` returns an `ArchiveStatus` field (`ARCHIVE_ACCESS`) for IT objects in the archive tier. No range-request tricks, no S3 Inventory needed. When the object is in Frequent/Infrequent Access, `ArchiveStatus` is absent.
3. **Restores are free**: Standard (and Bulk) retrievals from IT archive tiers have no retrieval fee. Expedited is available for a fee (future option).
4. **`RestoreObject` must NOT include `Days`**: Intelligent-Tiering restores reject the `Days` element. There is no temporary restored copy.
5. **No expiry after restore**: Unlike Glacier storage classes, a restored IT object **moves back to the Frequent Access tier permanently** (until it again goes unaccessed for 90 days). There is no 24-hour window, no `expiry-date`, and no "restored_expiring" state.
6. **Completion signal**: While restoring, `HeadObject` shows `ArchiveStatus` present and `x-amz-restore: ongoing-request="true"`. When complete, **`ArchiveStatus` disappears**. Do not look for `expiry-date` — IT restores never produce one.
7. **Presigning is local**: `generatePresignedUrl()` ([lib/s3.ts](../../lib/s3.ts)) is pure HMAC signing — it makes **no S3 API call** and cannot fail for archived objects. A presigned URL for an archived object is happily generated and then fails with `403 InvalidObjectState` when the _client_ GETs it. Archive detection must therefore use `HeadObject`, never "try presign and catch".

### Glacier vs. Intelligent-Tiering cheat sheet

| Behavior             | Glacier storage classes            | S3 Intelligent-Tiering (ours)               |
| -------------------- | ---------------------------------- | ------------------------------------------- |
| Tier detection       | `StorageClass` on object           | `ArchiveStatus` field on HeadObject         |
| `RestoreObject` Days | Required                           | **Rejected — omit it**                      |
| Restored copy        | Temporary copy, expires after Days | Object moves back to Frequent Access, stays |
| Completion signal    | `ongoing-request="false"` + expiry | `ArchiveStatus` absent                      |
| Retrieval cost       | $0.01–$0.03/GB                     | **Free** (Standard/Bulk)                    |

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Phase 0: On-Demand URL Generation (Prerequisite)](#phase-0-on-demand-url-generation-prerequisite)
3. [Phase 1: Database Schema](#phase-1-database-schema)
4. [Phase 2: Backend API](#phase-2-backend-api)
5. [Phase 3: Book Availability Status](#phase-3-book-availability-status)
6. [Phase 4: Web Frontend](#phase-4-web-frontend)
7. [Phase 5: Background Jobs](#phase-5-background-jobs)
8. [Phase 6: iOS Push Notifications (AWS SNS + APNs)](#phase-6-ios-push-notifications-aws-sns--apns)
9. [Phase 7: iOS App Updates](#phase-7-ios-app-updates)
10. [Phase 8: Series-Level Restore](#phase-8-series-level-restore)
11. [Cost Analysis](#cost-analysis)
12. [Testing Strategy](#testing-strategy)
13. [Implementation Checklist](#implementation-checklist)

---

## Architecture Overview

### End-to-End Flow

```
User browses library
  ↓
Books show archive status badge (from cached audio_availability column, synced nightly)
  ↓
User taps "Play" on a book
  ↓
Client calls GET /api/books/{id}/stream
  ↓
API calls S3 HeadObject → reads ArchiveStatus field
  ↓
If archived: API calls S3 RestoreObject (no Days) + records restore request in DB
  ↓
Returns 202 { status: 'restoring', estimatedCompletion: '...' }
  ↓
Client shows "Restoring... ~3-5 hours" UI
  ↓
Background job polls S3 every 5 minutes for in-progress restores
  ↓
HeadObject no longer shows ArchiveStatus → restore complete:
  1. Update DB: request → 'completed', book → 'AVAILABLE'
  2. Look up requesting user's device tokens
  3. Send push notification via AWS SNS → APNs
  ↓
iOS receives push: "Your audiobook is ready to play!"
  ↓
User taps notification → deep links to book detail → Play button active
```

**Design principle**: The cached `audio_availability` column drives _badges only_. Playback and download decisions always do a real-time `HeadObject` (one cheap call at tap time), so a stale cache can never hand the client a URL that 403s.

### New Components

| Component                              | Purpose                                               |
| -------------------------------------- | ----------------------------------------------------- |
| `media_restore_requests` table         | Track restore state per file                          |
| `user_device_tokens` table             | Store APNs device tokens + SNS endpoints              |
| `audio_availability` column on books   | Cached availability for list-view badges              |
| `lib/restore.ts`                       | `initiateRestore()` + `parseRestoreHeader()` helpers  |
| `GET /api/books/{id}/stream`           | On-demand URL generation + archive detection          |
| `GET /api/books/{id}/restore-status`   | Poll restore progress                                 |
| `POST /api/books/{id}/restore`         | Explicitly request a restore (web/iOS restore button) |
| `POST /api/series/{id}/restore`        | Restore all archived books in a series                |
| `GET /api/books/restores`              | List active + recently completed restore requests     |
| `POST /api/notifications/register`     | Register iOS device token                             |
| `DELETE /api/notifications/register`   | Unregister device token                               |
| Update: `POST /api/downloads/{bookId}` | Archive detection added to existing download endpoint |
| Background: `poll-restore-status`      | Detect completed restores + trigger notifications     |
| Background: `sync-availability`        | Nightly job to cache archive status                   |
| `NotificationService`                  | Server-side SNS integration                           |
| iOS push notification handling         | APNs registration, deep linking                       |

---

## Phase 0: On-Demand URL Generation (Prerequisite)

**⚠️ Must be completed before any restore functionality**

**Time estimate**: 4-6 hours

### Problem

Currently, `transformBook()` ([lib/book-transformer.ts](../../lib/book-transformer.ts)) eagerly generates presigned S3 URLs for every book in list responses.

**Note**: presigning is a local signing operation — the old framing of "100+ S3 API calls per request" was wrong; eager generation costs no S3 calls and ~no money. The _real_ problems are:

- Playback can't be gated on archive status when URLs are handed out eagerly in lists
- Presigned URLs expire after 1 hour — a list left open goes stale and playback breaks
- There's no single endpoint where "this file is archived, restoring, ETA X" semantics can live
- Response payload hygiene (every list ships URLs almost nobody uses)

### Solution

Move presigned URL generation for **audio** to a dedicated stream endpoint called only when a user actually plays a book. Keep `coverUrl` generation as-is (covers are `STANDARD`, never archived).

### Enabler: `S3_ENABLED` override for local development

`isS3Enabled()` ([lib/s3.ts](../../lib/s3.ts)) requires `NODE_ENV === 'production'`, and `next dev` pins `NODE_ENV=development` — so the S3/archive code path is unreachable in local dev with hot reload. Add an explicit override honored alongside the existing check:

```typescript
export function isS3Enabled(): boolean {
  const override = process.env.S3_ENABLED === 'true';
  if (process.env.NODE_ENV !== 'production' && !override) return false;
  if (!S3_BUCKET) return false;
  // ... existing credential checks unchanged ...
}
```

This unlocks **hybrid mode** — local server + local Postgres + the real production bucket — which the entire manual-testing workflow relies on (see [Testing Strategy](#testing-strategy)).

### New endpoint: `GET /api/books/{id}/stream`

```typescript
// app/api/books/[id]/stream/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { normalizeUuid } from '@/lib/api-utils';
import { isS3Enabled, generatePresignedUrl } from '@/lib/s3';
import { getLocalAudioUrl } from '@/lib/media';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // Dual auth, same pattern as app/api/downloads/[bookId]/route.ts
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const bookId = normalizeUuid(params.id);
  if (!bookId) return NextResponse.json({ error: 'Invalid book ID format' }, { status: 400 });

  const book = await prisma.book.findUnique({
    where: { id: bookId },
    select: { id: true, audioUrl: true },
  });
  if (!book?.audioUrl) return NextResponse.json({ error: 'Book not found' }, { status: 404 });

  // Development: local files are always available, no presigning
  if (!isS3Enabled()) {
    return NextResponse.json({
      status: 'available',
      streamUrl: getLocalAudioUrl(book.audioUrl),
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
  }

  const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);
  return NextResponse.json({
    status: 'available',
    streamUrl,
    expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  });
}
```

(Phase 2 extends this with `HeadObject` archive detection — this phase just moves URL generation.)

### Client updates

- **Web** `PlaybackClient`/`AudioPlayer`: fetch `/api/books/{id}/stream` when the player mounts / user clicks Play, instead of receiving `audioUrl` as a prop from the server component
- **iOS** `AudioPlayerManager`: add `APIClient.getBookStream(bookId:)`, call before playback instead of using `book.audioUrl` ([AudioPlayerManager.swift:431](../../ios/BookVault/Services/AudioPlayerManager.swift#L431) currently streams `book.audioUrl` directly)

### ⚠️ Rollout order (don't break installed iOS builds)

Installed iOS builds stream from `book.audioUrl` in list responses. Removing it before the updated app is installed breaks streaming on old builds. Sequence:

1. **Deploy backend** with the new stream endpoint, **keeping `audioUrl` populated** in `transformBook()`
2. **Ship web + iOS client updates** that use the stream endpoint (TestFlight → device)
3. **Once updated app is installed on all devices**, change `transformBook()` to return `audioUrl: null` (keep the field for schema compatibility until the OpenAPI spec drops it)

### OpenAPI Spec Addition

```yaml
/api/books/{id}/stream:
  get:
    operationId: getBookStream
    tags: [Media]
    summary: Get on-demand streaming URL for a book
    description: |
      Generates a presigned S3 URL for audio playback (local API URL in development).
      Returns 202 with status=restoring if the file is archived; a restore is
      initiated automatically.
    security:
      - sessionAuth: []
      - bearerAuth: []
    parameters:
      - name: id
        in: path
        required: true
        schema:
          type: string
          format: uuid
    responses:
      '200':
        description: Stream URL ready
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/BookStreamResponse'
      '202':
        description: File is archived; restore initiated or already in progress
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/BookStreamResponse'
      '401':
        description: Unauthorized
      '404':
        description: Book not found

# components/schemas — single schema for both status codes keeps Swift codegen simple
BookStreamResponse:
  type: object
  required: [status]
  properties:
    status:
      type: string
      enum: [available, restoring]
    streamUrl:
      type: string
      format: uri
      description: Present when status=available
    expiresAt:
      type: string
      format: date-time
      description: Presigned URL expiry. Present when status=available
    bookId:
      type: string
      format: uuid
    message:
      type: string
      description: Human-readable status. Present when status=restoring
    requestedAt:
      type: string
      format: date-time
    estimatedCompletion:
      type: string
      format: date-time
      description: requestedAt + 5h (Standard tier upper bound). Present when status=restoring
```

### Success Metrics

- Playback still works on web and iOS (dev local mode AND production S3)
- Audio URLs only generated at play time; list responses eventually drop them
- Old iOS build keeps working until step 3 of the rollout

---

## Phase 1: Database Schema

**Time estimate**: 1-2 hours

### New Table: `media_restore_requests`

```prisma
model MediaRestoreRequest {
  id                String    @id @default(uuid())
  bookId            String    @map("book_id")
  s3Key             String    @map("s3_key")

  status            String    @default("in_progress") // in_progress, completed, failed
  restoreTier       String    @default("Standard") @map("restore_tier") // Standard (3-5h); Expedited is a future paid option

  requestedAt       DateTime  @default(now()) @map("requested_at")
  completedAt       DateTime? @map("completed_at")
  lastCheckedAt     DateTime? @map("last_checked_at")
  errorMessage      String?   @map("error_message")

  requestedByUserId String?   @map("requested_by_user_id")

  book              Book      @relation(fields: [bookId], references: [id], onDelete: Cascade)
  requestedBy       User?     @relation(fields: [requestedByUserId], references: [id], onDelete: SetNull)

  @@index([status, lastCheckedAt])
  @@index([bookId])
  @@index([requestedByUserId])
  @@map("media_restore_requests")
}
```

Changes from the original draft, per verified IT semantics:

- **Dropped `daysAvailable` and `expiresAt`** — IT restores have no temporary copy and no expiry
- **Dropped `storageClass`, `restoreStartedAt`, `availableAt`, `estimatedCompletionTime`** — single archive tier means the ETA is always `requestedAt + 5h` (derive it, don't store it); `pending`/`available`/`expired` statuses collapse into `in_progress`/`completed`
- **`requestedByUserId` is now optional (`String?`)** — required for `onDelete: SetNull` (Prisma rejects SetNull on a required relation), and lets system-initiated restores exist later

### New Table: `user_device_tokens`

```prisma
model UserDeviceToken {
  id             String   @id @default(uuid())
  userId         String   @map("user_id")
  deviceToken    String   @map("device_token")
  platform       String   @default("ios") // ios, web (future)
  snsEndpointArn String?  @map("sns_endpoint_arn")
  isActive       Boolean  @default(true) @map("is_active")
  createdAt      DateTime @default(now()) @map("created_at")
  updatedAt      DateTime @updatedAt @map("updated_at")

  user           User     @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, deviceToken])
  @@index([userId])
  @@map("user_device_tokens")
}
```

### Update `Book` Model

Cached availability for list-view badges (never used for playback decisions — see Phase 2):

```prisma
model Book {
  // ... existing fields ...

  audioAvailability     String    @default("AVAILABLE") @map("audio_availability") // AVAILABLE, ARCHIVED, RESTORING
  availabilityCheckedAt DateTime? @map("availability_checked_at")

  // ... existing relations ...
  restoreRequests       MediaRestoreRequest[]
}
```

We model **availability**, not raw storage class — every audio object's `StorageClass` is just `INTELLIGENT_TIERING`, which tells the UI nothing. `HeadObject.ArchiveStatus` (plus the restore header) maps cleanly onto these three states.

After the migration, all books default to `AVAILABLE`; the first run of the nightly sync (Phase 5) corrects them.

### Update `User` Model

```prisma
model User {
  // ... existing fields and relations ...
  deviceTokens    UserDeviceToken[]
  restoreRequests MediaRestoreRequest[]
}
```

---

## Phase 2: Backend API

**Time estimate**: 4-5 hours

### 2.1 Restore Helpers (`lib/restore.ts`)

The most correctness-sensitive code in the feature. Full spec:

```typescript
// lib/restore.ts
import { HeadObjectCommand, RestoreObjectCommand } from '@aws-sdk/client-s3';
import { getS3Client, getS3Bucket } from './s3';
import { prisma } from './db';

/** Standard-tier IT restores complete in 3-5 hours; use the upper bound for ETAs. */
export const RESTORE_ETA_HOURS = 5;

/**
 * Parse the x-amz-restore header (SDK: HeadObjectCommandOutput.Restore).
 * Format while restoring: `ongoing-request="true"`.
 * NOTE: IT restores never produce an expiry-date (no temporary copy) —
 * completion is signaled by ArchiveStatus disappearing, not by this header.
 */
export function parseRestoreHeader(header: string | undefined): { ongoingRequest: boolean } | null {
  if (!header) return null;
  return { ongoingRequest: /ongoing-request="true"/.test(header) };
}

/**
 * Initiate an S3 restore for an archived audio file. Idempotent:
 * - An existing in_progress DB request is returned as-is (dedup across devices/users)
 * - S3's RestoreAlreadyInProgress error is swallowed (concurrent play taps,
 *   or a restore initiated outside the app) and a DB row is still recorded
 */
export async function initiateRestore(
  book: { id: string; audioUrl: string },
  userId: string | null
) {
  const existing = await prisma.mediaRestoreRequest.findFirst({
    where: { bookId: book.id, status: 'in_progress' },
  });
  if (existing) return existing;

  // Standard (3-5h, free) in normal operation. RESTORE_TIER=Expedited collapses
  // the feedback loop to 1-5 minutes for pipeline testing (~$0.03/GB — pennies
  // per book). Never leave Expedited set in production config.
  const tier = process.env.RESTORE_TIER === 'Expedited' ? 'Expedited' : 'Standard';

  try {
    await getS3Client().send(
      new RestoreObjectCommand({
        Bucket: getS3Bucket(),
        Key: book.audioUrl,
        // ⚠️ No Days element — Intelligent-Tiering restores reject it.
        RestoreRequest: {
          GlacierJobParameters: { Tier: tier },
        },
      })
    );
  } catch (error: any) {
    if (error.name !== 'RestoreAlreadyInProgress') throw error;
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
      data: { audioAvailability: 'RESTORING' },
    }),
  ]);
  return request;
}

export function estimatedCompletion(requestedAt: Date): string {
  return new Date(requestedAt.getTime() + RESTORE_ETA_HOURS * 3600_000).toISOString();
}
```

### 2.2 Extend Stream Endpoint with Archive Detection

Replaces the Phase 0 production path. **Always HeadObject at play time** — one call (~$0.0000004, tens of ms) per play tap. The cached column can be ~24h stale and must never gate playback; this also means any cache drift self-heals on play.

```typescript
// app/api/books/[id]/stream/route.ts (production branch)
const head = await getS3Client().send(
  new HeadObjectCommand({ Bucket: getS3Bucket(), Key: book.audioUrl })
);

if (head.ArchiveStatus) {
  // Archived (restore may or may not be in flight) — initiateRestore is
  // idempotent for both cases and records/reuses the DB request.
  const restoreRequest = await initiateRestore(book, user.id);
  return NextResponse.json(
    {
      status: 'restoring',
      message: 'This audiobook is being restored from archive. It will be ready in 3-5 hours.',
      bookId: book.id,
      requestedAt: restoreRequest.requestedAt.toISOString(),
      estimatedCompletion: estimatedCompletion(restoreRequest.requestedAt),
    },
    { status: 202 }
  );
}

// Available — self-heal cached state if stale, then presign
if (book.audioAvailability !== 'AVAILABLE') {
  await prisma.book.update({
    where: { id: book.id },
    data: { audioAvailability: 'AVAILABLE', availabilityCheckedAt: new Date() },
  });
}
const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);
return NextResponse.json({
  status: 'available',
  streamUrl,
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
});
```

> **Why no try/presign/catch?** Presigning is local signing and never contacts S3 — it cannot throw `InvalidObjectState`. The only reliable server-side archive signal is `HeadObject.ArchiveStatus`.

### 2.3 Explicit Restore Endpoint

Backs the "Request restore" button (Phase 4/7) — lets a user restore without pretending to play:

```typescript
// app/api/books/[id]/restore/route.ts
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  // ... dual auth + normalizeUuid + book lookup (id, audioUrl), 404 if missing ...

  if (!isS3Enabled()) {
    return NextResponse.json({ status: 'available' }); // local files never archive
  }

  const head = await getS3Client().send(
    new HeadObjectCommand({ Bucket: getS3Bucket(), Key: book.audioUrl })
  );

  if (!head.ArchiveStatus) {
    // Nothing to restore — self-heal cache and report available
    await prisma.book.update({
      where: { id: book.id },
      data: { audioAvailability: 'AVAILABLE', availabilityCheckedAt: new Date() },
    });
    return NextResponse.json({ status: 'available' });
  }

  const restoreRequest = await initiateRestore(book, user.id);
  return NextResponse.json(
    {
      status: 'restoring',
      bookId: book.id,
      requestedAt: restoreRequest.requestedAt.toISOString(),
      estimatedCompletion: estimatedCompletion(restoreRequest.requestedAt),
    },
    { status: 202 }
  );
}
```

### 2.4 Restore Status Endpoint

Driven by the book's availability state (kept current by stream endpoint, poller, and nightly sync):

```typescript
// app/api/books/[id]/restore-status/route.ts
export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // ... auth + book lookup (audioAvailability) ...

  const latest = await prisma.mediaRestoreRequest.findFirst({
    where: { bookId: book.id },
    orderBy: { requestedAt: 'desc' },
  });

  switch (book.audioAvailability) {
    case 'RESTORING':
      return NextResponse.json({
        status: 'restoring',
        requestedAt: latest?.requestedAt,
        estimatedCompletion: latest ? estimatedCompletion(latest.requestedAt) : null,
      });
    case 'ARCHIVED':
      return NextResponse.json({
        status: 'archived',
        lastError: latest?.status === 'failed' ? latest.errorMessage : null,
      });
    default:
      return NextResponse.json({ status: 'available', completedAt: latest?.completedAt ?? null });
  }
}
```

OpenAPI schema:

```yaml
RestoreStatus:
  type: object
  required: [status]
  properties:
    status:
      type: string
      enum: [available, archived, restoring]
    requestedAt:
      type: string
      format: date-time
    estimatedCompletion:
      type: string
      format: date-time
    completedAt:
      type: string
      format: date-time
    lastError:
      type: string
```

### 2.5 Active Restores List

```typescript
// app/api/books/restores/route.ts
export async function GET(request: NextRequest) {
  // ... auth check ...

  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 3600_000);
  const restores = await prisma.mediaRestoreRequest.findMany({
    where: {
      requestedByUserId: user.id,
      OR: [{ status: 'in_progress' }, { status: 'completed', completedAt: { gte: sevenDaysAgo } }],
    },
    include: {
      book: { select: { id: true, title: true, coverUrl: true, audioAvailability: true } },
    },
    orderBy: { requestedAt: 'desc' },
  });

  return NextResponse.json({ restores });
}
```

(No expiry language — completed restores are simply available again.)

### 2.6 Update Existing Downloads Endpoint

[POST /api/downloads/[bookId]](../../app/api/downloads/%5BbookId%5D/route.ts) already does a HeadObject (via `getS3ObjectMetadata`) and presigns for iOS downloads. **An archived book currently gets a URL that 403s mid-download.** Fix: use a raw `HeadObjectCommand` (or extend the helper to return `ArchiveStatus`), and when `ArchiveStatus` is present, `initiateRestore()` and return the same 202 shape as the stream endpoint. Update the OpenAPI spec's download responses accordingly; iOS `DownloadManager` handles the 202 in Phase 7.

### 2.7 Chapters Endpoint — Graceful Degradation

The chapters route presigns a URL and runs ffprobe against it. For an archived file, ffprobe's HTTP reads fail, and extraction falls through to the cue/Audible-metadata fallbacks (both `STANDARD`, never archived) — verify this degrades without a 500. Optional optimization: when `book.audioAvailability !== 'AVAILABLE'`, skip the ffprobe attempt and go straight to the metadata fallbacks.

### 2.8 Device Token Registration

```typescript
// app/api/notifications/register/route.ts
export async function POST(request: NextRequest) {
  // ... auth check ...

  const { deviceToken, platform } = await request.json();

  if (!deviceToken || typeof deviceToken !== 'string') {
    return NextResponse.json({ error: 'deviceToken is required' }, { status: 400 });
  }

  // Create (or recover) the SNS platform endpoint — see NotificationService in Phase 6
  const snsEndpointArn = await NotificationService.registerEndpoint(deviceToken, platform || 'ios');

  await prisma.userDeviceToken.upsert({
    where: { userId_deviceToken: { userId: user.id, deviceToken } },
    create: {
      userId: user.id,
      deviceToken,
      platform: platform || 'ios',
      snsEndpointArn,
      isActive: true,
    },
    update: { snsEndpointArn, isActive: true },
  });

  return NextResponse.json({ success: true });
}

export async function DELETE(request: NextRequest) {
  // ... auth check ...
  const { deviceToken } = await request.json();

  await prisma.userDeviceToken.updateMany({
    where: { userId: user.id, deviceToken },
    data: { isActive: false },
  });

  return NextResponse.json({ success: true });
}
```

---

## Phase 3: Book Availability Status

**Time estimate**: 2 hours

### Problem

Users have no way to know a book is archived until they try to play it. Archive status should be visible throughout the UI — book grids, detail pages, search results.

### Solution: Cached `audioAvailability` on Book

The `audioAvailability` column (Phase 1) drives list-view badges. It's kept current by three writers:

1. **Nightly sync job** (Phase 5) — HeadObject sweep reading `ArchiveStatus`
2. **Stream/restore endpoints** — self-heal on every play/restore attempt
3. **Restore poller** (Phase 5) — flips `RESTORING → AVAILABLE` on completion

### API Response Changes

Add `archiveStatus` to the Book schema in OpenAPI (three states only — no expiring state exists with IT):

```yaml
Book:
  type: object
  properties:
    # ... existing properties ...
    archiveStatus:
      type: string
      enum: [available, archived, restoring]
      description: |
        Availability of the audio file:
        - available: Ready to stream immediately
        - archived: In the Intelligent-Tiering Archive Access tier; requires a ~3-5 hour restore
        - restoring: Restore in progress
```

Keep it **optional** in the schema (additive, backward-compatible): a pre-restore backend omits it and clients treat absent as available — a newly-required field would break decoding of old responses during rollout (notably an updated iOS build hitting the not-yet-deployed backend). Regenerate TS + Swift types.

### Update `transformBook()`

Derived purely from the row already in hand — **zero extra queries** (the original draft's per-book `findFirst` would have been an N+1 on every 100-book list page):

```typescript
const ARCHIVE_STATUS_MAP = {
  AVAILABLE: 'available',
  ARCHIVED: 'archived',
  RESTORING: 'restoring',
} as const;

export async function transformBook(book: BookWithIncludes) {
  // ... existing transform logic ...
  return {
    // ... existing fields ...
    archiveStatus:
      ARCHIVE_STATUS_MAP[book.audioAvailability as keyof typeof ARCHIVE_STATUS_MAP] ?? 'available',
  };
}
```

---

## Phase 4: Web Frontend

**Time estimate**: 2-3 hours

### 4.1 Archive Status Badge

New component for book cards and detail views:

```typescript
// components/ArchiveStatusBadge.tsx
'use client';

interface ArchiveStatusBadgeProps {
  status: 'available' | 'archived' | 'restoring';
  estimatedCompletion?: string;
  compact?: boolean; // For book cards (icon only)
}

export function ArchiveStatusBadge({
  status,
  estimatedCompletion,
  compact,
}: ArchiveStatusBadgeProps) {
  if (status === 'available') return null;

  // archived → snowflake icon + "Archived"
  // restoring → spinner icon + "Restoring..." + ETA
  // (remember dark: variants)
}
```

### 4.2 Update BookCard

Show archive badge overlay on book cards in grids:

```tsx
<div className="relative">
  <Image src={coverUrl} ... />
  <ArchiveStatusBadge status={book.archiveStatus} compact />
</div>
```

### 4.3 Update Book Detail Page

```tsx
{
  book.archiveStatus === 'archived' ? (
    <RestoreButton bookId={book.id} /> // calls POST /api/books/{id}/restore
  ) : book.archiveStatus === 'restoring' ? (
    <RestoringIndicator bookId={book.id} />
  ) : (
    <PlayButton bookId={book.id} />
  );
}
```

The player itself must also handle a 202 from `/stream` (race: book archived since page load) by switching to the restoring UI.

### 4.4 Restoring Indicator with Polling

```typescript
// components/RestoringIndicator.tsx
'use client';

export function RestoringIndicator({ bookId }: Props) {
  const [status, setStatus] = useState<'restoring' | 'available'>('restoring');

  useEffect(() => {
    const interval = setInterval(async () => {
      const res = await fetch(`/api/books/${bookId}/restore-status`);
      const data = await res.json();
      if (data.status === 'available') {
        setStatus('available');
        clearInterval(interval);
        // Update parent state / router.refresh()
      }
    }, 30_000);

    return () => clearInterval(interval);
  }, [bookId]);

  // Spinner + ETA countdown from estimatedCompletion
}
```

### 4.5 Restores List Page

New page at `/library/restores`:

```
/library/restores
├── Active Restores (in_progress)
│   └── BookCard + spinner + ETA
└── Recently Restored (completed, last 7 days)
    └── BookCard + "ready to play"
```

(No "expires in X hours" — restored books stay available.)

---

## Phase 5: Background Jobs

**Time estimate**: 2-3 hours

### 5.1 Restore Status Poller

Runs every 5 minutes. **Completion signal: `ArchiveStatus` disappears from HeadObject** (IT restores never produce an `expiry-date`; the original draft's `!ongoingRequest && expiryDate` check would never have fired).

```typescript
// scripts/poll-restore-status.ts
import { HeadObjectCommand } from '@aws-sdk/client-s3';
import { getS3Client, getS3Bucket } from '@/lib/s3';
import { prisma } from '@/lib/db';
import { NotificationService } from '@/lib/notification-service';

const STUCK_THRESHOLD_MS = 24 * 3600_000; // Standard tier finishes in 3-5h; 24h = something is wrong

export async function pollRestoreStatus() {
  const activeRestores = await prisma.mediaRestoreRequest.findMany({
    where: { status: 'in_progress' },
    include: { book: { select: { id: true, title: true } } },
  });

  console.log(`Checking ${activeRestores.length} active restores...`);

  for (const restore of activeRestores) {
    try {
      const head = await getS3Client().send(
        new HeadObjectCommand({ Bucket: getS3Bucket(), Key: restore.s3Key })
      );

      if (!head.ArchiveStatus) {
        // Object is back in the Frequent Access tier — restore complete
        console.log(`✅ Restore complete: ${restore.book.title}`);

        await prisma.$transaction([
          prisma.mediaRestoreRequest.update({
            where: { id: restore.id },
            data: { status: 'completed', completedAt: new Date() },
          }),
          prisma.book.update({
            where: { id: restore.bookId },
            data: { audioAvailability: 'AVAILABLE', availabilityCheckedAt: new Date() },
          }),
        ]);

        if (restore.requestedByUserId) {
          await NotificationService.sendRestoreComplete(
            restore.requestedByUserId,
            restore.book.id,
            restore.book.title
          );
        }
        continue;
      }

      // Still restoring
      await prisma.mediaRestoreRequest.update({
        where: { id: restore.id },
        data: { lastCheckedAt: new Date() },
      });

      if (Date.now() - restore.requestedAt.getTime() > STUCK_THRESHOLD_MS) {
        await prisma.mediaRestoreRequest.update({
          where: { id: restore.id },
          data: { status: 'failed', errorMessage: 'Restore did not complete within 24 hours' },
        });
        // Book stays RESTORING until nightly sync corrects it to ARCHIVED,
        // or correct it here directly for faster feedback.
      }
    } catch (error) {
      console.error(`Error checking restore ${restore.id}:`, error);
    }
  }
}
```

### 5.2 Nightly Availability Sync

`HeadObject.ArchiveStatus` makes this trivial (the original draft's caveat about IT tiers being undetectable was wrong):

```typescript
// scripts/sync-availability.ts
import { parseRestoreHeader } from '@/lib/restore';

export async function syncAvailability() {
  const books = await prisma.book.findMany({
    where: { audioUrl: { not: null } },
    select: { id: true, audioUrl: true, audioAvailability: true },
  });

  // Process in batches of ~10 concurrent HeadObjects; 691 books ≈ a few seconds
  for (const book of books) {
    try {
      const head = await getS3Client().send(
        new HeadObjectCommand({ Bucket: getS3Bucket(), Key: book.audioUrl! })
      );

      const availability = !head.ArchiveStatus
        ? 'AVAILABLE'
        : parseRestoreHeader(head.Restore)?.ongoingRequest
          ? 'RESTORING'
          : 'ARCHIVED';

      await prisma.book.update({
        where: { id: book.id },
        data: { audioAvailability: availability, availabilityCheckedAt: new Date() },
      });
    } catch (error) {
      // Log and continue — don't fail the whole job for one book
      console.error(`Failed availability check for book ${book.id}:`, error);
    }
  }
}
```

Run this **once immediately after deploying Phase 1+3** — it will reveal exactly how many books are currently archived (sample suggests a majority).

### 5.3 Deployment: Cron API Routes

```typescript
// app/api/cron/poll-restores/route.ts  (and /api/cron/sync-availability)
export async function GET(req: Request) {
  const authHeader = req.headers.get('authorization');
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }
  await pollRestoreStatus();
  return Response.json({ success: true, checkedAt: new Date().toISOString() });
}
```

**Scheduling**: EventBridge Scheduler → API destination hitting `https://bookvault.lionikis.com/api/cron/poll-restores` every 5 minutes (with the `Authorization` header stored in an EventBridge connection), and `/api/cron/sync-availability` nightly at 3 AM. Serverless, no new ECS tasks, and the endpoints remain manually triggerable with `curl` for testing. (~~In-process `setInterval` via `instrumentation.ts`~~ — **struck July 19**: the service runs **2 ECS tasks**, so every in-process job would run twice; duplicate `RestoreObject`s are dedup'd in the DB, but the poller would double-send push notifications. EventBridge hits the ALB once per schedule and lands on one task.)

---

## Deployed Infrastructure (as-built, July 20, 2026)

The Phase 5 jobs are wired up and running in production. **Note: implemented with
classic EventBridge _Rules_, not EventBridge _Scheduler_** — Scheduler rejected the
API-destination target ARN (`ValidationException: Provided Arn is not in correct
format`); classic Rules are the supported path for API-destination targets and match
the plan's "EventBridge → API destination" intent.

| Resource               | Identifier / value                                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cron secret            | Secrets Manager `book-vault/cron` (key `CRON_SECRET`); execution role's existing `book-vault/*` grant covers it                                                                       |
| Task definition        | `book-vault:6` (= `:5` + the `CRON_SECRET` secret ref); both services rolled onto it                                                                                                  |
| EventBridge connection | `book-vault-cron` — API_KEY auth, header `Authorization: Bearer <CRON_SECRET>`                                                                                                        |
| API destinations       | `book-vault-poll-restores` → `/api/cron/poll-restores`; `book-vault-sync-availability` → `/api/cron/sync-availability` (both GET)                                                     |
| Invoke role            | `book-vault-scheduler-cron` (trusts `events.amazonaws.com`; policy `InvokeCronApiDestinations` → `events:InvokeApiDestination` on the two destinations)                               |
| Rules                  | `book-vault-poll-restores` = `rate(5 minutes)`; `book-vault-sync-availability` = `cron(0 8 * * ? *)` **UTC** (≈ 3 AM Central; classic Rules are UTC-only, so this does not track DST) |
| S3 restore IAM         | task role `book-vault-ecs-task` inline policy `S3RestoreAccess` → `s3:RestoreObject` on `book-vault-media/*` (HeadObject already covered by GetObject)                                |

**Migration note (P3005):** prod's DB predated Prisma migration tracking — `migrate deploy`
failed with `P3005` (schema not empty, empty `_prisma_migrations`). Resolved by baselining
the 3 pre-existing migrations (`migrate resolve --applied <name>` — history rows only, no
schema SQL) then `migrate deploy` for `20260719183757_restore_workflow_schema`. Prod
`db-migrate.sh` also had two bugs fixed in #108 (unpinned CLI pulled Prisma 7; false-success
on ECS-exec).

**First sync result (July 20, 2026):** 764 audio files checked → **695 archived (~91%)**, 69
available, 0 errors. Confirms the feature's premise: the large majority of the library is in
the Intelligent-Tiering Archive Access tier.

**Manual re-run / debug:**
`curl -H "Authorization: Bearer $CRON_SECRET" https://bookvault.lionikis.com/api/cron/sync-availability`
(secret via `aws secretsmanager get-secret-value --secret-id book-vault/cron`).

---

## Phase 6: iOS Push Notifications (AWS SNS + APNs)

**Time estimate**: 4-5 hours

Pipeline:

```
iOS app launch
  → Register with APNs → receive device token
  → POST /api/notifications/register { deviceToken }
  → Backend creates/recovers AWS SNS Platform Endpoint
  → Store endpoint ARN + device token in DB

Restore completes (detected by poller)
  → NotificationService.sendRestoreComplete(userId, bookId, title)
  → Look up user's active device tokens
  → For each: SNS.publish() with APNs payload
  → iOS receives push → user taps → deep link to book detail
```

### 6.1 AWS Setup (One-Time)

**a) Create APNs key in Apple Developer Portal:**

1. Certificates, Identifiers & Profiles → Keys
2. Create a key with "Apple Push Notifications service (APNs)" enabled
3. Download the `.p8` file — note the Key ID and Team ID

**b) Create SNS Platform Application:**

```bash
aws sns create-platform-application \
  --name book-vault-ios \
  --platform APNS \
  --attributes \
    PlatformCredential="$(cat AuthKey_XXXXXXXXXX.p8)",\
    PlatformPrincipal="YOUR_TEAM_ID",\
    ApplePlatformKeyId="YOUR_KEY_ID",\
    ApplePlatformBundleId="com.yourname.BookVault" \
  --profile book_vault \
  --region us-east-1
```

> **Note**: `APNS` for production builds, `APNS_SANDBOX` for development — create both during testing. Store the ARNs in environment variables / Secrets Manager. The ECS task role needs `sns:CreatePlatformEndpoint`, `sns:SetEndpointAttributes`, and `sns:Publish` on these resources.

**c) Environment variables:**

```env
AWS_SNS_PLATFORM_APPLICATION_ARN=arn:aws:sns:us-east-1:XXXX:app/APNS/book-vault-ios
AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX=arn:aws:sns:us-east-1:XXXX:app/APNS_SANDBOX/book-vault-ios
```

### 6.2 Backend NotificationService

```typescript
// lib/notification-service.ts
import {
  SNSClient,
  PublishCommand,
  CreatePlatformEndpointCommand,
  SetEndpointAttributesCommand,
} from '@aws-sdk/client-sns';
import { prisma } from './db';

const snsClient = new SNSClient({ region: process.env.AWS_REGION || 'us-east-1' });

export class NotificationService {
  /**
   * Create or recover the SNS platform endpoint for a device token.
   *
   * ⚠️ CreatePlatformEndpoint is only idempotent when attributes match. If the
   * token exists with different attributes, SNS throws InvalidParameter with
   * the existing ARN embedded in the message — recover it. Also re-enable
   * endpoints that APNs feedback disabled.
   */
  static async registerEndpoint(deviceToken: string, platform: string): Promise<string> {
    const platformAppArn =
      process.env.NODE_ENV === 'production'
        ? process.env.AWS_SNS_PLATFORM_APPLICATION_ARN
        : process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX;

    let endpointArn: string;
    try {
      const result = await snsClient.send(
        new CreatePlatformEndpointCommand({
          PlatformApplicationArn: platformAppArn,
          Token: deviceToken,
        })
      );
      endpointArn = result.EndpointArn!;
    } catch (error: any) {
      const match = /Endpoint (arn:aws:sns:\S+) already exists/.exec(error.message ?? '');
      if (error.name === 'InvalidParameterException' && match) {
        endpointArn = match[1];
      } else {
        throw error;
      }
    }

    // Ensure the endpoint is enabled and carries the current token
    await snsClient.send(
      new SetEndpointAttributesCommand({
        EndpointArn: endpointArn,
        Attributes: { Token: deviceToken, Enabled: 'true' },
      })
    );

    return endpointArn;
  }

  /**
   * Send a push notification when a book restore completes.
   */
  static async sendRestoreComplete(userId: string, bookId: string, bookTitle: string) {
    const tokens = await prisma.userDeviceToken.findMany({
      where: { userId, isActive: true },
    });

    if (tokens.length === 0) {
      console.log(`No active device tokens for user ${userId}, skipping notification`);
      return;
    }

    for (const token of tokens) {
      if (!token.snsEndpointArn) continue;

      try {
        const payload = {
          aps: {
            alert: {
              title: 'Audiobook Ready',
              body: `"${bookTitle}" has been restored and is ready to play.`,
            },
            sound: 'default',
            badge: 1,
          },
          // Custom data for deep linking
          bookId,
          action: 'restore_complete',
        };

        await snsClient.send(
          new PublishCommand({
            TargetArn: token.snsEndpointArn,
            Message: JSON.stringify({
              default: `${bookTitle} is ready to play`,
              APNS: JSON.stringify(payload),
              APNS_SANDBOX: JSON.stringify(payload),
            }),
            MessageStructure: 'json',
          })
        );

        console.log(`Push sent to user ${userId} for book "${bookTitle}"`);
      } catch (error: any) {
        if (error.name === 'EndpointDisabledException') {
          await prisma.userDeviceToken.update({
            where: { id: token.id },
            data: { isActive: false },
          });
          console.log(`Disabled stale endpoint for user ${userId}`);
        } else {
          console.error(`Failed to send push to ${token.snsEndpointArn}:`, error);
        }
      }
    }
  }
}
```

### 6.3 Token Refresh Handling

APNs device tokens can change. The iOS app re-registers on every launch; the backend handles it via the upsert + `registerEndpoint()` recovery logic above.

---

## Phase 7: iOS App Updates

**Time estimate**: 4-5 hours

### 7.1 Push Notification Registration

```swift
// BookVaultApp.swift
import UserNotifications

@main
struct BookVaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        return true
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await NotificationRegistrar.shared.register(deviceToken: token)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DebugLogger.error("Failed to register for push: \(error)")
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let bookId = userInfo["bookId"] as? String,
           let action = userInfo["action"] as? String,
           action == "restore_complete" {
            DeepLinkManager.shared.navigate(to: .bookDetail(bookId: bookId))
        }
        handler()
    }
}
```

### 7.2 NotificationRegistrar Service

```swift
// Services/NotificationRegistrar.swift
class NotificationRegistrar {
    static let shared = NotificationRegistrar()
    private let apiClient = APIClient.shared

    func register(deviceToken: String) async {
        do {
            try await apiClient.post("/api/notifications/register", body: [
                "deviceToken": deviceToken,
                "platform": "ios"
            ])
            DebugLogger.info("Device token registered for push notifications")
        } catch {
            DebugLogger.error("Failed to register device token: \(error)")
        }
    }

    func unregister(deviceToken: String) async {
        do {
            try await apiClient.delete("/api/notifications/register", body: [
                "deviceToken": deviceToken
            ])
        } catch {
            DebugLogger.error("Failed to unregister device token: \(error)")
        }
    }
}
```

### 7.3 Restore UI in iOS

**BookDetailView** — swap play button based on `archiveStatus` (three states — no expiring state exists):

```swift
switch book.archiveStatus {
case .archived:
    RestoreRequestButton(bookId: book.id)   // POST /api/books/{id}/restore
case .restoring:
    RestoringProgressView(bookId: book.id)  // polls /restore-status
default:
    PlayButton(bookId: book.id)
}
```

**AudioPlayerManager**: handle a 202 from `getBookStream(bookId:)` (book archived since the list was fetched) by surfacing the restoring state instead of a playback error.

**DownloadManager**: handle a 202 from `POST /api/downloads/{bookId}` the same way (see Phase 2.6).

**Archive badge on book cards** — subtle overlay icon (snowflake for archived, spinner for restoring).

### 7.4 Deep Link Manager

```swift
// Services/DeepLinkManager.swift
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    enum Destination {
        case bookDetail(bookId: String)
        case restoresList
    }

    @Published var pendingDestination: Destination?

    func navigate(to destination: Destination) {
        DispatchQueue.main.async {
            self.pendingDestination = destination
        }
    }
}
```

Wire this into the root `ContentView` to handle navigation when a push notification is tapped.

---

## Phase 8: Series-Level Restore

**Time estimate**: 2-3 hours

### Problem

If a user wants to listen to a 15-book series and all are archived, they'd need to request restores one at a time. Series-level restore batch-initiates all archived books in a series.

### API Endpoint

Canonical path: **`POST /api/series/{id}/restore`** (it's a series operation; the earlier draft listed an inconsistent `/api/books/{id}/restore-series` — that path is dropped).

```typescript
// app/api/series/[id]/restore/route.ts
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  // ... dual auth + normalizeUuid ...

  const seriesBooks = await prisma.bookSeries.findMany({
    where: { seriesId },
    include: {
      book: { select: { id: true, title: true, audioUrl: true, audioAvailability: true } },
    },
    orderBy: { sequence: 'asc' },
  });

  const archivedBooks = seriesBooks.filter(
    (sb) => sb.book.audioUrl && sb.book.audioAvailability === 'ARCHIVED'
  );

  if (archivedBooks.length === 0) {
    return NextResponse.json({
      message: 'No archived books in this series',
      total: 0,
      results: [],
    });
  }

  const results = [];
  for (const sb of archivedBooks) {
    try {
      await initiateRestore({ id: sb.book.id, audioUrl: sb.book.audioUrl! }, user.id);
      results.push({ bookId: sb.book.id, title: sb.book.title, status: 'initiated' });
    } catch (error) {
      results.push({
        bookId: sb.book.id,
        title: sb.book.title,
        status: 'failed',
        error: String(error),
      });
    }
  }

  return NextResponse.json({
    message: `Restore initiated for ${results.filter((r) => r.status === 'initiated').length} books`,
    total: archivedBooks.length,
    results,
  });
}
```

(Filtering on the cached column is fine here — `initiateRestore` is harmless if a book turns out to be available, and the per-book stream call self-corrects at play time.)

### OpenAPI Spec

```yaml
/api/series/{id}/restore:
  post:
    operationId: restoreSeries
    tags: [Series]
    summary: Restore all archived books in a series
    security:
      - sessionAuth: []
      - bearerAuth: []
    parameters:
      - name: id
        in: path
        required: true
        schema:
          type: string
          format: uuid
    responses:
      '200':
        description: Restore initiated
        content:
          application/json:
            schema:
              type: object
              required: [message, total, results]
              properties:
                message:
                  type: string
                total:
                  type: integer
                results:
                  type: array
                  items:
                    type: object
                    properties:
                      bookId:
                        type: string
                      title:
                        type: string
                      status:
                        type: string
                        enum: [initiated, failed]
```

### UI Integration

**Web**: "Restore All Archived" button on the series detail page when any books are archived, with a count: "3 of 12 books are archived".

**iOS**: Same treatment on the series view. One API call; individual book cards update as restores complete.

### Notification Behavior

The poller detects individual book completions, each triggering its own push. Improvement: if multiple books from the same series complete within one poll cycle, send a single batched notification: "3 books from [Series Name] are ready to play."

---

## Cost Analysis

### S3 Restore Costs — free at our tier

Restores from the Intelligent-Tiering Archive Access tier using **Standard (3-5h) or Bulk retrieval are free** — no retrieval fee (that's what the IT monitoring fee, already being paid, covers). The earlier Glacier-based cost table ($0.03/GB etc.) did not apply.

| Tier                      | Restore Time | Cost                                                 |
| ------------------------- | ------------ | ---------------------------------------------------- |
| Standard                  | 3-5 hours    | **$0.00**                                            |
| Expedited (future option) | minutes      | ~$0.03/GB + $10/1k requests (verify current pricing) |

After restore, the object sits in Frequent Access (standard storage rates) and descends through the tiers again if unaccessed — no action or cost on our side.

### AWS SNS Costs

| Component                 | Free Tier            | After Free Tier |
| ------------------------- | -------------------- | --------------- |
| Mobile push notifications | 1M/month (permanent) | $0.50 per 1M    |

Projected usage: single-digit notifications/month. **$0.00.**

### HeadObject Requests

- Nightly sync: 691 books × 30 days ≈ 20,700 requests/month × $0.0004/1k ≈ **$0.008/month**
- Poller + play-time checks: negligible (a few hundred requests/month)

### Total: ≈ $0.01/month

---

## Testing Strategy

### Development & Testing Workflow (three rings)

Backend, web, and scripts are developed in VSCode; only the Xcode project itself needs Xcode. Feedback loops, fastest to slowest:

**Ring 1 — Jest with mocked S3 (seconds).** Add `aws-sdk-client-mock` as a dev dependency and mock `HeadObjectCommand` / `RestoreObjectCommand` responses. All branch logic is verified here — including asserting that the `RestoreObject` input contains **no `Days`** and that dedup prevents duplicate restore calls. Run `npm run validate:full` before each PR (contract tests guard the generated Swift models).

**Ring 2 — Hybrid mode: local server + local DB + real production bucket (minutes).** Enabled by the Phase 0 `S3_ENABLED` override:

```bash
# .env.local
S3_ENABLED=true
AWS_S3_BUCKET=book-vault-media
AWS_ACCESS_KEY_ID=...        # book_vault profile credentials
AWS_SECRET_ACCESS_KEY=...
```

Because `audioUrl` values double as both local relative paths and S3 keys, running `npx tsx scripts/sync-availability.ts` locally against the prod bucket fills the **local** DB with real archive states. The whole web UI (badges, restore buttons, restores page) is then developed against genuine data, and clicking Play on a genuinely archived book exercises the 202 path for real. Trigger cron routes with `curl -H "Authorization: Bearer $CRON_SECRET" localhost:3000/api/cron/poll-restores`, or run the scripts directly from the CLI. Hybrid mode is safe: the app only HeadObjects, presigns, and restores against S3 (never writes objects), and IT restores are free. One caveat — restoring a book moves it back to Frequent Access and **resets its 90-day archive clock**, so pick one or two _designated test books_ rather than restoring indiscriminately.

**Ring 3 — Full pipeline with fast restores (minutes, not hours).** Set `RESTORE_TIER=Expedited` (Phase 2) so test restores complete in 1-5 minutes (~$0.02 per 500MB book) instead of 3-5 hours: request restore → poller detects completion → push notification → playback. Works from hybrid mode or in production. Finish with **one Standard-tier restore as an overnight soak test**, then confirm the default is back to Standard.

### iOS testing

- **UI states (Simulator, fast loop)**: point the simulator build at the local hybrid-mode server. Archived/restoring badges and 202 handling in `AudioPlayerManager`/`DownloadManager` are plain API responses — no device needed.
- **Deep-link handling without a backend**: `xcrun simctl push booted <bundle-id> payload.apns` injects a notification payload into the simulator. Write a `payload.apns` with the `bookId`/`action: restore_complete` fields and iterate on the tap → `DeepLinkManager` → book detail flow before SNS even exists.
- **Real push E2E (physical device — required)**: real APNs registration and delivery must be verified on a device (simulator-only testing has burned this project before). The full pipeline works without deploying anything: iPhone on the same LAN → local hybrid-mode server → `APNS_SANDBOX` platform app → APNs → device. Verify delivery from the SNS console first to isolate Apple-side config issues from app code.
- **Xcode mechanics**: the push entitlement goes in `project.yml`, then `cd ios && xcodegen generate` — never edit the generated project directly. Debug builds on device use `APNS_SANDBOX`; the production `APNS` platform app only matters for TestFlight builds.

### Use real archived objects — they already exist

The bucket has been live since December 2025 with a 90-day archive threshold. A HeadObject sample (July 12, 2026) found **5 of 8 audio files in `ARCHIVE_ACCESS`**. There is no need to simulate archiving:

1. **Find test subjects**: run `scripts/sync-availability.ts` (or a one-off HeadObject sweep) against production — it doubles as the first real validation of the sync job
2. **Full flow**: pick an archived book → tap play → verify 202 + restoring UI → confirm `RestoreObject` accepted (HeadObject shows `ongoing-request="true"`) → wait 3-5h → poller flips it → push notification arrives → playback works
3. **Push notifications**: use the SNS console to send a test push to a registered endpoint before wiring the poller
4. **Series restore**: find a series with 2+ archived books via the sync results → trigger → verify all complete

> **⚠️ Do NOT test with `copy-object --storage-class GLACIER`** (the earlier draft suggested this). That puts the object in the _Glacier storage class_, which has different semantics — `Days` required on restore, `expiry-date` headers, retrieval fees — none of which this implementation handles, by design. It would test code paths we deliberately don't have. There's also no way to force an IT object into Archive Access early; the real archived objects above are the test bed.

### Automated Tests

Mock the S3 client with `aws-sdk-client-mock` (`HeadObjectCommand` / `RestoreObjectCommand`).

```typescript
// __tests__/api/books/stream.test.ts
describe('GET /api/books/{id}/stream', () => {
  it('returns 200 with streamUrl when HeadObject has no ArchiveStatus');
  it('returns local /api/audio URL in development (S3 disabled)');
  it('returns 202 and calls RestoreObject when ArchiveStatus present');
  it('returns 202 without duplicate RestoreObject when restore already ongoing');
  it('self-heals stale audioAvailability on successful stream');
  it('returns 401 for unauthenticated requests');
  it('returns 404 for non-existent books');
});

// __tests__/lib/restore.test.ts
describe('initiateRestore', () => {
  it('sends RestoreObject WITHOUT Days (IT requirement)');
  it('dedupes against an existing in_progress request');
  it('swallows RestoreAlreadyInProgress and still records the request');
  it('sets book.audioAvailability to RESTORING transactionally');
});

// __tests__/scripts/poll-restore-status.test.ts
describe('pollRestoreStatus', () => {
  it('marks completed + book AVAILABLE when ArchiveStatus is absent');
  it('leaves in_progress and updates lastCheckedAt while ArchiveStatus present');
  it('marks failed after 24h without completion');
  it('sends push notification to the requesting user on completion');
});

// __tests__/api/books/restore-status.test.ts
describe('GET /api/books/{id}/restore-status', () => {
  it('returns available for AVAILABLE books');
  it('returns restoring with ETA for RESTORING books');
  it('returns archived for ARCHIVED books with no active restore');
});

// __tests__/api/notifications/register.test.ts
describe('POST /api/notifications/register', () => {
  it('registers a new device token');
  it('updates existing token (upsert)');
  it('recovers existing endpoint ARN from InvalidParameter error');
});

// __tests__/api/series/restore.test.ts
describe('POST /api/series/{id}/restore', () => {
  it('initiates restore for all archived books in series');
  it('skips available books');
  it('returns results per book');
});
```

---

## Implementation Checklist

### Phase 0: On-Demand URL Generation — ✅ COMPLETE (PR #88, July 19, 2026)

- [x] Add `S3_ENABLED` override to `isS3Enabled()` (unlocks local hybrid mode for all later phases)
- [x] Create `GET /api/books/{id}/stream` endpoint (with dev-mode local URL branch)
- [x] Update OpenAPI spec (`BookStreamResponse` schema) + regenerate TS/Swift types
- [x] Update web player to fetch stream URL on demand (`PlaybackClient`, with `audioUrl` fallback)
- [x] Add `APIClient.getBookStream(bookId:)` + update `AudioPlayerManager` (iOS)
- [x] Add tests for stream endpoint (`__tests__/api/books/stream.test.ts`)
- [ ] **Rollout step 3 — deliberately deferred**: null `audioUrl` in `transformBook()` only after ALL installed iOS builds use the stream endpoint (an old build still streams from `book.audioUrl`)
- [x] Test playback on web and iOS (dev + production — E2E smoke exercises the play flow)

### Phase 1: Database Schema — ✅ COMPLETE (July 19, 2026, with Phase 2)

- [x] Prisma migration: `media_restore_requests` (nullable `requestedByUserId`, SetNull)
- [x] Prisma migration: `user_device_tokens`
- [x] Add `audioAvailability` + `availabilityCheckedAt` to `Book`
- [x] Add relations to `User` and `Book` models
- [x] Run migration (`20260719183757_restore_workflow_schema`)

### Phase 2: Backend API — ✅ COMPLETE (July 19, 2026; device-token endpoints moved to Phase 6)

- [x] Add `aws-sdk-client-mock` dev dependency
- [x] Create `lib/restore.ts`: `initiateRestore()` (no `Days`!), `parseRestoreHeader()`, `getArchiveState()`, `estimatedCompletion()`, `setBookAvailability()`
- [x] `RESTORE_TIER` env override in `initiateRestore()` (Expedited for fast pipeline testing)
- [x] Extend stream endpoint with HeadObject `ArchiveStatus` detection (202 + self-heal)
- [x] Create `POST /api/books/{id}/restore`
- [x] Create `GET /api/books/{id}/restore-status`
- [x] Create `GET /api/books/restores`
- [x] Update `POST /api/downloads/{bookId}` with archive detection (202; HeadObject now precedes presigning)
- [x] Verify chapters endpoint degrades gracefully for archived files (verified: 200 + empty chapters, no 500)
- [ ] ~~Create `POST`/`DELETE /api/notifications/register`~~ — **moved to Phase 6**: the endpoint's core is `NotificationService.registerEndpoint` (SNS), which is Phase 6 work; shipping a half-wired registration route earlier serves nothing (no client calls it until Phase 7)
- [x] Update OpenAPI spec (all new endpoints + `RestoreStatus`/`RestoreRequestSummary`/`RestoresListResponse` schemas) + regenerate TS + Swift types
- [ ] **⚠️ IAM (deploy prerequisite)**: add `s3:RestoreObject` on `arn:aws:s3:::book-vault-media/*` to the `book-vault-ecs-task` role (e.g. inline policy `S3RestoreAccess`). The role currently has only GetObject/ListBucket — production restores would get AccessDenied. HeadObject is already covered by GetObject.

### Phase 3: Book Availability Status — ✅ COMPLETE (July 19, 2026, with Phase 4)

- [x] Add required `archiveStatus` to OpenAPI Book schema (enum available|archived|restoring)
- [x] Update `transformBook()` — derive from `audioAvailability` via ARCHIVE_STATUS_MAP, zero extra queries
- [x] Regenerate TS + Swift models (Book/LibraryBook now carry archiveStatus)
- [x] Contract tests pass (added archiveStatus to the strict-field-check Book map + the zod schema)

### Phase 4: Web Frontend — ✅ COMPLETE (July 19, 2026)

- [x] Create `ArchiveStatusBadge` component (compact overlay + full label; `dark:` variants)
- [x] Update `BookCard` with archive badge overlay
- [x] Update book detail page with restore/restoring/play states (`RestoreButton` / `RestoringIndicator` / Play)
- [x] Handle 202 from `/stream` inside the player (PlaybackClient shows a restoring state)
- [x] Create `RestoringIndicator` with 30s polling (router.refresh on completion)
- [x] Create `/library/restores` page (active + last-7-days, auto-refresh while active)
- [x] Test full web flow (E2E smoke exercises play; component tests for badge/restore button/transform)

**Also folded in from the July 19 architecture review (D-5):** root `error.tsx` /
`loading.tsx` / `not-found.tsx` boundaries, and `dark:` variants on the AudioPlayer
(it previously had none). Restore UI shipped dark-mode-aware from the start.

**E2E note:** Next 16's dev server uses Turbopack; a cold first-compile can push
client-hydration-gated assertions past the old 10s expect timeout (the add itself
returns 201 in ~55ms — dev warmup, not app latency). Bumped the Playwright expect
timeout to 15s; verified green cold (`.next` deleted) and warm.

### Phase 5: Background Jobs — ⚙️ CODE COMPLETE (July 19, 2026); infra pending

- [x] Create `sync-availability` (lib + `scripts/sync-availability.ts` + `/api/cron/sync-availability`)
- [x] Create `poll-restore-status` (lib + script + `/api/cron/poll-restores`; completion = `ArchiveStatus` absent)
- [x] Stuck-restore failure handling (24h threshold → status failed, book back to ARCHIVED)
- [x] Cron routes guarded by `CRON_SECRET` bearer (fail-closed if unset); excluded from OpenAPI coverage
- [x] Tests: poller + sync (aws-sdk-client-mock) + cron auth (16 tests)
- [x] **DEPLOY/INFRA** — ✅ DONE July 20, 2026 (see "Deployed Infrastructure" section):
      `CRON_SECRET` in Secrets Manager; task def `:6`; classic EventBridge Rules
      (poller `rate(5 minutes)`, sync `cron(0 8 * * ? *)` UTC); first sync ran →
      **695/764 archived (~91%)**; scheduled poller firing verified end-to-end.
- [x] Notification on completion — Phase 6 backend now wired (real
      `NotificationService`; self-guards / no-ops until push ARNs are configured).

### Phase 6 — split: backend ✅ DONE (#110, July 20, 2026) / AWS+Apple setup deferred

**Backend (done, testable without artifacts):**

- [x] `@aws-sdk/client-sns`; `lib/notification-service.ts` (`registerEndpoint` w/
      InvalidParameter ARN-recovery + re-enable; `sendRestoreComplete` w/
      EndpointDisabled handling; `isPushEnabled` self-guard)
- [x] `POST`/`DELETE /api/notifications/register` (device-token upsert/deactivate)
- [x] Wire notification sending into the restore poller (replaced the Phase-5 stub)
- [x] Tests (aws-sdk-client-mock): service + route + poller-notifies

**AWS + Apple setup (DEFERRED — needs your artifacts + a device):**

- [ ] Create APNs key (`.p8`) in Apple Developer Portal
- [ ] `aws sns create-platform-application` for APNS + APNS_SANDBOX
- [ ] Set `AWS_SNS_PLATFORM_APPLICATION_ARN[_SANDBOX]` in task env; extend ECS
      **task role** IAM (`sns:CreatePlatformEndpoint`, `SetEndpointAttributes`, `Publish`)
- [ ] Verify push delivery via SNS console, then on a real device

### Phase 7 — split into 7a (archive/restore UI) and 7b (push + deep-link)

**Phase 7a — iOS archive/restore UI (simulator-testable, no device):**

- [ ] `archiveStatus` in Swift Book model ✅ already present (OpenAPI regen); make
      `execute<T>` 202-aware so restoring is distinguishable from 200
- [ ] Add `restoreBook` / `getBookRestoreStatus` / `listRestores` to `APIClient`
      (+ `APIClientProtocol` + `MockAPIClient`)
- [ ] First-class restore/availability state in `AudioPlayerManager` (today
      `.restoring` is swallowed as a generic 409 error)
- [ ] Handle 202 in `DownloadManager` (current `GenerateDownloadUrl200Response`
      can't decode it)
- [ ] Archive badge on the shared `BookGridItem` (propagates to 5 list surfaces)
- [ ] Restore/restoring/play CTA in `BookDetailView`

**Phase 7b — push registration + deep-linking (simctl-testable, no device):**

- [ ] Push-notification entitlement (`project.yml` + `xcodegen generate`)
- [ ] `AppDelegate` APNs registration (extend the existing background-download AppDelegate)
- [ ] `NotificationRegistrar` → `POST /api/notifications/register`
- [ ] `DeepLinkManager` for notification taps (book detail); iterate via `xcrun simctl push`
- [ ] **Device (DEFERRED):** real APNs registration + delivery on a physical device

### Phase 8: Series-Level Restore (2-3 hours)

- [ ] Create `POST /api/series/{id}/restore` endpoint
- [ ] Update OpenAPI spec
- [ ] "Restore All Archived" button on web series page
- [ ] Same on iOS series view
- [ ] Batched notifications for same-cycle series completions
- [ ] Test with a real multi-book archived series

### Post-Implementation

- [ ] Add CloudWatch metrics for restore requests
- [ ] Monitor SNS delivery success rate
- [ ] Document user-facing restore behavior
- [ ] Update CLAUDE.md with new patterns (restore helpers, availability column)

---

## Future Enhancements

1. **Proactive Restore**: If user adds an archived book to "Want to Listen" list, auto-initiate restore
2. **Expedited Restore**: Paid option (~$0.03/GB) for minutes-fast restores via `GlacierJobParameters.Tier: 'Expedited'`
3. **Smart Notifications**: Batch series notifications ("3 books from Mistborn are ready")
4. **Web Push**: Extend notification support to browsers via Web Push API
5. **Restore History**: Analytics page showing restore patterns and frequency
6. **S3 Inventory Integration**: Replace the nightly HeadObject sweep with S3 Inventory reports (only worth it at much larger library sizes)

---

## Related Documents

- [docs/archive/s3-archive-restore-workflow.md](../archive/s3-archive-restore-workflow.md) - Original v1 plan (superseded)
- [media-configuration.md](../media-configuration.md) - S3 and media handling
- [API_SECURITY.md](../API_SECURITY.md) - Authentication patterns
- [mobile/architecture.md](../mobile/architecture.md) - iOS app architecture
- [data-validation-layers.md](../data-validation-layers.md) - OpenAPI-first workflow
