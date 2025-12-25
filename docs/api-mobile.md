# Mobile API Documentation

**Last Updated**: December 24, 2025

This document provides comprehensive API documentation for mobile clients (iOS app) integrating with Book Vault backend.

---

## Table of Contents

1. [Authentication](#authentication)
2. [Progress Sync](#progress-sync)
3. [Audio Streaming](#audio-streaming)

---

## Authentication

Mobile clients use JWT Bearer tokens for authentication. See Phase 1 implementation for mobile auth endpoints.

### Headers

All authenticated requests must include:

```
Authorization: Bearer <accessToken>
```

---

## Progress Sync

### Overview

Mobile clients can sync playback progress with high-frequency updates (every 10 seconds) using timestamp-based conflict resolution.

### Endpoints

#### POST /api/progress

Save playback position for a book.

**Request:**

```json
{
  "bookId": "uuid-string",
  "positionSeconds": 123,
  "timestamp": "2025-12-24T10:30:00.000Z" // Optional - ISO 8601 format
}
```

**Response (200):**

```json
{
  "positionSeconds": 123,
  "completed": false,
  "lastPlayed": "2025-12-24T10:30:00.000Z",
  "updated": true // false if conflict (older timestamp)
}
```

**Conflict Resolution:**

- If `timestamp` provided, server compares with existing `lastPlayed`
- Only updates if client timestamp is newer
- If conflict detected, returns `updated: false` and existing progress
- If `timestamp` omitted, uses server time (backward compatible with web)

**Errors:**

- `400`: Missing bookId or positionSeconds
- `401`: Unauthorized (invalid/missing token)
- `429`: Rate limit exceeded (100 requests/minute per user)
- `500`: Server error

---

#### POST /api/progress/batch

Batch sync for offline mode. Upload multiple progress updates at once.

**Request:**

```json
{
  "updates": [
    {
      "bookId": "uuid-1",
      "positionSeconds": 120,
      "timestamp": "2025-12-24T10:00:00.000Z"
    },
    {
      "bookId": "uuid-2",
      "positionSeconds": 300,
      "timestamp": "2025-12-24T10:05:00.000Z"
    }
  ]
}
```

**Response (200):**

```json
{
  "updated": 2,
  "conflicts": 0,
  "details": [
    { "bookId": "uuid-1", "status": "updated" },
    { "bookId": "uuid-2", "status": "updated" }
  ]
}
```

**Conflict Resolution:**

- Each update uses timestamp-based last-write-wins strategy
- Server compares client `timestamp` with existing `lastPlayed`
- Updates with older timestamps are rejected (marked as "conflict")
- All updates processed in a transaction (atomic)

**Errors:**

- `400`: Missing or empty updates array
- `401`: Unauthorized
- `429`: Rate limit exceeded
- `500`: Server error

---

#### GET /api/progress?bookId=xxx

Fetch current progress for a book.

**Query Parameters:**

- `bookId` (required): Book UUID

**Response (200):**

```json
{
  "positionSeconds": 123,
  "completed": false,
  "lastPlayed": "2025-12-24T10:30:00.000Z"
}
```

If no progress exists:

```json
{
  "positionSeconds": 0,
  "completed": false,
  "lastPlayed": null
}
```

**Errors:**

- `400`: Missing bookId
- `401`: Unauthorized
- `500`: Server error

---

### Sync Strategy

**Recommended approach for iOS:**

1. **During Playback:**
   - Save position locally every 10 seconds
   - POST to `/api/progress` immediately if online
   - Queue updates in local database if offline

2. **On App Launch:**
   - Fetch latest progress for current book: `GET /api/progress?bookId=xxx`
   - Compare with local progress (use newer timestamp)

3. **Offline Sync:**
   - When coming back online, use `POST /api/progress/batch`
   - Send all queued updates with original timestamps
   - Server resolves conflicts automatically

4. **Continue Listening:**
   - Fetch recently played books from main library endpoint
   - Books are ordered by `lastPlayed` DESC (indexed for fast queries)

---

## Audio Streaming

### Overview

Audio files are streamed from the backend with support for HTTP range requests (byte-range) for seeking.

### Audio URL Format

**Development (local filesystem):**

```
http://localhost:3000/api/audio/<book-folder>/<filename>.mp3
```

**Production (S3 + CloudFront):**

```
https://cdn.bookvault.app/<book-folder>/<filename>.mp3
```

Or pre-signed S3 URLs (for downloads):

```
https://s3.amazonaws.com/book-vault-media/<path>?signature=...
```

### iOS AVPlayer Integration

AVPlayer automatically handles range requests for seeking. Simply provide the audio URL:

```swift
import AVFoundation

// Set up audio session for background playback
let audioSession = AVAudioSession.sharedInstance()
try? audioSession.setCategory(.playback, mode: .spokenAudio)
try? audioSession.setActive(true)

// Create player with authenticated URL
var request = URLRequest(url: audioURL)
request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

let asset = AVURLAsset(url: audioURL, options: [
    "AVURLAssetHTTPHeaderFieldsKey": [
        "Authorization": "Bearer \(accessToken)"
    ]
])

let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
player.play()
```

### Range Request Support

The backend supports HTTP Range requests (RFC 7233) for efficient seeking:

**Request Headers:**

```
GET /api/audio/<path>
Authorization: Bearer <token>
Range: bytes=0-1023
```

**Response (206 Partial Content):**

```
HTTP/1.1 206 Partial Content
Content-Type: audio/mpeg
Content-Length: 1024
Content-Range: bytes 0-1023/12345678
Accept-Ranges: bytes

<binary audio data>
```

**Response (200 Full File):**

If no Range header provided, returns full file:

```
HTTP/1.1 200 OK
Content-Type: audio/mpeg
Content-Length: 12345678
Accept-Ranges: bytes

<binary audio data>
```

### Error Handling

**Status Codes:**

- `200`: Full file returned (no Range header)
- `206`: Partial content (Range request)
- `401`: Unauthorized (missing/invalid token)
- `404`: Audio file not found
- `416`: Range Not Satisfiable (invalid range)
- `500`: Server error

**Swift Error Handling:**

```swift
player.addObserver(self, forKeyPath: "status", options: .new, context: nil)

override func observeValue(forKeyPath keyPath: String?,
                          of object: Any?,
                          change: [NSKeyValueChangeKey : Any]?,
                          context: UnsafeMutableRawPointer?) {
    if keyPath == "status" {
        if player.status == .failed {
            // Handle error (network, auth, or file not found)
            if let error = player.error {
                print("Playback error: \(error)")
            }
        }
    }
}
```

### Background Audio

iOS requires specific configuration for background audio:

**Info.plist:**

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**Audio Session:**

```swift
// Configure for background playback
let audioSession = AVAudioSession.sharedInstance()
try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
try? audioSession.setActive(true)
```

**Now Playing Info:**

```swift
import MediaPlayer

func updateNowPlayingInfo(book: Book, position: TimeInterval, duration: TimeInterval) {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = book.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = book.authors.first?.name ?? "Unknown"
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate

    if let coverURL = book.coverUrl, let imageData = try? Data(contentsOf: coverURL) {
        if let image = UIImage(data: imageData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: image.size,
                requestHandler: { _ in image }
            )
        }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
}
```

### Testing Range Requests

**Test with curl:**

```bash
# Full file
curl -I http://localhost:3000/api/audio/<path>
# Expected: HTTP 200, Accept-Ranges: bytes

# Range request (first 1KB)
curl -I -H "Range: bytes=0-1023" http://localhost:3000/api/audio/<path>
# Expected: HTTP 206, Content-Range: bytes 0-1023/<total>

# Seek to middle (simulate skip forward)
curl -I -H "Range: bytes=1000000-1001023" http://localhost:3000/api/audio/<path>
# Expected: HTTP 206, Content-Range: bytes 1000000-1001023/<total>
```

---

## Performance Guidelines

### Progress Sync

- **Update frequency**: Every 10 seconds during playback
- **Rate limit**: 100 requests/minute per user (plenty for 10s interval)
- **Batch size**: Up to 100 updates per batch (offline sync)
- **Timeout**: 5 seconds recommended for progress requests

### Audio Streaming

- **Initial buffering**: AVPlayer handles automatically
- **Seek performance**: <1 second (range requests)
- **Network errors**: Implement retry with exponential backoff
- **Cache headers**: Respect Cache-Control headers for images

### Continue Listening Query

- **Performance**: <500ms for 1000+ books (indexed query)
- **Limit**: Fetch top 10-20 recently played books
- **Caching**: Cache results client-side, refresh on app launch

---

## Rate Limiting

All endpoints enforce rate limiting to prevent abuse:

| Endpoint               | Limit                 | Window |
| ---------------------- | --------------------- | ------ |
| `/api/progress` (POST) | 100 requests per user | 1 min  |
| `/api/progress/batch`  | 100 requests per user | 1 min  |
| All other endpoints    | 100 requests per user | 1 min  |

**Rate Limit Response:**

```json
{
  "error": "Rate limit exceeded"
}
```

**Status Code:** `429 Too Many Requests`

**Recommendation:**

- Implement client-side throttling (max 1 update per 10s)
- Queue updates locally if rate limit hit
- Retry with exponential backoff

---

## Timestamp Format

All timestamps use ISO 8601 format (UTC):

```
2025-12-24T10:30:00.000Z
```

**Swift formatting:**

```swift
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let timestamp = formatter.string(from: Date())
```

**Parsing:**

```swift
let date = formatter.date(from: "2025-12-24T10:30:00.000Z")
```

---

## Error Handling Best Practices

1. **Network Errors:**
   - Retry with exponential backoff (1s, 2s, 4s, 8s)
   - Queue updates locally if offline
   - Show user-friendly error messages

2. **Authentication Errors (401):**
   - Attempt token refresh
   - If refresh fails, redirect to login
   - Clear local auth state

3. **Rate Limit Errors (429):**
   - Back off immediately
   - Queue updates locally
   - Retry after 60 seconds

4. **Server Errors (500):**
   - Retry up to 3 times
   - Log error for debugging
   - Fallback to cached data if available

---

## Testing

### Manual Testing

Use curl or Postman to test endpoints:

```bash
# Login (Phase 1 - mobile auth)
curl -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Save progress
curl -X POST http://localhost:3000/api/progress \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<uuid>","positionSeconds":120,"timestamp":"2025-12-24T10:00:00Z"}'

# Batch sync
curl -X POST http://localhost:3000/api/progress/batch \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"updates":[{"bookId":"<uuid>","positionSeconds":120,"timestamp":"2025-12-24T10:00:00Z"}]}'

# Test audio streaming
curl -I -H "Authorization: Bearer <token>" \
  http://localhost:3000/api/audio/<book-folder>/<file>.mp3

# Test range request
curl -I -H "Authorization: Bearer <token>" \
  -H "Range: bytes=0-1023" \
  http://localhost:3000/api/audio/<book-folder>/<file>.mp3
```

---

## Changelog

### Phase 3 (December 25, 2025)

- Validated HTTP Range request support (206 Partial Content)
- Confirmed S3 range request forwarding for production
- Added range request logging for debugging iOS seeking issues
- Verified backend streaming is fully compatible with iOS AVPlayer
- Documented background playback requirements

### Phase 2 (December 24, 2025)

- Added batch progress sync endpoint
- Added timestamp-based conflict resolution
- Added performance monitoring for slow queries
- Documented audio streaming format for iOS AVPlayer
- Added rate limiting (100 req/min per user)

---

## Support

For issues or questions:

- Backend API: See main project documentation
- iOS App: See `docs/mobile-ios-plan.md`
