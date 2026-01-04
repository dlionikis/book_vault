# S3 Archive Restore Workflow Implementation Plan

> **Created**: January 2, 2026
> **Status**: Planned (not yet implemented)
> **Priority**: Medium (implement after cost optimization Phase 2)
> **Dependencies**: S3 Intelligent-Tiering with Archive tiers enabled
> **⚠️ PREREQUISITE**: Requires refactoring to on-demand URL generation (Phase 0 below)

---

## Overview

**Note**: Only audio files (> 5MB) are subject to archiving. Cover images, metadata JSON, and cue files remain in S3 Standard permanently, so browsing the library always works instantly.

When S3 Intelligent-Tiering moves audiobook audio files to Archive Access tier (after 90 days of no access), they become temporarily unavailable for streaming. Users will encounter `403 Forbidden` errors with `InvalidObjectState` if they try to play archived books.

This document outlines how to implement a graceful restore workflow that:

1. **Phase 0**: Refactor to on-demand presigned URL generation (prerequisite)
2. Detects when files are archived
3. Initiates restore operations automatically
4. Shows users restore progress
5. Notifies users when books are ready to play

---

## Table of Contents

1. [Current State vs Desired State](#current-state-vs-desired-state)
2. [Phase 0: Prerequisite Refactor](#phase-0-prerequisite-refactor---on-demand-url-generation)
3. [Problem Statement](#problem-statement)
4. [Architecture Overview](#architecture-overview)
5. [Database Schema Changes](#database-schema-changes)
6. [API Implementation](#api-implementation)
7. [Frontend Implementation](#frontend-implementation)
8. [iOS App Implementation](#ios-app-implementation)
9. [Background Jobs](#background-jobs)
10. [Testing Strategy](#testing-strategy)
11. [Cost Considerations](#cost-considerations)
12. [Implementation Checklist](#implementation-checklist)

---

## Current State vs Desired State

### How It Works Now ❌

**Presigned URLs are generated eagerly in book list responses:**

```typescript
// lib/book-transformer.ts
export async function transformBook(book: BookWithIncludes) {
  const [coverUrl, audioUrl] = await Promise.all([
    getCoverUrl(book.coverUrl), // Generates presigned URL
    getAudioUrl(book.audioUrl), // Generates presigned URL
  ]);

  return {
    id: book.id,
    audioUrl, // ⚠️ Presigned URL embedded in response
    // ...
  };
}
```

**Problems:**

- Generates 100+ presigned URLs for `/api/books` list requests
- URLs expire in 1 hour - wasted if user doesn't play
- Unnecessary S3 API calls (costs money, hits rate limits)
- Security: URLs exposed in list responses when not needed
- Archive handling impossible: can't check storage class before generating URL

### How It Should Work ✅

**Presigned URLs generated on-demand when needed:**

```typescript
// User clicks "Play" or "Download"
const response = await fetch(`/api/books/${bookId}/stream`);
const { streamUrl } = await response.json();

// Use fresh URL immediately
audioPlayer.src = streamUrl;
```

**Benefits:**

- ✅ Only generate URLs when actually needed (99% reduction in S3 calls)
- ✅ URLs generated right before use - no expiry issues
- ✅ Can check storage class and handle archives before generating URL
- ✅ Better security - URLs only exposed when needed
- ✅ Dramatically lower costs

---

## Phase 0: Prerequisite Refactor - On-Demand URL Generation

**⚠️ This must be implemented BEFORE archive restore functionality**

### Step 1: Create Stream Endpoint

**File**: `app/api/books/[id]/stream/route.ts`

```typescript
import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/app/api/auth/[...nextauth]/route';
import { prisma } from '@/lib/db';
import { generatePresignedUrl } from '@/lib/s3';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session?.user?.id) {
    return new Response('Unauthorized', { status: 401 });
  }

  try {
    const book = await prisma.book.findUnique({
      where: { id: params.id },
      select: { audioUrl: true },
    });

    if (!book || !book.audioUrl) {
      return new Response('Book not found', { status: 404 });
    }

    // Generate presigned URL on-demand
    const streamUrl = await generatePresignedUrl(book.audioUrl, 3600);

    return Response.json({
      streamUrl,
      expiresAt: new Date(Date.now() + 3600 * 1000).toISOString(),
    });
  } catch (error) {
    console.error('Error generating stream URL:', error);
    return new Response('Internal server error', { status: 500 });
  }
}
```

### Step 2: Update Book Transformer

**File**: `lib/book-transformer.ts`

```typescript
export async function transformBook(book: BookWithIncludes) {
  // Remove presigned URL generation - return S3 keys instead
  return {
    id: book.id,
    asin: book.asin,
    title: book.title,
    // ... other fields

    // Return null for URLs - clients fetch on-demand
    coverUrl: book.coverUrl ? `/api/books/${book.id}/cover` : null,
    audioUrl: null, // Client calls /api/books/[id]/stream when needed
  };
}
```

**Alternative**: Keep static cover URLs but make audio on-demand only.

### Step 3: Update iOS AudioPlayerManager

**File**: `ios/BookVault/Services/AudioPlayerManager.swift`

```swift
func play(book: Book) async {
    // Check if downloaded first
    guard !offlineStorage.hasBook(book.id) else {
        playLocalFile(book)
        return
    }

    // Fetch stream URL on-demand
    do {
        let streamUrl = try await apiClient.getBookStreamUrl(bookId: book.id)
        await playRemoteFile(streamUrl)
    } catch {
        DebugLogger.error("Failed to get stream URL: \(error)")
        showError("Unable to stream audiobook")
    }
}
```

### Step 4: Add APIClient Method

**File**: `ios/BookVault/Services/APIClient.swift`

```swift
func getBookStreamUrl(bookId: UUID) async throws -> String {
    let request = try createRequest(
        path: "/api/books/\(bookId.uuidString)/stream",
        method: "GET",
        requiresAuth: true
    )

    let response: BookStreamResponse = try await execute(request: request)
    return response.streamUrl
}

// Add to generated models or define locally
struct BookStreamResponse: Codable {
    let streamUrl: String
    let expiresAt: String
}
```

### Step 5: Update Web AudioPlayer

**File**: `components/AudioPlayer.tsx`

```typescript
const fetchStreamUrl = async (bookId: string): Promise<string> => {
  const response = await fetch(`/api/books/${bookId}/stream`);
  if (!response.ok) throw new Error('Failed to get stream URL');

  const { streamUrl } = await response.json();
  return streamUrl;
};

// Use in audio player
useEffect(() => {
  if (bookId && !isDownloaded) {
    fetchStreamUrl(bookId).then((url) => {
      audioRef.current.src = url;
      audioRef.current.load();
    });
  }
}, [bookId]);
```

### Step 6: Update OpenAPI Spec

**File**: `docs/api/openapi.yaml`

```yaml
/books/{id}/stream:
  get:
    summary: Get streaming URL for audiobook
    description: Returns a presigned S3 URL for streaming the audiobook
    security:
      - bearerAuth: []
    parameters:
      - in: path
        name: id
        required: true
        schema:
          type: string
          format: uuid
    responses:
      '200':
        description: Stream URL generated successfully
        content:
          application/json:
            schema:
              type: object
              properties:
                streamUrl:
                  type: string
                  format: uri
                  description: Presigned S3 URL valid for 1 hour
                expiresAt:
                  type: string
                  format: date-time
                  description: ISO 8601 timestamp when URL expires
      '401':
        description: Unauthorized
      '404':
        description: Book not found
```

### Step 7: Testing the Refactor

```typescript
// __tests__/api/books/stream.test.ts
describe('GET /api/books/[id]/stream', () => {
  it('should return stream URL for authenticated user', async () => {
    const response = await fetch(`/api/books/${bookId}/stream`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.streamUrl).toMatch(/^https:\/\/.+\.s3\..+\.amazonaws\.com/);
    expect(data.expiresAt).toBeDefined();
  });

  it('should return 401 for unauthenticated request', async () => {
    const response = await fetch(`/api/books/${bookId}/stream`);
    expect(response.status).toBe(401);
  });
});
```

---

## Problem Statement

### Current Behavior (After Phase 0 Refactor)

When a user tries to play an archived audiobook:

1. Frontend requests presigned URL from `/api/books/[id]/stream`
2. Backend generates presigned URL successfully (no error)
3. Audio player attempts to load the file from S3
4. S3 returns: `403 Forbidden - InvalidObjectState`
5. Audio player shows cryptic error, book appears broken

### Desired Behavior

1. System proactively checks storage class before generating URLs
2. If archived, initiate restore automatically
3. Show user: "This audiobook is being restored. It will be ready in 3-5 hours."
4. Poll restore status in background
5. Notify user when ready: "Your audiobook is ready to play!"
6. Book auto-plays or shows prominent "Play Now" button

---

## Architecture Overview

### High-Level Flow

```
User clicks "Play" on book (not downloaded locally)
  ↓
Client calls /api/books/[id]/stream
  ↓
API checks S3 storage class (HeadObject)
  ↓
If ARCHIVE_ACCESS or DEEP_ARCHIVE_ACCESS:
  ↓
  1. Create restore request in database
  2. Initiate S3 restore (RestoreObject API)
  3. Return 202 status with restore info
  ↓
Background job polls S3 restore status every 5 minutes
  ↓
When restored:
  ↓
  1. Update database: status = 'available'
  2. Send notification (optional: email/push)
  3. Keep available for N days (configurable)
  ↓
Client receives 200 with streamUrl
  ↓
User can now play the book
```

### Components Needed

1. **Database**: Track restore requests and status
2. **API Endpoints**: Check status, initiate restores
3. **Background Job**: Poll restore status
4. **Frontend**: Show restore UI, poll for updates
5. **iOS App**: Same as frontend
6. **Notifications** (optional): Email/push when ready

---

## Database Schema Changes

### New Table: `media_restore_requests`

```sql
CREATE TABLE media_restore_requests (
  id SERIAL PRIMARY KEY,

  -- Which media file needs restoration
  media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  s3_key TEXT NOT NULL, -- Full S3 key of the object
  storage_class TEXT NOT NULL, -- ARCHIVE_ACCESS or DEEP_ARCHIVE_ACCESS

  -- Restore request details
  status TEXT NOT NULL DEFAULT 'pending', -- pending, in_progress, available, expired, failed
  restore_tier TEXT NOT NULL DEFAULT 'Standard', -- Standard (3-5h) or Expedited (1-5min, $$)
  days_available INTEGER NOT NULL DEFAULT 1, -- How long to keep restored (1-30 days)

  -- Timestamps
  requested_at TIMESTAMP NOT NULL DEFAULT NOW(),
  restore_started_at TIMESTAMP, -- When S3 restore actually started
  available_at TIMESTAMP, -- When file became available
  expires_at TIMESTAMP, -- When restored copy expires

  -- User who requested (for notifications)
  requested_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,

  -- Metadata
  estimated_completion_time TIMESTAMP, -- Best guess when it'll be ready
  restore_expiry_date TEXT, -- From S3 Restore header
  last_checked_at TIMESTAMP, -- Last time we polled S3 status
  error_message TEXT, -- If restore failed

  -- Indexes
  UNIQUE(media_id, requested_at), -- Prevent duplicate requests
  INDEX idx_status_last_checked (status, last_checked_at) -- For background job
);
```

### Update `media` Table (Optional)

Add a cached storage class column for faster checks:

```sql
ALTER TABLE media
ADD COLUMN s3_storage_class TEXT DEFAULT 'STANDARD';

-- Update via background job daily or on-demand
```

---

## API Implementation

### 1. Check Storage Class Before Streaming

**Update**: `app/api/media/[id]/stream/route.ts`

```typescript
import { S3Client, HeadObjectCommand, RestoreObjectCommand } from '@aws-sdk/client-s3';

export async function GET(req: Request, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return new Response('Unauthorized', { status: 401 });
  }

  const media = await prisma.media.findUnique({
    where: { id: parseInt(params.id) },
  });

  if (!media) {
    return new Response('Not found', { status: 404 });
  }

  // Check storage class
  const s3Client = new S3Client({ region: 'us-east-1' });

  try {
    const headResult = await s3Client.send(
      new HeadObjectCommand({
        Bucket: process.env.AWS_S3_BUCKET!,
        Key: media.s3Key,
      })
    );

    const storageClass = headResult.StorageClass || 'STANDARD';

    // If archived, check restore status or initiate restore
    if (storageClass === 'INTELLIGENT_TIERING') {
      // Check if it's in archive tier
      const archiveTiers = ['ARCHIVE_ACCESS', 'DEEP_ARCHIVE_ACCESS'];

      // Parse Restore header to check status
      if (headResult.Restore) {
        // Format: 'ongoing-request="true"' or 'ongoing-request="false", expiry-date="..."'
        const restore = parseRestoreHeader(headResult.Restore);

        if (restore.ongoingRequest) {
          // Restore already in progress
          return Response.json(
            {
              status: 'restoring',
              message: 'This audiobook is being restored',
              estimatedCompletion: restore.estimatedCompletion,
            },
            { status: 202 }
          );
        } else if (restore.expiryDate && new Date(restore.expiryDate) > new Date()) {
          // File is restored and available
          const url = await generatePresignedUrl(media.s3Key);
          return Response.json({ url });
        }
      } else {
        // Check if in archive tier (need to test actual archival status)
        // For now, try to access and catch InvalidObjectState error
        try {
          const url = await generatePresignedUrl(media.s3Key);
          return Response.json({ url });
        } catch (error: any) {
          if (error.Code === 'InvalidObjectState') {
            // File is archived, initiate restore
            await initiateRestore(media, session.user.id);
            return Response.json(
              {
                status: 'restoring',
                message: 'This audiobook is being restored. It will be ready in 3-5 hours.',
                mediaId: media.id,
              },
              { status: 202 }
            );
          }
          throw error;
        }
      }
    }

    // File is accessible, generate presigned URL
    const url = await generatePresignedUrl(media.s3Key);
    return Response.json({ url });
  } catch (error) {
    console.error('Error checking storage class:', error);
    return new Response('Internal server error', { status: 500 });
  }
}

async function initiateRestore(media: any, userId: string) {
  const s3Client = new S3Client({ region: 'us-east-1' });

  // Create database record
  const restoreRequest = await prisma.mediaRestoreRequest.create({
    data: {
      mediaId: media.id,
      s3Key: media.s3Key,
      storageClass: 'ARCHIVE_ACCESS', // or detect actual tier
      status: 'pending',
      restoreTier: 'Standard',
      daysAvailable: 1,
      requestedByUserId: userId,
      estimatedCompletionTime: new Date(Date.now() + 5 * 60 * 60 * 1000), // 5 hours
    },
  });

  // Initiate S3 restore
  await s3Client.send(
    new RestoreObjectCommand({
      Bucket: process.env.AWS_S3_BUCKET!,
      Key: media.s3Key,
      RestoreRequest: {
        Days: 1, // Keep restored for 1 day
        GlacierJobParameters: {
          Tier: 'Standard', // Standard (3-5h) or Expedited (1-5min, costs more)
        },
      },
    })
  );

  await prisma.mediaRestoreRequest.update({
    where: { id: restoreRequest.id },
    data: {
      status: 'in_progress',
      restoreStartedAt: new Date(),
    },
  });

  return restoreRequest;
}

function parseRestoreHeader(restore: string) {
  // Parse: 'ongoing-request="true"' or 'ongoing-request="false", expiry-date="Fri, 21 Dec 2012 00:00:00 GMT"'
  const ongoingMatch = restore.match(/ongoing-request="(\w+)"/);
  const expiryMatch = restore.match(/expiry-date="([^"]+)"/);

  return {
    ongoingRequest: ongoingMatch?.[1] === 'true',
    expiryDate: expiryMatch?.[1] || null,
    estimatedCompletion:
      ongoingMatch?.[1] === 'true' ? new Date(Date.now() + 5 * 60 * 60 * 1000) : null,
  };
}
```

### 2. Get Restore Status

**New**: `app/api/media/[id]/restore-status/route.ts`

```typescript
export async function GET(req: Request, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return new Response('Unauthorized', { status: 401 });
  }

  const restoreRequest = await prisma.mediaRestoreRequest.findFirst({
    where: {
      mediaId: parseInt(params.id),
      status: { in: ['pending', 'in_progress'] },
    },
    orderBy: { requestedAt: 'desc' },
    include: { media: true },
  });

  if (!restoreRequest) {
    return Response.json({ status: 'not_needed' });
  }

  return Response.json({
    status: restoreRequest.status,
    estimatedCompletion: restoreRequest.estimatedCompletionTime,
    requestedAt: restoreRequest.requestedAt,
    availableAt: restoreRequest.availableAt,
  });
}
```

### 3. List Active Restores (For User Dashboard)

**New**: `app/api/media/restores/route.ts`

```typescript
export async function GET(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return new Response('Unauthorized', { status: 401 });
  }

  const activeRestores = await prisma.mediaRestoreRequest.findMany({
    where: {
      requestedByUserId: session.user.id,
      status: { in: ['pending', 'in_progress', 'available'] },
      // Only show recent restores
      requestedAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
    },
    include: {
      media: {
        include: {
          book: true,
        },
      },
    },
    orderBy: { requestedAt: 'desc' },
  });

  return Response.json(activeRestores);
}
```

---

## Frontend Implementation

### 1. Update AudioPlayer Component

**Update**: `components/AudioPlayer.tsx`

```typescript
'use client';

import { useState, useEffect } from 'react';

export function AudioPlayer({ mediaId }: { mediaId: number }) {
  const [status, setStatus] = useState<'loading' | 'restoring' | 'ready' | 'error'>('loading');
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [restoreInfo, setRestoreInfo] = useState<any>(null);

  useEffect(() => {
    loadAudio();
  }, [mediaId]);

  async function loadAudio() {
    try {
      const res = await fetch(`/api/media/${mediaId}/stream`);

      if (res.status === 202) {
        // File is being restored
        const data = await res.json();
        setStatus('restoring');
        setRestoreInfo(data);

        // Start polling for status
        pollRestoreStatus();
      } else if (res.ok) {
        const data = await res.json();
        setAudioUrl(data.url);
        setStatus('ready');
      } else {
        setStatus('error');
      }
    } catch (error) {
      console.error('Error loading audio:', error);
      setStatus('error');
    }
  }

  async function pollRestoreStatus() {
    const interval = setInterval(async () => {
      try {
        const res = await fetch(`/api/media/${mediaId}/restore-status`);
        const data = await res.json();

        if (data.status === 'available') {
          clearInterval(interval);
          // Reload audio
          loadAudio();
        } else if (data.status === 'failed') {
          clearInterval(interval);
          setStatus('error');
        }

        setRestoreInfo(data);
      } catch (error) {
        console.error('Error polling restore status:', error);
      }
    }, 30000); // Poll every 30 seconds

    // Clean up on unmount
    return () => clearInterval(interval);
  }

  if (status === 'restoring') {
    return (
      <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-6">
        <div className="flex items-center gap-3">
          <svg className="animate-spin h-5 w-5 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          <div>
            <p className="font-medium text-blue-900 dark:text-blue-100">
              Restoring Audiobook
            </p>
            <p className="text-sm text-blue-700 dark:text-blue-300">
              This audiobook hasn't been played in a while. It will be ready in 3-5 hours.
            </p>
            {restoreInfo?.estimatedCompletion && (
              <p className="text-xs text-blue-600 dark:text-blue-400 mt-1">
                Estimated completion: {new Date(restoreInfo.estimatedCompletion).toLocaleString()}
              </p>
            )}
          </div>
        </div>
      </div>
    );
  }

  if (status === 'ready' && audioUrl) {
    return (
      <audio controls src={audioUrl} className="w-full">
        Your browser does not support the audio element.
      </audio>
    );
  }

  if (status === 'error') {
    return (
      <div className="text-red-600">
        Failed to load audiobook. Please try again later.
      </div>
    );
  }

  return <div>Loading...</div>;
}
```

### 2. Add Restore Dashboard (Optional)

**New**: `app/library/restores/page.tsx`

```typescript
import { RestoresList } from '@/components/RestoresList';

export default function RestoresPage() {
  return (
    <div className="container mx-auto py-8">
      <h1 className="text-3xl font-bold mb-6">Restoring Audiobooks</h1>
      <p className="text-gray-600 dark:text-gray-400 mb-8">
        Audiobooks that haven't been played in a while need to be restored before you can listen.
        This typically takes 3-5 hours.
      </p>
      <RestoresList />
    </div>
  );
}
```

---

## iOS App Implementation

Similar to frontend, update the audio playback logic to:

1. Check for restore status before playing
2. Show alert dialog: "This audiobook is being restored. You'll be notified when it's ready."
3. Poll status in background
4. Send push notification when available

**Update**: `BookVault/Views/AudioPlayerView.swift`

```swift
struct AudioPlayerView: View {
    @State private var restoreStatus: RestoreStatus?
    @State private var showingRestoreAlert = false

    var body: some View {
        if let restoreStatus = restoreStatus, restoreStatus.isRestoring {
            RestoreProgressView(status: restoreStatus)
        } else {
            // Normal audio player
        }
    }

    func loadAudio() async {
        // Check restore status first
        let response = await APIClient.shared.get("/api/media/\(mediaId)/stream")

        if response.statusCode == 202 {
            // Restoring
            restoreStatus = try? JSONDecoder().decode(RestoreStatus.self, from: response.data)
            showingRestoreAlert = true
            startPollingRestoreStatus()
        } else {
            // Load audio normally
        }
    }
}
```

---

## Background Jobs

### Restore Status Poller

**New**: `scripts/poll-restore-status.ts`

```typescript
import { PrismaClient } from '@prisma/client';
import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';

const prisma = new PrismaClient();
const s3Client = new S3Client({ region: 'us-east-1' });

async function pollRestoreStatus() {
  // Find all in-progress restores that haven't been checked recently
  const pendingRestores = await prisma.mediaRestoreRequest.findMany({
    where: {
      status: { in: ['pending', 'in_progress'] },
      OR: [
        { lastCheckedAt: null },
        { lastCheckedAt: { lt: new Date(Date.now() - 5 * 60 * 1000) } }, // 5 minutes ago
      ],
    },
    include: { media: true },
  });

  console.log(`Checking ${pendingRestores.length} restore requests...`);

  for (const restore of pendingRestores) {
    try {
      const headResult = await s3Client.send(
        new HeadObjectCommand({
          Bucket: process.env.AWS_S3_BUCKET!,
          Key: restore.s3Key,
        })
      );

      const restoreHeader = headResult.Restore;

      await prisma.mediaRestoreRequest.update({
        where: { id: restore.id },
        data: { lastCheckedAt: new Date() },
      });

      if (!restoreHeader) {
        // No restore in progress, might have expired
        console.log(`Restore ${restore.id} has no restore header`);
        continue;
      }

      const parsed = parseRestoreHeader(restoreHeader);

      if (!parsed.ongoingRequest && parsed.expiryDate) {
        // Restore completed!
        console.log(`Restore ${restore.id} completed!`);

        await prisma.mediaRestoreRequest.update({
          where: { id: restore.id },
          data: {
            status: 'available',
            availableAt: new Date(),
            expiresAt: new Date(parsed.expiryDate),
            restoreExpiryDate: parsed.expiryDate,
          },
        });

        // TODO: Send notification to user
        // await sendNotification(restore.requestedByUserId, ...);
      }
    } catch (error) {
      console.error(`Error checking restore ${restore.id}:`, error);

      // If error is persistent, mark as failed
      if (
        restore.lastCheckedAt &&
        new Date().getTime() - restore.lastCheckedAt.getTime() > 24 * 60 * 60 * 1000
      ) {
        await prisma.mediaRestoreRequest.update({
          where: { id: restore.id },
          data: {
            status: 'failed',
            errorMessage: String(error),
          },
        });
      }
    }
  }
}

// Run every 5 minutes
setInterval(pollRestoreStatus, 5 * 60 * 1000);

// Run immediately on start
pollRestoreStatus();
```

### Run as Background Service

**Option 1: Simple cron job**

```bash
# Add to crontab
*/5 * * * * cd /path/to/book_vault && node scripts/poll-restore-status.js
```

**Option 2: Add to Next.js API route (simpler for now)**

```typescript
// app/api/cron/poll-restores/route.ts
export async function GET(req: Request) {
  // Verify cron secret
  const authHeader = req.headers.get('authorization');
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  await pollRestoreStatus();
  return Response.json({ success: true });
}
```

Then use a service like cron-job.org or Vercel Cron to hit this endpoint every 5 minutes.

---

## Testing Strategy

### Manual Testing

1. **Archive a test file manually**:

   ```bash
   aws s3api copy-object \
     --bucket book-vault-media \
     --copy-source book-vault-media/test-file.m4b \
     --key test-file.m4b \
     --storage-class GLACIER \
     --profile book_vault
   ```

2. **Try to play the file** - should trigger restore workflow

3. **Check database** - verify restore request created

4. **Wait and poll** - check that background job detects completion

### Unit Tests

```typescript
// __tests__/lib/restore-workflow.test.ts
describe('Restore Workflow', () => {
  it('should detect archived files', async () => {
    // Mock S3 HeadObject response with ARCHIVE storage class
    // Verify restore is initiated
  });

  it('should parse restore headers correctly', () => {
    const header1 = 'ongoing-request="true"';
    const parsed1 = parseRestoreHeader(header1);
    expect(parsed1.ongoingRequest).toBe(true);

    const header2 = 'ongoing-request="false", expiry-date="Fri, 21 Dec 2012 00:00:00 GMT"';
    const parsed2 = parseRestoreHeader(header2);
    expect(parsed2.ongoingRequest).toBe(false);
    expect(parsed2.expiryDate).toBeTruthy();
  });

  it('should handle failed restores gracefully', async () => {
    // Test error handling
  });
});
```

---

## Cost Considerations

### S3 Restore Costs

| Tier      | Restore Time | Cost per GB | Cost for 1GB book |
| --------- | ------------ | ----------- | ----------------- |
| Standard  | 3-5 hours    | $0.03       | $0.03             |
| Bulk      | 5-12 hours   | $0.0025     | $0.0025           |
| Expedited | 1-5 minutes  | $0.10       | $0.10             |

**Recommendation**: Use `Standard` tier for most cases. Only use `Expedited` if user pays or for premium feature.

### Keep Restored Files for 1 Day

Setting `Days: 1` in restore request means:

- File stays accessible for 24 hours after restore
- If user plays multiple files from same book, subsequent chapters don't need restore
- After 24 hours, file moves back to archive tier

**Cost**: No extra charge for keeping restored for 1-30 days.

---

## Implementation Checklist

### Phase 0: Prerequisite - On-Demand URL Generation (4-6 hours)

**⚠️ Must be completed before archive restore implementation**

- [ ] Create `/api/books/[id]/stream` endpoint
- [ ] Update `transformBook()` to remove presigned URL generation
- [ ] Add `APIClient.getBookStreamUrl()` method (iOS)
- [ ] Update `AudioPlayerManager` to fetch URLs on-demand (iOS)
- [ ] Update `AudioPlayer` component to fetch URLs on-demand (Web)
- [ ] Update OpenAPI spec with new stream endpoint
- [ ] Add tests for stream endpoint
- [ ] Verify S3 API call reduction (check CloudWatch metrics)
- [ ] Test playback still works on all platforms
- [ ] Update documentation

**Success Metrics:**

- `/api/books` responses no longer include presigned URLs
- S3 API calls reduced by ~99%
- Playback still works on web and iOS
- URLs only generated when user clicks play/download

### Phase 1: Database & API (2-3 hours)

**After Phase 0 is complete**

- [ ] Create `media_restore_requests` table migration
- [ ] Add Prisma schema for MediaRestoreRequest
- [ ] Update `/api/books/[id]/stream` to check storage class
- [ ] Add restore initiation logic
- [ ] Create `/api/books/[id]/restore-status` endpoint
- [ ] Create `/api/books/restores` list endpoint
- [ ] Test with manually archived file

### Phase 2: Frontend (2-3 hours)

- [ ] Update AudioPlayer to show restore UI
- [ ] Add polling logic for restore status
- [ ] Create RestoresList component
- [ ] Add /library/restores page
- [ ] Test user flow end-to-end

### Phase 3: Background Job (1-2 hours)

- [ ] Create `scripts/poll-restore-status.ts`
- [ ] Test restore status detection
- [ ] Set up cron job or API route for polling
- [ ] Add error handling and logging

### Phase 4: iOS App (3-4 hours)

- [ ] Update AudioPlayerView for restore status
- [ ] Add restore progress UI
- [ ] Implement polling in background
- [ ] Test on device

### Phase 5: Notifications (Optional, 2-3 hours)

- [ ] Add email notifications when restore completes
- [ ] Add push notifications for iOS
- [ ] Test notification delivery

### Phase 6: Monitoring & Refinement (1-2 hours)

- [ ] Add CloudWatch metrics for restore requests
- [ ] Create dashboard for restore success rate
- [ ] Document user-facing restore behavior
- [ ] Add restore status to book details page

---

## Future Enhancements

1. **Proactive Restore**: If user adds book to "Want to Listen" list, pre-restore it
2. **Expedited Restore**: Premium feature - pay $0.10 per book for 1-5 minute restore
3. **Batch Restore**: Restore all books by an author or in a series
4. **Smart Caching**: Keep frequently accessed books in Frequent Access tier
5. **Restore History**: Show users which books are frequently archived/restored

---

## Related Documents

- [aws-cost-optimization-plan.md](./aws-cost-optimization-plan.md) - S3 Intelligent-Tiering setup
- [media-configuration.md](./media-configuration.md) - S3 and media handling
- [API_SECURITY.md](./API_SECURITY.md) - Authentication for restore endpoints
