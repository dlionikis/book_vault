# Presigned URL + iOS Image Caching Implementation Plan

**Created**: December 31, 2025
**Completed**: December 31, 2025
**Status**: ✅ COMPLETE - Deployed to Production
**PR**: #51

## Completion Notes

All phases implemented and deployed:

- Backend generates presigned S3 URLs (1-hour expiry)
- iOS caches covers by book ID (not URL)
- IAM task role support added for ECS Fargate (no explicit AWS credentials needed)
- Web app and iOS app verified working in production

## Problem Statement

The iOS app cannot display cover images in production because:

1. S3 bucket is private (correctly secured - all public access blocked)
2. API returns direct S3 URLs which return 403 Forbidden
3. SwiftUI's `AsyncImage` caches by URL, so presigned URLs cause cache misses on expiry

## Solution Overview

1. **Backend**: Generate presigned URLs for `coverUrl` and `audioUrl` in book API responses
2. **iOS**: Cache cover images locally by book ID (not by URL), making presigned URL expiry irrelevant

---

## Phase 1: Backend - Presigned URL Generation

### 1.1 Modify book-transformer.ts

**File**: `lib/book-transformer.ts`

**Changes**:

- Make `transformBook()` async to support presigned URL generation
- Generate presigned URLs for `coverUrl` and `audioUrl` in production
- Keep local filesystem URLs in development

```typescript
// Current (sync):
export function transformBook(book: BookWithIncludes) {
  return {
    ...
    coverUrl: getCoverUrl(book.coverUrl),
    audioUrl: getAudioUrl(book.audioUrl),
    ...
  };
}

// New (async with presigned URLs):
export async function transformBook(book: BookWithIncludes) {
  const coverUrl = await getPresignedCoverUrl(book.coverUrl);
  const audioUrl = await getPresignedAudioUrl(book.audioUrl);
  return {
    ...
    coverUrl,
    audioUrl,
    ...
  };
}
```

### 1.2 Update media.ts helpers

**File**: `lib/media.ts`

**Changes**:

- Add `getPresignedCoverUrl()` async function
- Add `getPresignedAudioUrl()` async function
- Use `generatePresignedUrl()` from `lib/s3.ts` in production
- Fall back to API routes in development

```typescript
import { isS3Enabled, generatePresignedUrl } from './s3';

export async function getPresignedCoverUrl(relativePath: string | null): Promise<string | null> {
  if (!relativePath) return null;

  if (isS3Enabled()) {
    // Production: Generate presigned S3 URL (1 hour expiry)
    return await generatePresignedUrl(relativePath, 3600);
  }

  // Development: Use local API route
  const encodedPath = relativePath.split('/').map(encodeURIComponent).join('/');
  const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
  return `${baseUrl}/api/images/${encodedPath}`;
}

export async function getPresignedAudioUrl(relativePath: string | null): Promise<string | null> {
  if (!relativePath) return null;

  if (isS3Enabled()) {
    // Production: Generate presigned S3 URL (1 hour expiry)
    return await generatePresignedUrl(relativePath, 3600);
  }

  // Development: Use local API route
  const encodedPath = relativePath.split('/').map(encodeURIComponent).join('/');
  const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
  return `${baseUrl}/api/audio/${encodedPath}`;
}
```

### 1.3 Update API routes to use async transform

**Files to update**:

- `app/api/books/route.ts` - List books
- `app/api/books/[id]/route.ts` - Get single book
- `app/api/library/route.ts` - Get library (uses `transformLibraryBook`)
- `app/api/search/route.ts` - Search (if it uses transformBook)

**Changes**:

```typescript
// Before:
const transformedBooks: Book[] = books.map(transformBook);

// After:
const transformedBooks: Book[] = await Promise.all(books.map(transformBook));
```

### 1.4 Backend Testing

1. Test locally with S3 disabled (should return API routes)
2. Test with S3 enabled (should return presigned S3 URLs)
3. Verify presigned URLs work in browser (copy URL, paste in browser)
4. Verify expiry works (URL stops working after 1 hour)

---

## Phase 2: iOS - Cover Image Caching

### 2.1 Add CoverCacheManager

**New File**: `ios/BookVault/Services/CoverCacheManager.swift`

**Purpose**: Cache cover images to disk, keyed by book ID (not URL)

```swift
import Foundation
import UIKit

@MainActor
class CoverCacheManager: ObservableObject {
    static let shared = CoverCacheManager()

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    // In-memory cache for fast access
    private var memoryCache: [UUID: UIImage] = [:]
    private let maxMemoryCacheSize = 50

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("covers", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Get cached cover image for a book
    func getCover(for bookId: UUID) -> UIImage? {
        // Check memory cache first
        if let cached = memoryCache[bookId] {
            return cached
        }

        // Check disk cache
        let fileURL = coverFileURL(for: bookId)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        // Add to memory cache
        addToMemoryCache(bookId: bookId, image: image)
        return image
    }

    /// Check if cover is cached for a book
    func hasCover(for bookId: UUID) -> Bool {
        memoryCache[bookId] != nil || fileManager.fileExists(atPath: coverFileURL(for: bookId).path)
    }

    /// Get local file URL for cached cover (for SwiftUI Image)
    func localCoverURL(for bookId: UUID) -> URL? {
        let fileURL = coverFileURL(for: bookId)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// Download and cache cover image from URL
    func cacheCover(for bookId: UUID, from url: URL) async throws {
        // Skip if already cached
        guard !hasCover(for: bookId) else { return }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let image = UIImage(data: data) else {
            throw CoverCacheError.downloadFailed
        }

        // Save to disk
        let fileURL = coverFileURL(for: bookId)
        try data.write(to: fileURL)

        // Add to memory cache
        addToMemoryCache(bookId: bookId, image: image)

        DebugLogger.storage("Cached cover for book: \(bookId)")
    }

    /// Delete cached cover for a book
    func deleteCover(for bookId: UUID) {
        memoryCache.removeValue(forKey: bookId)
        let fileURL = coverFileURL(for: bookId)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Clear all cached covers
    func clearAll() {
        memoryCache.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private Helpers

    private func coverFileURL(for bookId: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(bookId.uuidString).jpg")
    }

    private func addToMemoryCache(bookId: UUID, image: UIImage) {
        // Evict oldest if at capacity
        if memoryCache.count >= maxMemoryCacheSize {
            memoryCache.removeValue(forKey: memoryCache.keys.first!)
        }
        memoryCache[bookId] = image
    }
}

enum CoverCacheError: LocalizedError {
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download cover image"
        }
    }
}
```

### 2.2 Create CachedCoverImage View Component

**New File**: `ios/BookVault/Views/Components/CachedCoverImage.swift`

**Purpose**: Drop-in replacement for AsyncImage that uses local cache

```swift
import SwiftUI

/// Cover image view that uses local cache, falling back to network
struct CachedCoverImage: View {
    let bookId: UUID
    let coverUrl: String?

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(ProgressView())
            } else if loadFailed {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.title)
                            .foregroundColor(.gray)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .task {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        let cache = CoverCacheManager.shared

        // Check cache first
        if let cached = cache.getCover(for: bookId) {
            image = cached
            return
        }

        // No cache - try to download
        guard let urlString = coverUrl, let url = URL(string: urlString) else {
            loadFailed = true
            return
        }

        isLoading = true

        do {
            try await cache.cacheCover(for: bookId, from: url)
            image = cache.getCover(for: bookId)
        } catch {
            DebugLogger.error("Failed to load cover for \(bookId)", error: error)
            loadFailed = true
        }

        isLoading = false
    }
}
```

### 2.3 Update LibraryManager to Cache Covers

**File**: `ios/BookVault/Services/LibraryManager.swift`

**Changes**: After fetching library, cache all cover images in background

```swift
// In fetchLibraryBooks(), after saving to disk cache:
libraryCacheManager.saveLibrary(books: response.books)

// Add: Cache covers in background (don't block return)
Task.detached(priority: .background) {
    await self.cacheCoversForBooks(response.books)
}
```

```swift
// New private method:
private func cacheCoversForBooks(_ books: [LibraryBook]) async {
    let cache = await CoverCacheManager.shared

    for book in books {
        guard let urlString = book.coverUrl,
              let url = URL(string: urlString) else { continue }

        do {
            try await cache.cacheCover(for: book.id, from: url)
        } catch {
            // Log but don't fail - cover caching is best-effort
            DebugLogger.warning("Failed to cache cover for \(book.title)")
        }
    }

    DebugLogger.success("Cached \(books.count) covers")
}
```

### 2.4 Update Views to Use CachedCoverImage

**Files to update**:

- `ios/BookVault/Views/Books/CatalogView.swift` (line 121)
- `ios/BookVault/Views/Books/BookDetailView.swift` (line 38)
- `ios/BookVault/Views/Player/NowPlayingView.swift` (line 43)

**Before**:

```swift
AsyncImage(url: URL(string: book.coverUrl ?? "")) { phase in
    switch phase {
    case .empty:
        Rectangle()
            .fill(Color.gray.opacity(0.3))
    case .success(let image):
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    case .failure:
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "book.closed")
                    .foregroundColor(.gray)
            )
    @unknown default:
        EmptyView()
    }
}
```

**After**:

```swift
CachedCoverImage(bookId: book.id, coverUrl: book.coverUrl)
```

### 2.5 Update project.yml for New Files

**File**: `ios/project.yml`

Add new source files to the project targets.

### 2.6 iOS Testing

1. Build and run on simulator
2. Verify covers load and display
3. Kill app, restart - verify covers load instantly from cache
4. Enable airplane mode - verify cached covers still display
5. Verify covers appear in library view, detail view, and now playing

---

## Phase 3: Testing & Verification

### 3.1 End-to-End Test Scenarios

1. **Fresh Install Flow**:
   - Login → Fetch library → Covers download → Display correctly

2. **App Restart Flow**:
   - Open app → Covers load from cache instantly (no network)

3. **Offline Mode Flow**:
   - Enable airplane mode → Open app → Cached covers display

4. **New Book Added Flow**:
   - Add book to library → Cover downloads → Displays in library

5. **Presigned URL Expiry Flow**:
   - Wait 1+ hours → Open app → Cached covers still work
   - Force refresh library → New presigned URLs fetched → Still works

### 3.2 Performance Verification

- Cover images should load in < 100ms from cache
- Memory usage should stay reasonable (~50 images max in memory)
- Disk cache should not grow unbounded (consider cleanup of old covers)

---

## Implementation Order

1. **Backend Phase 1.1-1.3**: Make transformBook async, add presigned URL generation
2. **Backend Phase 1.4**: Test presigned URLs work in browser
3. **iOS Phase 2.1**: Add CoverCacheManager
4. **iOS Phase 2.2**: Add CachedCoverImage component
5. **iOS Phase 2.3**: Update LibraryManager to cache covers
6. **iOS Phase 2.4**: Update views to use CachedCoverImage
7. **iOS Phase 2.5**: Update project.yml
8. **Phase 3**: End-to-end testing

---

## Rollback Plan

If issues arise:

1. **Backend**: Revert to sync transformBook returning API route URLs
2. **iOS**: Revert views to use AsyncImage with direct URLs
3. Both can be reverted independently if needed

---

## Future Enhancements (Not in Scope)

- Cover image cache cleanup (delete covers for removed books)
- Cover image compression/resizing
- CDN layer for additional caching
- Prefetch covers for series when viewing one book
