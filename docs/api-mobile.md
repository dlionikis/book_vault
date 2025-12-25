# Mobile API Documentation

**Last Updated**: December 25, 2025

This document provides comprehensive API documentation for mobile clients (iOS app) integrating with Book Vault backend.

---

## Table of Contents

1. [Authentication](#authentication)
2. [Progress Sync](#progress-sync)
3. [Audio Streaming](#audio-streaming)
4. [Chapter Navigation](#chapter-navigation)
5. [Search & Browse](#search--browse)
6. [Library & Lists Sync](#library--lists-sync)

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

## Chapter Navigation

### Overview

Audiobooks include chapter markers for navigation. Chapters are extracted from `.cue` files during import and stored in the database.

### Chapter Data Format

Each chapter object includes:

```typescript
{
  id: string; // UUID
  chapterNumber: number; // Sequential number (1, 2, 3, ...)
  title: string; // Chapter title
  startTime: number; // Start time in seconds (decimal)
  endTime: number; // End time in seconds (decimal)
  duration: number; // Duration in seconds (decimal)
}
```

**Important Notes:**

- Times are in **seconds** (not milliseconds)
- Times are **decimal** (e.g., `123.45` seconds)
- No conversion needed for iOS playback APIs
- Chapters are ordered by `chapterNumber` (ascending)

### Fetching Chapters

#### Option 1: Fetch with Book (Single Request)

Include chapters when fetching book details to reduce round-trips:

```
GET /api/books/{id}?include=chapters
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "id": "uuid",
  "title": "Book Title",
  // ... other book fields
  "chapters": [
    {
      "id": "chapter-uuid-1",
      "chapterNumber": 1,
      "title": "Chapter 1: Introduction",
      "startTime": 0,
      "endTime": 123.45,
      "duration": 123.45
    },
    {
      "id": "chapter-uuid-2",
      "chapterNumber": 2,
      "title": "Chapter 2: The Journey Begins",
      "startTime": 123.45,
      "endTime": 456.78,
      "duration": 333.33
    }
  ]
}
```

**Caching:**

- Response includes `Cache-Control: public, max-age=86400` (24 hours)
- Chapters rarely change, safe to cache aggressively
- Reduces bandwidth on repeated requests

#### Option 2: Fetch Book Without Chapters (Default)

Omit `?include=chapters` to get book without chapters (backward compatible with web):

```
GET /api/books/{id}
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "id": "uuid",
  "title": "Book Title"
  // ... other book fields
  // No chapters field
}
```

### iOS Integration

**Swift Example:**

```swift
struct Chapter: Codable {
    let id: String
    let chapterNumber: Int
    let title: String
    let startTime: Double  // Seconds (decimal)
    let endTime: Double
    let duration: Double
}

// Fetch book with chapters
func fetchBookWithChapters(bookId: String) async throws -> Book {
    let url = URL(string: "https://api.bookvault.app/api/books/\(bookId)?include=chapters")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    let book = try JSONDecoder().decode(Book.self, from: data)
    return book
}

// Seek to chapter start
func seekToChapter(_ chapter: Chapter) {
    let time = CMTime(seconds: chapter.startTime, preferredTimescale: 1)
    player.seek(to: time) { finished in
        if finished {
            print("Seeked to \(chapter.title)")
        }
    }
}
```

**Chapter UI Example:**

```swift
List(book.chapters, id: \.id) { chapter in
    Button(action: { seekToChapter(chapter) }) {
        HStack {
            VStack(alignment: .leading) {
                Text(chapter.title)
                    .font(.headline)
                Text(formatDuration(chapter.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isCurrentChapter(chapter) {
                Image(systemName: "play.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, secs)
}

func isCurrentChapter(_ chapter: Chapter) -> Bool {
    let currentTime = player.currentTime().seconds
    return currentTime >= chapter.startTime && currentTime < chapter.endTime
}
```

### Performance

- **Query performance**: <500ms for books with 50+ chapters (indexed by `bookId`)
- **Caching**: 24-hour cache reduces bandwidth on repeated requests
- **Single request**: Use `?include=chapters` to fetch book + chapters in one round-trip

### Best Practices

1. **Cache chapters locally**: Store in app database after first fetch
2. **Respect cache headers**: Use `Cache-Control` to minimize requests
3. **Prefetch on playback**: Fetch chapters when user starts playing book
4. **Update on sync**: Check for chapter updates when syncing library

---

## Search & Browse

### Overview

Mobile clients can search and browse the library with pagination, field filtering, and autocomplete support for responsive UX.

### Search Endpoint

#### GET /api/search

Search across books, authors, narrators, and series with pagination and field filtering.

**Query Parameters:**

- `q` (required): Search query (case-insensitive, partial match)
- `page` (optional): Page number (default: 1, 1-based)
- `limit` (optional): Results per page (default: 20, max: 100)
- `fields` (optional): Comma-separated field list (e.g., `id,title,coverUrl`)

**Request:**

```
GET /api/search?q=harry&page=1&limit=20
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "results": [
    {
      "id": "uuid",
      "asin": "B001234567",
      "title": "Harry Potter and the Philosopher's Stone",
      "publisherSummary": "...",
      "runtimeMinutes": 480,
      "releaseDate": "1997-06-26T00:00:00.000Z",
      "publisher": "Pottermore Publishing",
      "coverUrl": "https://cdn.bookvault.app/...",
      "audioUrl": "https://cdn.bookvault.app/...",
      "authors": [
        {
          "id": "author-uuid",
          "name": "J.K. Rowling",
          "asin": "A001234567"
        }
      ],
      "narrators": [
        {
          "id": "narrator-uuid",
          "name": "Stephen Fry",
          "asin": "N001234567"
        }
      ],
      "series": [
        {
          "id": "series-uuid",
          "title": "Harry Potter",
          "asin": "S001234567",
          "sequence": "1"
        }
      ],
      "createdAt": "2025-12-20T10:00:00.000Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 145,
    "pages": 8
  }
}
```

**Search Behavior:**

- **Case-insensitive**: Searches ignore case
- **Partial match**: Uses `contains` matching (not exact)
- **Searches across**:
  - Book title
  - Book description
  - Publisher summary
  - Author names
  - Narrator names
  - Series titles

**Field Filtering:**

To reduce payload size for mobile bandwidth optimization:

```
GET /api/search?q=harry&fields=id,title,coverUrl
Authorization: Bearer <token>
```

**Response with fields:**

```json
{
  "results": [
    {
      "id": "uuid",
      "title": "Harry Potter and the Philosopher's Stone",
      "coverUrl": "https://cdn.bookvault.app/..."
    }
  ],
  "pagination": { ... }
}
```

**Available fields:**

- `id`, `asin`, `title`, `description`, `publisherSummary`
- `runtimeMinutes`, `releaseDate`, `publisher`
- `coverUrl`, `audioUrl`
- `authors`, `narrators`, `series`, `categories`, `chapters`
- `createdAt`, `updatedAt`

**Errors:**

- `400`: Search query required
- `401`: Unauthorized
- `500`: Server error

---

### Autocomplete Endpoint

#### GET /api/search/suggestions

Fast autocomplete suggestions for search-as-you-type UX.

**Query Parameters:**

- `q` (required): Query (min 2 characters)

**Request:**

```
GET /api/search/suggestions?q=har
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "books": [
    {
      "id": "uuid-1",
      "title": "Harry Potter and the Philosopher's Stone",
      "coverUrl": "https://cdn.bookvault.app/..."
    },
    {
      "id": "uuid-2",
      "title": "A Harlan Coben Novel",
      "coverUrl": "https://cdn.bookvault.app/..."
    }
  ],
  "authors": [
    {
      "id": "author-uuid-1",
      "name": "Harlan Coben"
    },
    {
      "id": "author-uuid-2",
      "name": "Charlaine Harris"
    }
  ],
  "narrators": [
    {
      "id": "narrator-uuid-1",
      "name": "Harris Yulin"
    }
  ]
}
```

**Suggestion Limits:**

- Top 5 books (by title or series title match)
- Top 3 authors
- Top 2 narrators
- **Total:** Up to 10 mixed results
- **Performance:** <200ms target response time

**Errors:**

- `400`: Query must be at least 2 characters
- `401`: Unauthorized
- `500`: Server error

---

### Browse Endpoints

Browse by authors, series, narrators, or categories with pagination.

#### GET /api/browse/authors

List all authors with book counts.

**Query Parameters:**

- `page` (optional): Page number (default: 1)
- `limit` (optional): Results per page (default: 20, max: 100)

**Response (200):**

```json
{
  "results": [
    {
      "id": "author-uuid",
      "name": "J.K. Rowling",
      "asin": "A001234567",
      "bookCount": 7
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 456,
    "pages": 23
  }
}
```

---

#### GET /api/browse/series

List all series with book counts.

**Query Parameters:**

- `page` (optional): Page number (default: 1)
- `limit` (optional): Results per page (default: 20, max: 100)

**Response (200):**

```json
{
  "results": [
    {
      "id": "series-uuid",
      "title": "Harry Potter",
      "asin": "S001234567",
      "bookCount": 7
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 234,
    "pages": 12
  }
}
```

---

#### GET /api/browse/narrators

List all narrators with book counts.

**Query Parameters:**

- `page` (optional): Page number (default: 1)
- `limit` (optional): Results per page (default: 20, max: 100)

**Response (200):**

```json
{
  "results": [
    {
      "id": "narrator-uuid",
      "name": "Stephen Fry",
      "asin": "N001234567",
      "bookCount": 12
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 189,
    "pages": 10
  }
}
```

---

#### GET /api/browse/categories

List all categories with book counts.

**Query Parameters:**

- `page` (optional): Page number (default: 1)
- `limit` (optional): Results per page (default: 20, max: 100)

**Response (200):**

```json
{
  "results": [
    {
      "id": "category-uuid",
      "name": "Science Fiction & Fantasy",
      "level": 0,
      "parentName": null,
      "bookCount": 234
    },
    {
      "id": "category-uuid-2",
      "name": "Fantasy",
      "level": 1,
      "parentName": "Science Fiction & Fantasy",
      "bookCount": 156
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 89,
    "pages": 5
  }
}
```

---

### iOS Integration Examples

**Search with Debounce:**

```swift
import Combine

class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var results: [Book] = []
    @Published var isLoading = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Debounce search input (500ms)
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .filter { $0.count >= 2 }
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    func performSearch(query: String) {
        isLoading = true

        Task {
            do {
                let results = try await searchBooks(query: query, page: 1, limit: 20)
                await MainActor.run {
                    self.results = results
                    self.isLoading = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    func searchBooks(query: String, page: Int, limit: Int) async throws -> [Book] {
        var components = URLComponents(string: "https://api.bookvault.app/api/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "fields", value: "id,title,coverUrl,authors") // Reduce payload
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results
    }
}
```

**Autocomplete:**

```swift
func fetchSuggestions(query: String) async throws -> Suggestions {
    guard query.count >= 2 else {
        return Suggestions(books: [], authors: [], narrators: [])
    }

    var components = URLComponents(string: "https://api.bookvault.app/api/search/suggestions")!
    components.queryItems = [URLQueryItem(name: "q", value: query)]

    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    let suggestions = try JSONDecoder().decode(Suggestions.self, from: data)
    return suggestions
}
```

**Pagination (Infinite Scroll):**

```swift
class BrowseViewModel: ObservableObject {
    @Published var authors: [Author] = []
    @Published var isLoadingMore = false

    private var currentPage = 1
    private var totalPages = 1

    func loadNextPage() async {
        guard currentPage < totalPages && !isLoadingMore else { return }

        isLoadingMore = true
        currentPage += 1

        do {
            let response = try await fetchAuthors(page: currentPage, limit: 20)
            await MainActor.run {
                self.authors.append(contentsOf: response.results)
                self.totalPages = response.pagination.pages
                self.isLoadingMore = false
            }
        } catch {
            print("Load more error: \(error)")
            await MainActor.run {
                self.currentPage -= 1 // Revert on error
                self.isLoadingMore = false
            }
        }
    }
}
```

---

### Performance & Best Practices

**Search:**

- **Debounce**: Wait 300-500ms after user stops typing
- **Min query length**: 2 characters minimum for autocomplete
- **Field filtering**: Use `?fields=` to reduce payload size for list views
- **Pagination**: Load 20-50 results per page (balance UX vs performance)
- **Cache**: Cache results for 5-10 minutes to reduce requests

**Browse:**

- **Infinite scroll**: Load next page when user reaches 80% of current list
- **Prefetch**: Load page 2 when user views page 1
- **Cache**: Cache browse results for 30 minutes
- **Refresh**: Pull-to-refresh to clear cache and reload

**Performance Targets:**

- Search: <500ms for queries with 1000+ books
- Autocomplete: <200ms for fast suggestions
- Browse: <500ms per page

---

## Library & Lists Sync

### Overview

Mobile clients can manage user lists and library with cross-device sync using polling and last-write-wins conflict resolution.

### Endpoints

#### GET /api/library/lists

Fetch all user lists with book counts.

**Request:**

```
GET /api/library/lists
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "lists": [
    {
      "id": "list-uuid-1",
      "name": "Favorites",
      "description": "My favorite audiobooks",
      "bookCount": 12,
      "createdAt": "2025-12-20T10:00:00.000Z",
      "updatedAt": "2025-12-24T15:30:00.000Z"
    },
    {
      "id": "list-uuid-2",
      "name": "To Read",
      "description": null,
      "bookCount": 25,
      "createdAt": "2025-12-21T08:00:00.000Z",
      "updatedAt": "2025-12-23T12:00:00.000Z"
    }
  ]
}
```

**Errors:**

- `401`: Unauthorized

---

#### POST /api/library/lists

Create a new list.

**Request:**

```json
{
  "name": "Favorites",
  "description": "My favorite audiobooks" // Optional
}
```

**Response (201):**

```json
{
  "id": "list-uuid",
  "name": "Favorites",
  "description": "My favorite audiobooks",
  "bookCount": 0,
  "createdAt": "2025-12-25T10:00:00.000Z",
  "updatedAt": "2025-12-25T10:00:00.000Z"
}
```

**Errors:**

- `400`: List name is required
- `401`: Unauthorized
- `500`: Server error

---

#### PUT /api/library/lists/[id]

Update list metadata (name and/or description).

**Request:**

```json
{
  "name": "My Favorites", // Optional
  "description": "Updated description" // Optional
}
```

**Response (200):**

```json
{
  "id": "list-uuid",
  "name": "My Favorites",
  "description": "Updated description",
  "bookCount": 12,
  "createdAt": "2025-12-20T10:00:00.000Z",
  "updatedAt": "2025-12-25T10:00:00.000Z"
}
```

**Errors:**

- `401`: Unauthorized
- `403`: Not your list
- `404`: List not found
- `500`: Server error

---

#### DELETE /api/library/lists/[id]

Delete a list (cascade deletes all books in list).

**Request:**

```
DELETE /api/library/lists/<list-id>
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "success": true
}
```

**Errors:**

- `401`: Unauthorized
- `403`: Not your list
- `404`: List not found
- `500`: Server error

---

#### PUT /api/library/lists/[id]/reorder

Reorder books in a list (drag-to-reorder).

**Request:**

```json
{
  "bookIds": ["book-uuid-3", "book-uuid-1", "book-uuid-2"]
}
```

**Response (200):**

```json
{
  "success": true,
  "updated": 3
}
```

**Errors:**

- `400`: Book IDs array required
- `401`: Unauthorized
- `403`: Not your list
- `404`: List not found
- `500`: Server error

---

#### POST /api/library/lists/[id]/books

Add a book to a list.

**Request:**

```json
{
  "bookId": "book-uuid"
}
```

**Response (201):**

```json
{
  "success": true
}
```

**Notes:**

- Uses upsert to handle duplicates gracefully
- If book already in list, returns success without error

**Errors:**

- `400`: Book ID is required
- `401`: Unauthorized
- `403`: Not your list
- `404`: List not found or book not found
- `500`: Server error

---

#### DELETE /api/library/lists/[id]/books?bookId=xxx

Remove a book from a list.

**Request:**

```
DELETE /api/library/lists/<list-id>/books?bookId=<book-uuid>
Authorization: Bearer <token>
```

**Response (200):**

```json
{
  "success": true
}
```

**Errors:**

- `400`: Book ID is required
- `401`: Unauthorized
- `403`: Not your list
- `404`: List not found
- `500`: Server error

---

### Conflict Resolution Strategy

**List Metadata (name, description):**

- **Strategy**: Last-write-wins based on `updatedAt` timestamp
- **How it works**:
  1. Client fetches lists and stores `updatedAt` timestamp
  2. Client makes local changes
  3. Client pushes changes immediately if online
  4. On next sync, client compares local `updatedAt` with server `updatedAt`
  5. Newer timestamp wins (server overwrites client or vice versa)

**List Contents (books added/removed):**

- **Strategy**: Merge changes (no conflicts)
- **How it works**:
  1. Each add/remove operation is independent
  2. Adding same book twice = no-op (upsert handles)
  3. Removing same book twice = no-op (delete handles)
  4. No conflict resolution needed (operations are idempotent)

**Book Order (position):**

- **Strategy**: Last-write-wins (entire list reordered atomically)
- **How it works**:
  1. Client sends complete `bookIds` array in desired order
  2. Server updates all positions in single transaction
  3. Last reorder request wins if multiple clients reorder simultaneously

---

### Sync Strategy

**Recommended polling interval:**

- **When app active**: Poll every 30 seconds
- **On app launch**: Fetch immediately
- **Push local changes**: Immediately when online (don't wait for poll)

**iOS sync flow example:**

1. **App Launch:**
   - Fetch all lists: `GET /api/library/lists`
   - Store locally with `updatedAt` timestamps
   - Fetch full list contents for active/favorite lists

2. **Periodic Sync (every 30s):**
   - Fetch lists: `GET /api/library/lists`
   - Compare `updatedAt` timestamps with local cache
   - If server timestamp newer, fetch updated list
   - If local timestamp newer, push local changes

3. **Immediate Push (user makes change):**
   - User adds book to list → `POST /api/library/lists/[id]/books`
   - User removes book → `DELETE /api/library/lists/[id]/books`
   - User reorders list → `PUT /api/library/lists/[id]/reorder`
   - Don't wait for next poll interval

4. **Conflict Handling:**
   - If server rejects update (403, 404), refetch and show error
   - If network error, queue operation locally and retry
   - Show sync status indicator in UI (syncing, synced, error)

---

### iOS Integration Example

**Swift code for list management:**

```swift
class ListSyncManager: ObservableObject {
    @Published var lists: [UserList] = []
    @Published var isSyncing = false

    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 30 // seconds

    func startSync() {
        // Initial fetch
        Task { await syncLists() }

        // Start polling
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { await self?.syncLists() }
        }
    }

    func stopSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func syncLists() async {
        isSyncing = true

        do {
            let url = URL(string: "https://api.bookvault.app/api/library/lists")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ListsResponse.self, from: data)

            await MainActor.run {
                self.lists = response.lists
                self.isSyncing = false
            }
        } catch {
            print("Sync error: \(error)")
            await MainActor.run {
                self.isSyncing = false
            }
        }
    }

    func createList(name: String, description: String?) async throws -> UserList {
        let url = URL(string: "https://api.bookvault.app/api/library/lists")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateListRequest(name: name, description: description)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let list = try JSONDecoder().decode(UserList.self, from: data)

        // Update local cache immediately
        await MainActor.run {
            self.lists.append(list)
        }

        return list
    }

    func addBookToList(listId: String, bookId: String) async throws {
        let url = URL(string: "https://api.bookvault.app/api/library/lists/\(listId)/books")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AddBookRequest(bookId: bookId)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, _) = try await URLSession.shared.data(for: request)

        // Trigger immediate sync to update book count
        await syncLists()
    }

    func reorderList(listId: String, bookIds: [String]) async throws {
        let url = URL(string: "https://api.bookvault.app/api/library/lists/\(listId)/reorder")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ReorderRequest(bookIds: bookIds)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, _) = try await URLSession.shared.data(for: request)
    }
}

struct UserList: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let bookCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct ListsResponse: Codable {
    let lists: [UserList]
}

struct CreateListRequest: Codable {
    let name: String
    let description: String?
}

struct AddBookRequest: Codable {
    let bookId: String
}

struct ReorderRequest: Codable {
    let bookIds: [String]
}
```

---

### Concurrency & Race Conditions

**Safe operations** (handled automatically):

- Adding same book to list from multiple devices → upsert prevents duplicates
- Removing same book from multiple devices → delete handles missing records
- Creating lists with same name → allowed (no unique constraint)

**Potential conflicts** (last-write-wins):

- Editing list metadata simultaneously → server timestamp wins
- Reordering list simultaneously → last reorder request wins
- No explicit conflict UI needed (operations are rare, conflicts rarer)

**Transaction safety:**

- List reorder uses `prisma.$transaction` for atomicity
- All book add/remove operations are atomic
- No partial state exposed to clients

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

### Phase 6 (December 25, 2025)

- Added `GET /api/library/lists` (fetch all lists with book counts)
- Added `POST/PUT/DELETE /api/library/lists` (create/update/delete lists)
- Added `PUT /api/library/lists/[id]/reorder` (drag-to-reorder books)
- Added `POST/DELETE /api/library/lists/[id]/books` (add/remove books)
- Documented conflict resolution strategy (last-write-wins + merge)
- Added iOS integration examples for list management and sync
- Added concurrency handling with transaction safety

### Phase 5 (December 25, 2025)

- Added pagination to `/api/search` and `/api/browse/*` endpoints
- Created `/api/search/suggestions` for autocomplete (<200ms)
- Added `?fields=` parameter for selective response fields
- Verified indexes on Book, Author, Narrator, Series for search performance
- Documented search syntax and pagination behavior
- Added iOS integration examples for search, autocomplete, and pagination

### Phase 4 (December 25, 2025)

- Added optional `?include=chapters` parameter to book detail endpoint
- Added Cache-Control headers (24hr) for chapter responses
- Documented chapter timestamp format (seconds decimal) for iOS
- Verified Chapter index performance for fast queries
- Added Swift code examples for chapter navigation UI

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
