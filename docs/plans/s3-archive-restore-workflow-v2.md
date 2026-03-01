# S3 Archive Restore Workflow - Updated Implementation Plan

> **Created**: January 2, 2026
> **Updated**: March 1, 2026
> **Status**: Planned (not yet implemented)
> **Priority**: High (next major feature)
> **Dependencies**: S3 Intelligent-Tiering with Archive tiers enabled
> **⚠️ PREREQUISITE**: Requires refactoring to on-demand URL generation (Phase 0)

---

## Overview

When S3 Intelligent-Tiering moves audiobook audio files to Archive Access tier (after 90 days of no access), they become temporarily unavailable for streaming. This plan covers the full restore pipeline:

1. Detect archived books and surface availability status across all UIs
2. Let users request restores (single book or full series)
3. Background polling to detect restore completion
4. Push notifications via AWS SNS + APNs when books are ready
5. Graceful UX on both web and iOS

**Only audio files (> 5MB) are subject to archiving.** Cover images, metadata, and cue files remain in S3 Standard permanently — browsing always works instantly.

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
Books show archive status badge (cached from nightly job)
  ↓
User taps "Play" on archived book
  ↓
Client calls GET /api/books/{id}/stream
  ↓
API calls S3 HeadObject → detects ARCHIVE_ACCESS tier
  ↓
API creates restore request in DB + calls S3 RestoreObject
  ↓
Returns 202 { status: 'restoring', estimatedCompletion: '...' }
  ↓
Client shows "Restoring... ~3-5 hours" UI
  ↓
Background job polls S3 every 5 minutes for in-progress restores
  ↓
Restore completes:
  1. Update DB: status → 'available'
  2. Look up user's device tokens
  3. Send push notification via AWS SNS → APNs
  ↓
iOS receives push: "Your audiobook is ready to play!"
  ↓
User taps notification → deep links to book detail → Play button active
```

### New Components

| Component                             | Purpose                                           |
| ------------------------------------- | ------------------------------------------------- |
| `media_restore_requests` table        | Track restore state per file                      |
| `user_device_tokens` table            | Store APNs device tokens + SNS endpoints          |
| `s3_storage_class` column on `books`  | Cached archive status for list views              |
| `GET /api/books/{id}/stream`          | On-demand URL generation + archive detection      |
| `GET /api/books/{id}/restore-status`  | Poll restore progress                             |
| `POST /api/books/{id}/restore`        | Explicitly request a restore                      |
| `POST /api/books/{id}/restore-series` | Restore all archived books in a series            |
| `GET /api/books/restores`             | List active restore requests                      |
| `POST /api/notifications/register`    | Register iOS device token                         |
| `DELETE /api/notifications/register`  | Unregister device token                           |
| Background: `poll-restore-status`     | Detect completed restores + trigger notifications |
| Background: `sync-storage-classes`    | Nightly job to cache archive status               |
| `NotificationService`                 | Server-side SNS integration                       |
| iOS `RestoreManager`                  | Restore state + polling on client                 |
| iOS push notification handling        | APNs registration, deep linking                   |

---

## Phase 0: On-Demand URL Generation (Prerequisite)

**⚠️ Must be completed before any restore functionality**

**Time estimate**: 4-6 hours

### Problem

Currently, `transformBook()` eagerly generates presigned S3 URLs for every book in list responses. This means:

- 100+ presigned URLs generated per `/api/books` request
- Can't check storage class before generating URLs
- Unnecessary S3 API calls and cost
- URLs in list responses that expire unused

### Solution

Move presigned URL generation to a dedicated stream endpoint called only when a user actually plays or downloads a book.

### Changes

**New endpoint**: `GET /api/books/{id}/stream`

```typescript
// app/api/books/[id]/stream/route.ts
export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;
  if (!user) return new Response('Unauthorized', { status: 401 });

  const book = await prisma.book.findUnique({
    where: { id: params.id },
    select: { audioUrl: true },
  });

  if (!book?.audioUrl) return new Response('Book not found', { status: 404 });

  const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);
  return Response.json({
    streamUrl,
    expiresAt: new Date(Date.now() + 3600 * 1000).toISOString(),
  });
}
```

**Update `transformBook()`**: Remove `audioUrl` presigned URL generation. Return `audioUrl: null` in list responses. Keep `coverUrl` generation as-is (covers are never archived).

**Update clients**:

- Web `AudioPlayer`: Fetch `/api/books/{id}/stream` when user clicks Play
- iOS `AudioPlayerManager`: Add `APIClient.getBookStreamUrl(bookId:)` method, call before playback

### OpenAPI Spec Addition

```yaml
/api/books/{id}/stream:
  get:
    operationId: getBookStream
    tags: [Media]
    summary: Get on-demand streaming URL for a book
    description: |
      Generates a presigned S3 URL for audio playback.
      Returns 202 if the file is archived and a restore has been initiated.
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
              type: object
              required: [streamUrl, expiresAt]
              properties:
                streamUrl:
                  type: string
                  format: uri
                expiresAt:
                  type: string
                  format: date-time
      '202':
        description: File is archived, restore initiated
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/RestoreStatus'
      '401':
        description: Unauthorized
      '404':
        description: Book not found
```

### Success Metrics

- `/api/books` responses no longer include presigned audio URLs
- S3 API calls reduced by ~99%
- Playback still works on web and iOS
- URLs only generated when user clicks play/download

---

## Phase 1: Database Schema

**Time estimate**: 1-2 hours

### New Table: `media_restore_requests`

```prisma
model MediaRestoreRequest {
  id                      String    @id @default(uuid())
  bookId                  String    @map("book_id")
  s3Key                   String    @map("s3_key")
  storageClass            String    @map("storage_class") // ARCHIVE_ACCESS or DEEP_ARCHIVE_ACCESS

  status                  String    @default("pending") // pending, in_progress, available, expired, failed
  restoreTier             String    @default("Standard") @map("restore_tier") // Standard (3-5h) or Expedited (1-5min)
  daysAvailable           Int       @default(1) @map("days_available")

  requestedAt             DateTime  @default(now()) @map("requested_at")
  restoreStartedAt        DateTime? @map("restore_started_at")
  availableAt             DateTime? @map("available_at")
  expiresAt               DateTime? @map("expires_at")

  requestedByUserId       String    @map("requested_by_user_id")
  estimatedCompletionTime DateTime? @map("estimated_completion_time")
  lastCheckedAt           DateTime? @map("last_checked_at")
  errorMessage            String?   @map("error_message")

  book                    Book      @relation(fields: [bookId], references: [id], onDelete: Cascade)
  requestedBy             User      @relation(fields: [requestedByUserId], references: [id], onDelete: SetNull)

  @@index([status, lastCheckedAt])
  @@index([bookId])
  @@index([requestedByUserId])
  @@map("media_restore_requests")
}
```

### New Table: `user_device_tokens`

```prisma
model UserDeviceToken {
  id              String    @id @default(uuid())
  userId          String    @map("user_id")
  deviceToken     String    @map("device_token")
  platform        String    @default("ios") // ios, web (future)
  snsEndpointArn  String?   @map("sns_endpoint_arn")
  isActive        Boolean   @default(true) @map("is_active")
  createdAt       DateTime  @default(now()) @map("created_at")
  updatedAt       DateTime  @updatedAt @map("updated_at")

  user            User      @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, deviceToken])
  @@index([userId])
  @@map("user_device_tokens")
}
```

### Update `Book` Model

Add cached storage class to avoid per-request HeadObject calls on list views:

```prisma
model Book {
  // ... existing fields ...

  audioStorageClass  String   @default("STANDARD") @map("audio_storage_class")
  storageClassCheckedAt DateTime? @map("storage_class_checked_at")

  // ... existing relations ...
  restoreRequests  MediaRestoreRequest[]
}
```

### Update `User` Model

```prisma
model User {
  // ... existing fields and relations ...
  deviceTokens     UserDeviceToken[]
  restoreRequests  MediaRestoreRequest[]
}
```

---

## Phase 2: Backend API

**Time estimate**: 3-4 hours

### 2.1 Update Stream Endpoint for Archive Detection

Extend the Phase 0 stream endpoint to check storage class:

```typescript
// app/api/books/[id]/stream/route.ts
export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // ... auth check ...

  const book = await prisma.book.findUnique({
    where: { id: params.id },
    select: { id: true, audioUrl: true, audioStorageClass: true },
  });

  if (!book?.audioUrl) return new Response('Not found', { status: 404 });

  // Fast path: cached storage class says it's available
  if (book.audioStorageClass === 'STANDARD' || book.audioStorageClass === 'FREQUENT_ACCESS') {
    const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);
    return Response.json({ streamUrl, expiresAt: new Date(Date.now() + 3600_000).toISOString() });
  }

  // Slow path: check S3 directly for archived/restoring files
  const headResult = await s3Client.send(
    new HeadObjectCommand({ Bucket: S3_BUCKET, Key: book.audioUrl })
  );

  // Parse restore header if present
  if (headResult.Restore) {
    const restore = parseRestoreHeader(headResult.Restore);

    if (restore.ongoingRequest) {
      return Response.json(
        {
          status: 'restoring',
          message: 'This audiobook is being restored. It will be ready in 3-5 hours.',
          estimatedCompletion: restore.estimatedCompletion,
          bookId: book.id,
        },
        { status: 202 }
      );
    }

    if (restore.expiryDate && new Date(restore.expiryDate) > new Date()) {
      // Restored and available — generate URL
      await prisma.book.update({
        where: { id: book.id },
        data: { audioStorageClass: 'RESTORED' },
      });
      const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);
      return Response.json({ streamUrl, expiresAt: new Date(Date.now() + 3600_000).toISOString() });
    }
  }

  // File is archived — initiate restore
  try {
    const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);
    // If this succeeds, file is actually accessible
    await prisma.book.update({
      where: { id: book.id },
      data: { audioStorageClass: 'STANDARD', storageClassCheckedAt: new Date() },
    });
    return Response.json({ streamUrl, expiresAt: new Date(Date.now() + 3600_000).toISOString() });
  } catch (error: any) {
    if (error.Code === 'InvalidObjectState' || error.name === 'InvalidObjectState') {
      await initiateRestore(book, user.id);
      return Response.json(
        {
          status: 'restoring',
          message: 'This audiobook is being restored. It will be ready in 3-5 hours.',
          bookId: book.id,
          estimatedCompletion: new Date(Date.now() + 5 * 3600_000).toISOString(),
        },
        { status: 202 }
      );
    }
    throw error;
  }
}
```

### 2.2 Restore Status Endpoint

```typescript
// app/api/books/[id]/restore-status/route.ts
export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  // ... auth check ...

  const restoreRequest = await prisma.mediaRestoreRequest.findFirst({
    where: {
      bookId: params.id,
      status: { in: ['pending', 'in_progress', 'available'] },
    },
    orderBy: { requestedAt: 'desc' },
  });

  if (!restoreRequest) {
    return Response.json({ status: 'not_needed' });
  }

  return Response.json({
    status: restoreRequest.status,
    estimatedCompletion: restoreRequest.estimatedCompletionTime,
    requestedAt: restoreRequest.requestedAt,
    availableAt: restoreRequest.availableAt,
    expiresAt: restoreRequest.expiresAt,
  });
}
```

### 2.3 Active Restores List

```typescript
// app/api/books/restores/route.ts
export async function GET(request: NextRequest) {
  // ... auth check ...

  const restores = await prisma.mediaRestoreRequest.findMany({
    where: {
      requestedByUserId: user.id,
      status: { in: ['pending', 'in_progress', 'available'] },
    },
    include: {
      book: {
        select: { id: true, title: true, coverUrl: true, audioStorageClass: true },
      },
    },
    orderBy: { requestedAt: 'desc' },
  });

  return Response.json({ restores });
}
```

### 2.4 Device Token Registration

```typescript
// app/api/notifications/register/route.ts
export async function POST(request: NextRequest) {
  // ... auth check ...

  const { deviceToken, platform } = await request.json();

  if (!deviceToken || typeof deviceToken !== 'string') {
    return Response.json({ error: 'deviceToken is required' }, { status: 400 });
  }

  // Create or update SNS platform endpoint
  const snsEndpointArn = await createSNSEndpoint(deviceToken, platform);

  await prisma.userDeviceToken.upsert({
    where: {
      userId_deviceToken: { userId: user.id, deviceToken },
    },
    create: {
      userId: user.id,
      deviceToken,
      platform: platform || 'ios',
      snsEndpointArn,
      isActive: true,
    },
    update: {
      snsEndpointArn,
      isActive: true,
      updatedAt: new Date(),
    },
  });

  return Response.json({ success: true });
}

export async function DELETE(request: NextRequest) {
  // ... auth check ...
  const { deviceToken } = await request.json();

  await prisma.userDeviceToken.updateMany({
    where: { userId: user.id, deviceToken },
    data: { isActive: false },
  });

  return Response.json({ success: true });
}
```

---

## Phase 3: Book Availability Status

**Time estimate**: 2-3 hours

### Problem

Users have no way to know a book is archived until they try to play it. We need archive status visible throughout the UI — in book grids, detail pages, and search results.

### Solution: Cached `audioStorageClass` on Book

The `audioStorageClass` column (added in Phase 1) is the source of truth for list views. A nightly background job syncs this by calling HeadObject on all books. The stream endpoint does a real-time check as a fallback.

### Storage Class Values

| Value                 | Meaning                                            | UI Treatment                         |
| --------------------- | -------------------------------------------------- | ------------------------------------ |
| `STANDARD`            | Immediately available                              | Normal play button                   |
| `FREQUENT_ACCESS`     | Immediately available                              | Normal play button                   |
| `INFREQUENT_ACCESS`   | Immediately available (slightly slower first byte) | Normal play button                   |
| `ARCHIVE_ACCESS`      | Archived, 3-5 hour restore                         | Archive badge + "Request" button     |
| `DEEP_ARCHIVE_ACCESS` | Deep archived, 12+ hour restore                    | Archive badge + "Request" button     |
| `RESTORING`           | Restore in progress                                | Restoring badge + progress indicator |
| `RESTORED`            | Temporarily available after restore                | Normal play button + "expires" note  |

### API Response Changes

Add `archiveStatus` to the Book schema in OpenAPI:

```yaml
Book:
  type: object
  properties:
    # ... existing properties ...
    archiveStatus:
      type: string
      enum: [available, archived, restoring, restored_expiring]
      description: |
        Availability status of the audio file:
        - available: Ready to stream immediately
        - archived: In S3 Glacier, requires 3-5 hour restore
        - restoring: Restore in progress
        - restored_expiring: Temporarily available, will re-archive
```

### Update `transformBook()`

```typescript
export async function transformBook(book: BookWithIncludes) {
  // ... existing transform logic ...

  // Derive archive status from cached storage class
  let archiveStatus: 'available' | 'archived' | 'restoring' | 'restored_expiring' = 'available';

  const sc = book.audioStorageClass;
  if (sc === 'ARCHIVE_ACCESS' || sc === 'DEEP_ARCHIVE_ACCESS') {
    // Check if there's an active restore request
    const activeRestore = await prisma.mediaRestoreRequest.findFirst({
      where: { bookId: book.id, status: { in: ['pending', 'in_progress'] } },
    });
    archiveStatus = activeRestore ? 'restoring' : 'archived';
  } else if (sc === 'RESTORED') {
    archiveStatus = 'restored_expiring';
  }

  return {
    // ... existing fields ...
    archiveStatus,
  };
}
```

> **Performance note**: The restore request lookup adds a DB query per book. For list views, consider a batch approach — query all active restores for the page of books in one query, then map by bookId.

### Nightly Storage Class Sync Job

```typescript
// scripts/sync-storage-classes.ts
async function syncStorageClasses() {
  const books = await prisma.book.findMany({
    where: { audioUrl: { not: null } },
    select: { id: true, audioUrl: true, audioStorageClass: true },
  });

  for (const book of books) {
    try {
      const head = await s3Client.send(
        new HeadObjectCommand({ Bucket: S3_BUCKET, Key: book.audioUrl! })
      );

      // S3 Intelligent-Tiering doesn't expose the exact tier via StorageClass.
      // StorageClass will be 'INTELLIGENT_TIERING'. The actual access tier
      // is only detectable via the Restore header or by attempting access.
      // For now, mark as STANDARD unless we know otherwise from restore history.
      const storageClass = head.StorageClass || 'STANDARD';

      await prisma.book.update({
        where: { id: book.id },
        data: {
          audioStorageClass: storageClass,
          storageClassCheckedAt: new Date(),
        },
      });
    } catch (error: any) {
      if (error.name === 'InvalidObjectState') {
        await prisma.book.update({
          where: { id: book.id },
          data: { audioStorageClass: 'ARCHIVE_ACCESS', storageClassCheckedAt: new Date() },
        });
      }
      // Log and continue — don't fail the whole job for one book
      console.error(`Failed to check storage class for book ${book.id}:`, error);
    }
  }
}
```

> **Important S3 Intelligent-Tiering caveat**: S3 returns `StorageClass: INTELLIGENT_TIERING` for all objects in an IT bucket — it doesn't tell you which tier (Frequent, Infrequent, Archive) the object is in. The actual tier is only discoverable by attempting to access the object and catching `InvalidObjectState`. The nightly job should attempt a HeadObject + small range request to detect this. Alternatively, S3 Storage Lens or S3 Inventory can provide tier-level reporting on a schedule.

---

## Phase 4: Web Frontend

**Time estimate**: 2-3 hours

### 4.1 Archive Status Badge

New component for book cards and detail views:

```typescript
// components/ArchiveStatusBadge.tsx
'use client';

interface ArchiveStatusBadgeProps {
  status: 'available' | 'archived' | 'restoring' | 'restored_expiring';
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
  // restored_expiring → clock icon + "Available for 24h"
}
```

### 4.2 Update BookCard

Show archive badge overlay on book cards in grids:

```tsx
// In BookCard component
<div className="relative">
  <Image src={coverUrl} ... />
  <ArchiveStatusBadge status={book.archiveStatus} compact />
</div>
```

### 4.3 Update Book Detail Page

Replace play button with restore button when archived:

```tsx
{book.archiveStatus === 'archived' ? (
  <RestoreButton bookId={book.id} />
) : book.archiveStatus === 'restoring' ? (
  <RestoringIndicator bookId={book.id} estimatedCompletion={...} />
) : (
  <PlayButton bookId={book.id} />
)}
```

### 4.4 Restoring Indicator with Polling

```typescript
// components/RestoringIndicator.tsx
'use client';

export function RestoringIndicator({ bookId, estimatedCompletion }: Props) {
  const [status, setStatus] = useState<string>('restoring');

  useEffect(() => {
    const interval = setInterval(async () => {
      const res = await fetch(`/api/books/${bookId}/restore-status`);
      const data = await res.json();
      setStatus(data.status);
      if (data.status === 'available' || data.status === 'not_needed') {
        clearInterval(interval);
        // Refresh page or update parent state
      }
    }, 30_000); // Poll every 30 seconds

    return () => clearInterval(interval);
  }, [bookId]);

  // Show spinner + ETA countdown
}
```

### 4.5 Restores List Page

New page at `/library/restores` showing all active and recent restore requests:

```
/library/restores
├── Active Restores (pending, in_progress)
│   └── BookCard + progress + ETA
└── Recently Restored (available, last 7 days)
    └── BookCard + "expires in X hours"
```

---

## Phase 5: Background Jobs

**Time estimate**: 2-3 hours

### 5.1 Restore Status Poller

Runs every 5 minutes. Checks S3 for all in-progress restores:

```typescript
// scripts/poll-restore-status.ts
import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';
import { prisma } from '@/lib/db';
import { NotificationService } from '@/lib/notification-service';

async function pollRestoreStatus() {
  const activeRestores = await prisma.mediaRestoreRequest.findMany({
    where: { status: { in: ['pending', 'in_progress'] } },
    include: {
      book: { select: { id: true, title: true, audioUrl: true } },
      requestedBy: { select: { id: true } },
    },
  });

  console.log(`Checking ${activeRestores.length} active restores...`);

  for (const restore of activeRestores) {
    try {
      const head = await s3Client.send(
        new HeadObjectCommand({ Bucket: S3_BUCKET, Key: restore.s3Key })
      );

      if (!head.Restore) continue;

      const parsed = parseRestoreHeader(head.Restore);

      if (!parsed.ongoingRequest && parsed.expiryDate) {
        // Restore complete!
        console.log(`✅ Restore complete: ${restore.book.title}`);

        await prisma.$transaction([
          prisma.mediaRestoreRequest.update({
            where: { id: restore.id },
            data: {
              status: 'available',
              availableAt: new Date(),
              expiresAt: new Date(parsed.expiryDate),
            },
          }),
          prisma.book.update({
            where: { id: restore.bookId },
            data: { audioStorageClass: 'RESTORED' },
          }),
        ]);

        // Send push notification
        await NotificationService.sendRestoreComplete(
          restore.requestedByUserId,
          restore.book.id,
          restore.book.title
        );
      }

      await prisma.mediaRestoreRequest.update({
        where: { id: restore.id },
        data: { lastCheckedAt: new Date() },
      });
    } catch (error) {
      console.error(`Error checking restore ${restore.id}:`, error);

      // Mark as failed if stuck for > 24 hours
      if (
        restore.restoreStartedAt &&
        Date.now() - restore.restoreStartedAt.getTime() > 24 * 3600_000
      ) {
        await prisma.mediaRestoreRequest.update({
          where: { id: restore.id },
          data: { status: 'failed', errorMessage: String(error) },
        });
      }
    }
  }
}
```

### 5.2 Deployment Options

**Option A: Cron API route (simplest for ECS)**

```typescript
// app/api/cron/poll-restores/route.ts
export async function GET(req: Request) {
  const authHeader = req.headers.get('authorization');
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }
  await pollRestoreStatus();
  return Response.json({ success: true, checkedAt: new Date() });
}
```

Then use an external cron service, CloudWatch Events + Lambda, or a simple `crontab` on the ECS task to hit the endpoint every 5 minutes.

**Option B: ECS Scheduled Task**

Create a separate ECS task definition that runs the poller script on a schedule via CloudWatch Events. More operationally complex but cleaner separation.

**Recommendation**: Option A — keep it simple. You're running a single ECS task already; adding a cron hit to an API route is the lowest-effort approach.

### 5.3 Nightly Storage Class Sync

Separate cron job (once daily, e.g., 3 AM):

```bash
# Cron hits this endpoint nightly
GET /api/cron/sync-storage-classes
Authorization: Bearer ${CRON_SECRET}
```

This updates `audioStorageClass` on all books so browse views show accurate archive badges without real-time S3 calls.

---

## Phase 6: iOS Push Notifications (AWS SNS + APNs)

**Time estimate**: 4-5 hours

This is the most significant new addition to the plan. The full pipeline:

```
iOS app launch
  → Register with APNs → receive device token
  → POST /api/notifications/register { deviceToken }
  → Backend creates AWS SNS Platform Endpoint
  → Store endpoint ARN + device token in DB

Restore completes (detected by poller)
  → NotificationService.sendRestoreComplete(userId, bookId, title)
  → Look up user's active device tokens
  → For each: SNS.publish() with APNs payload
  → iOS receives push notification
  → User taps → deep link to book detail
```

### 6.1 AWS Setup (One-Time)

**a) Create APNs key in Apple Developer Portal:**

1. Go to Certificates, Identifiers & Profiles → Keys
2. Create a new key with "Apple Push Notifications service (APNs)" enabled
3. Download the `.p8` file — you'll need Key ID and Team ID

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

> **Note**: Use `APNS` for production, `APNS_SANDBOX` for development. You may want both during testing. Store the returned Platform Application ARN in environment variables.

**c) Environment variables:**

```env
# .env
AWS_SNS_PLATFORM_APPLICATION_ARN=arn:aws:sns:us-east-1:XXXX:app/APNS/book-vault-ios
AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX=arn:aws:sns:us-east-1:XXXX:app/APNS_SANDBOX/book-vault-ios
```

### 6.2 Backend NotificationService

```typescript
// lib/notification-service.ts
import { SNSClient, PublishCommand, CreatePlatformEndpointCommand } from '@aws-sdk/client-sns';
import { prisma } from './db';

const snsClient = new SNSClient({ region: 'us-east-1' });

export class NotificationService {
  /**
   * Create an SNS platform endpoint for a device token.
   * Returns the endpoint ARN for future publishes.
   */
  static async createSNSEndpoint(deviceToken: string, platform: string): Promise<string> {
    const platformAppArn =
      process.env.NODE_ENV === 'production'
        ? process.env.AWS_SNS_PLATFORM_APPLICATION_ARN
        : process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX;

    const result = await snsClient.send(
      new CreatePlatformEndpointCommand({
        PlatformApplicationArn: platformAppArn,
        Token: deviceToken,
      })
    );

    return result.EndpointArn!;
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
            'content-available': 1,
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
        // Handle disabled/invalid endpoints
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

APNs device tokens can change. The iOS app should re-register on every launch, and the backend should handle this via upsert (already implemented in the register endpoint above). SNS also handles token updates via `CreatePlatformEndpoint` — if the token already exists, it returns the existing endpoint ARN.

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

    // Handle notification tap (foreground)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let bookId = userInfo["bookId"] as? String,
           let action = userInfo["action"] as? String,
           action == "restore_complete" {
            // Deep link to book detail
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

**BookDetailView** — swap play button based on `archiveStatus`:

```swift
// In BookDetailView
switch book.archiveStatus {
case .archived:
    RestoreRequestButton(bookId: book.id)
case .restoring:
    RestoringProgressView(bookId: book.id, estimatedCompletion: ...)
case .restoredExpiring:
    PlayButton(bookId: book.id)
    Text("Available for 24 hours").font(.caption).foregroundColor(.secondary)
default:
    PlayButton(bookId: book.id)
}
```

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

If a user wants to listen to a 15-book series and all are archived, they'd need to request restores one at a time — hitting the 3-5 hour wall 15 times. Series-level restore batch-initiates all archived books in a series.

### API Endpoint

```typescript
// app/api/series/[id]/restore/route.ts
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  // ... auth check ...

  // Find all archived books in the series
  const seriesBooks = await prisma.bookSeries.findMany({
    where: { seriesId: params.id },
    include: {
      book: {
        select: {
          id: true,
          title: true,
          audioUrl: true,
          audioStorageClass: true,
        },
      },
    },
    orderBy: { sequence: 'asc' },
  });

  const archivedBooks = seriesBooks.filter(
    (sb) =>
      sb.book.audioStorageClass === 'ARCHIVE_ACCESS' ||
      sb.book.audioStorageClass === 'DEEP_ARCHIVE_ACCESS'
  );

  if (archivedBooks.length === 0) {
    return Response.json({ message: 'No archived books in this series', restored: 0 });
  }

  // Initiate restore for each archived book
  const results = [];
  for (const sb of archivedBooks) {
    try {
      await initiateRestore(sb.book, user.id);
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

  return Response.json({
    message: `Restore initiated for ${results.filter((r) => r.status === 'initiated').length} books`,
    total: archivedBooks.length,
    results,
  });
}
```

### OpenAPI Spec

```yaml
/api/series/{id}/restore:
  post:
    operationId: restoreSeries
    tags: [Series, Restore]
    summary: Restore all archived books in a series
    description: |
      Initiates S3 restore for all archived books in the specified series.
      Returns status for each book.
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
                        enum: [initiated, failed, already_restoring]
```

### UI Integration

**Web**: Add "Restore All Archived" button on series detail page when any books are archived. Show count: "3 of 12 books are archived".

**iOS**: Same treatment on the series view. The button triggers a single API call, and individual book cards update as restores complete.

### Notification Behavior

When a series restore is in progress, the poller detects individual book completions. Each book triggers its own push notification. Consider batching: if multiple books in the same series complete within the same poll cycle, send a single notification: "3 books from [Series Name] are ready to play."

---

## Cost Analysis

### S3 Restore Costs

| Tier      | Restore Time | Cost per GB | Cost for 500MB book |
| --------- | ------------ | ----------- | ------------------- |
| Standard  | 3-5 hours    | $0.03       | $0.015              |
| Bulk      | 5-12 hours   | $0.0025     | $0.00125            |
| Expedited | 1-5 minutes  | $0.10       | $0.05               |

**Recommendation**: Standard tier. At your usage (~handful of restores/month), cost is negligible.

### Restored File Availability

Setting `Days: 1` means the file stays accessible for 24 hours post-restore. No additional charge for keeping restored copies for 1-30 days. After 24 hours, the file automatically returns to archive tier.

### AWS SNS Costs

| Component                 | Free Tier            | After Free Tier |
| ------------------------- | -------------------- | --------------- |
| Mobile push notifications | 1M/month (permanent) | $0.50 per 1M    |
| SNS API requests          | 1M/month (12 months) | $0.50 per 1M    |

**Your projected usage**: Single-digit notifications per month. **Effective cost: $0.00.**

### Total Monthly Cost Estimate

For a handful of users restoring ~5-10 books/month:

- S3 restores: ~$0.15 (10 × 500MB × $0.03/GB)
- SNS: $0.00
- Additional S3 HeadObject calls (nightly sync): ~$0.005 (691 books × $0.0000044/request × 30 days)
- **Total: ~$0.16/month**

---

## Testing Strategy

### Manual Testing

1. **Archive a test file**:

   ```bash
   aws s3api copy-object \
     --bucket book-vault-media \
     --copy-source book-vault-media/test-file.m4b \
     --key test-file.m4b \
     --storage-class GLACIER \
     --profile book_vault
   ```

2. **Test the full flow**: Try to play → see restore UI → wait for restore → receive notification → play

3. **Test push notifications**: Use SNS console to send a test push to a registered device token

4. **Test series restore**: Archive 2-3 books from a series → trigger series restore → verify all complete

### Automated Tests

```typescript
// __tests__/api/books/stream.test.ts
describe('GET /api/books/{id}/stream', () => {
  it('returns 200 with streamUrl for available books');
  it('returns 202 with restore status for archived books');
  it('returns 401 for unauthenticated requests');
  it('returns 404 for non-existent books');
  it('handles concurrent restore requests for same book (dedup)');
});

// __tests__/api/books/restore-status.test.ts
describe('GET /api/books/{id}/restore-status', () => {
  it('returns not_needed when no active restore');
  it('returns in_progress with ETA for active restore');
  it('returns available with expiry for completed restore');
});

// __tests__/api/notifications/register.test.ts
describe('POST /api/notifications/register', () => {
  it('registers a new device token');
  it('updates existing token (upsert)');
  it('handles invalid token gracefully');
});

// __tests__/api/series/restore.test.ts
describe('POST /api/series/{id}/restore', () => {
  it('initiates restore for all archived books in series');
  it('skips already-available books');
  it('returns results per book');
});
```

---

## Implementation Checklist

### Phase 0: On-Demand URL Generation (4-6 hours)

- [ ] Create `GET /api/books/{id}/stream` endpoint
- [ ] Update `transformBook()` to remove presigned audio URL generation
- [ ] Add `APIClient.getBookStreamUrl()` method (iOS)
- [ ] Update `AudioPlayerManager` to fetch URLs on-demand (iOS)
- [ ] Update `AudioPlayer` component to fetch URLs on-demand (Web)
- [ ] Update OpenAPI spec with stream endpoint
- [ ] Regenerate TypeScript + Swift types
- [ ] Add tests for stream endpoint
- [ ] Verify S3 API call reduction (CloudWatch)
- [ ] Test playback on web and iOS

### Phase 1: Database Schema (1-2 hours)

- [ ] Create Prisma migration for `media_restore_requests` table
- [ ] Create Prisma migration for `user_device_tokens` table
- [ ] Add `audioStorageClass` + `storageClassCheckedAt` to `Book` model
- [ ] Add relations to `User` and `Book` models
- [ ] Run migration, verify in Prisma Studio

### Phase 2: Backend API (3-4 hours)

- [ ] Update stream endpoint with archive detection logic
- [ ] Create `GET /api/books/{id}/restore-status` endpoint
- [ ] Create `GET /api/books/restores` endpoint
- [ ] Create `POST /api/notifications/register` endpoint
- [ ] Create `DELETE /api/notifications/register` endpoint
- [ ] Add `initiateRestore()` helper function
- [ ] Add `parseRestoreHeader()` helper function
- [ ] Update OpenAPI spec with all new endpoints
- [ ] Regenerate types

### Phase 3: Book Availability Status (2-3 hours)

- [ ] Add `archiveStatus` to OpenAPI Book schema
- [ ] Update `transformBook()` to include `archiveStatus`
- [ ] Create nightly `sync-storage-classes` script
- [ ] Set up cron for nightly sync
- [ ] Regenerate Swift models

### Phase 4: Web Frontend (2-3 hours)

- [ ] Create `ArchiveStatusBadge` component
- [ ] Update `BookCard` with archive badge
- [ ] Update book detail page with restore/restoring/play states
- [ ] Create `RestoringIndicator` with polling
- [ ] Create `/library/restores` page
- [ ] Test full web flow

### Phase 5: Background Jobs (2-3 hours)

- [ ] Create `poll-restore-status` script
- [ ] Create cron API route with auth
- [ ] Set up 5-minute polling schedule
- [ ] Add error handling and failure detection (24h timeout)
- [ ] Test with manually archived file

### Phase 6: iOS Push Notifications (4-5 hours)

- [ ] Create APNs key in Apple Developer Portal
- [ ] Create SNS Platform Application (APNS + APNS_SANDBOX)
- [ ] Add SNS ARN to environment variables / Secrets Manager
- [ ] Implement `NotificationService` on backend
- [ ] Implement `createSNSEndpoint()` helper
- [ ] Test push delivery via SNS console
- [ ] Wire notification sending into restore poller

### Phase 7: iOS App Updates (4-5 hours)

- [ ] Add push notification entitlement to Xcode project
- [ ] Implement `AppDelegate` with APNs registration
- [ ] Implement `NotificationRegistrar` service
- [ ] Implement `DeepLinkManager` for notification taps
- [ ] Add `archiveStatus` to Swift Book model (via OpenAPI regeneration)
- [ ] Update `BookDetailView` with restore/restoring states
- [ ] Add archive badge to book cards
- [ ] Test on physical device

### Phase 8: Series-Level Restore (2-3 hours)

- [ ] Create `POST /api/series/{id}/restore` endpoint
- [ ] Update OpenAPI spec
- [ ] Add "Restore Series" button to web series page
- [ ] Add "Restore Series" button to iOS series view
- [ ] Handle batched notifications for series restores
- [ ] Test with multi-book series

### Post-Implementation

- [ ] Add CloudWatch metrics for restore requests
- [ ] Monitor SNS delivery success rate
- [ ] Document user-facing restore behavior
- [ ] Update CLAUDE.md with new patterns

---

## Future Enhancements

1. **Proactive Restore**: If user adds an archived book to "Want to Listen" list, auto-initiate restore
2. **Expedited Restore**: Premium option — $0.10 per book for 1-5 minute restore
3. **Smart Notifications**: Batch series notifications ("3 books from Mistborn are ready")
4. **Web Push**: Extend notification support to browsers via Web Push API
5. **Restore History**: Analytics page showing restore patterns, costs, frequency
6. **S3 Inventory Integration**: Use S3 Inventory reports instead of HeadObject for storage class sync (cheaper at scale)

---

## Related Documents

- [aws-cost-optimization-plan.md](./aws-cost-optimization-plan.md) - S3 Intelligent-Tiering setup
- [media-configuration.md](./media-configuration.md) - S3 and media handling
- [API_SECURITY.md](./API_SECURITY.md) - Authentication patterns
- [mobile/architecture.md](./mobile/architecture.md) - iOS app architecture
- [data-validation-layers.md](./data-validation-layers.md) - OpenAPI-first workflow
