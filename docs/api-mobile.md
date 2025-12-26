# Mobile API Quick Reference

**Last Updated**: December 25, 2025
**Audience**: iOS developers integrating with Book Vault backend

> **TL;DR**: Book Vault backend is mobile-ready. Use JWT Bearer tokens, stream audio with AVPlayer, sync progress every 10s. See links below for detailed guides.

---

## Quick Links

- **Full API Reference**: [api-quick-ref.md](api-quick-ref.md) - Complete endpoint list
- **iOS Implementation Plan**: [mobile-ios-plan.md](mobile-ios-plan.md) - 8-phase roadmap
- **Swift Code Examples**: [mobile-swift-examples.md](mobile-swift-examples.md) - Copy-paste code snippets
- **Architecture**: [architecture.md](architecture.md) - System design & tech stack

---

## Authentication

Use JWT Bearer tokens with all requests:

```
Authorization: Bearer <accessToken>
```

**Login endpoint** (get tokens):

```
POST /api/auth/mobile/login
Body: { "email": "...", "password": "..." }
Response: { "accessToken": "...", "refreshToken": "..." }
```

See [API_SECURITY.md](API_SECURITY.md) for token refresh flow.

---

## Core Endpoints for iOS

### 1. **Browse Library**

```
GET /api/books?page=1&limit=20
→ { books: Book[], total, page, totalPages }
```

### 2. **Book Details**

```
GET /api/books/{id}?include=chapters
→ Book with chapters array
```

### 3. **Progress Sync**

```
POST /api/progress
Body: { bookId, positionSeconds, timestamp }
→ { positionSeconds, completed, lastPlayed, updated }
```

**Key**: Include `timestamp` (ISO 8601) for conflict resolution. Update every 10s during playback.

### 4. **Batch Sync** (offline mode)

```
POST /api/progress/batch
Body: { updates: [{ bookId, positionSeconds, timestamp }, ...] }
→ { updated, conflicts, details }
```

### 5. **Audio Streaming**

```
GET /api/audio/{book-folder}/{file}.mp3
Headers: Authorization, Range (optional)
→ Audio stream (supports HTTP range requests for seeking)
```

### 6. **Search**

```
GET /api/search?q=query&page=1&limit=20&fields=id,title,coverUrl
→ { results: Book[], pagination }
```

**Autocomplete**:

```
GET /api/search/suggestions?q=query
→ { books, authors, narrators }
```

### 7. **User Lists**

```
GET /api/library/lists → { lists }
POST /api/library/lists → Create list
POST /api/library/lists/{id}/books → Add book
DELETE /api/library/lists/{id}/books?bookId=xxx → Remove book
PUT /api/library/lists/{id}/reorder → Reorder books
```

### 8. **Offline Downloads**

```
POST /api/downloads/{bookId} → { downloadUrl, expiresAt, fileSize }
GET /api/downloads/{bookId}/check → { eligible }
GET /api/downloads → { downloads, dailyCount }
```

**Note**: Pre-signed S3 URLs valid for 1 hour. Max 10 downloads/day.

---

## iOS AVPlayer Integration

**Basic setup**:

```swift
import AVFoundation

let audioSession = AVAudioSession.sharedInstance()
try? audioSession.setCategory(.playback, mode: .spokenAudio)
try? audioSession.setActive(true)

var request = URLRequest(url: audioURL)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

let asset = AVURLAsset(url: audioURL, options: [
    "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]
])
let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
```

**Range requests**: AVPlayer handles automatically for seeking. Backend returns `206 Partial Content`.

**Background audio**: Add `audio` to `UIBackgroundModes` in Info.plist.

**See [mobile-swift-examples.md](mobile-swift-examples.md) for complete code examples.**

---

## Data Models (Swift)

Book Vault API returns JSON that maps to Swift `Codable` structs:

```swift
struct Book: Codable {
    let id: String
    let title: String
    let description: String?
    let runtimeMinutes: Int
    let coverUrl: String
    let audioUrl: String
    let authors: [Author]
    let narrators: [Narrator]
    let series: [SeriesInfo]
    let chapters: [Chapter]? // Optional, use ?include=chapters
}

struct Chapter: Codable {
    let id: String
    let chapterNumber: Int
    let title: String
    let startTime: Double  // Seconds (decimal)
    let endTime: Double
    let duration: Double
}
```

**See [lib/types.ts](../lib/types.ts) for complete TypeScript type definitions.**

---

## Performance Targets

- **Progress sync**: Every 10s during playback (rate limit: 100/min)
- **Search**: <500ms response time
- **Autocomplete**: <200ms response time
- **Audio start**: <1s to playback (AVPlayer buffering)
- **Library sync**: Poll every 30s when app active

---

## Mobile-Specific Features

### **Timestamp-Based Conflict Resolution**

When syncing progress from multiple devices:

- Include `timestamp` in `POST /api/progress`
- Server compares with existing `lastPlayed`
- Newer timestamp wins (last-write-wins)
- Server returns `updated: false` if client timestamp is older

### **Offline Mode**

1. Queue progress updates locally when offline
2. Use `POST /api/progress/batch` when back online
3. Server resolves conflicts using timestamps
4. Download audiobooks via pre-signed S3 URLs

### **Field Filtering**

Reduce bandwidth by requesting only needed fields:

```
GET /api/search?q=harry&fields=id,title,coverUrl
```

### **Caching**

- Book details: Cache 24 hours (`Cache-Control` headers)
- Chapter data: Cache 24 hours (rarely changes)
- Images: Respect `Cache-Control` headers
- Search results: Cache 5-10 minutes client-side

---

## Rate Limiting

All endpoints: **100 requests/minute per user**

Download endpoints: **10 downloads/day per user**

Response on limit exceeded:

```json
{
  "error": "Rate limit exceeded"
}
```

**Status**: `429 Too Many Requests`

---

## Error Handling

| Code | Meaning                       | Action                    |
| ---- | ----------------------------- | ------------------------- |
| 400  | Bad request (missing params)  | Fix request format        |
| 401  | Unauthorized (invalid token)  | Refresh token or re-login |
| 403  | Forbidden (not your resource) | Check ownership           |
| 404  | Not found                     | Verify resource exists    |
| 429  | Rate limit exceeded           | Exponential backoff       |
| 500  | Server error                  | Retry with backoff        |

**Best practice**: Retry with exponential backoff (1s, 2s, 4s, 8s) for network errors.

---

## Testing with curl

```bash
# Login
curl -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Save progress
curl -X POST http://localhost:3000/api/progress \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<uuid>","positionSeconds":120,"timestamp":"2025-12-25T10:00:00.000Z"}'

# Test audio streaming
curl -I -H "Authorization: Bearer <token>" \
  http://localhost:3000/api/audio/<book-folder>/<file>.mp3

# Test range request (seeking)
curl -I -H "Authorization: Bearer <token>" \
  -H "Range: bytes=0-1023" \
  http://localhost:3000/api/audio/<book-folder>/<file>.mp3
```

---

## Next Steps

1. **Read [mobile-ios-plan.md](mobile-ios-plan.md)** - 8-phase implementation roadmap
2. **Review [mobile-swift-examples.md](mobile-swift-examples.md)** - Complete Swift code snippets
3. **Check [api-quick-ref.md](api-quick-ref.md)** - Full endpoint reference
4. **See [API_SECURITY.md](API_SECURITY.md)** - Authentication patterns

---

## Changelog

See archived version at `docs/archive/api-mobile-detailed.md` for comprehensive mobile implementation guide with full Swift examples (2,925 lines).

**Current version (condensed)**: Focuses on quick reference with links to detailed guides.
