# Media Streaming Endpoints

**Status**: Intentionally excluded from OpenAPI specification
**Reason**: These endpoints serve binary media files (audio/images) with range request support, not REST JSON responses

---

## Overview

These endpoints handle media file streaming and are implemented as Next.js API routes, but they are **NOT** included in the OpenAPI specification because:

1. They serve binary content (audio files, images), not JSON
2. They support HTTP range requests for seeking/progressive loading
3. They use different response headers and content types
4. They don't fit the REST JSON API contract paradigm

---

## Endpoints

### Audio Streaming

**Endpoint**: `GET /api/audio/{...path}`

**Purpose**: Stream audiobook audio files with range request support for seeking

**Authentication**: Required (session or bearer token)

**File Pattern**: `/api/audio/{book-folder}/{filename}.mp3`

**Features**:

- HTTP range requests for seeking (Status 206 Partial Content)
- Supports both S3 (production) and filesystem (development)
- Content-Type detection (.mp3, .m4b, .m4a, .ogg, .wav)
- Proper Accept-Ranges headers for iOS/Android compatibility

**Response Headers**:

- `Content-Type`: `audio/mpeg` (or appropriate audio MIME type)
- `Content-Length`: File size or chunk size (for range requests)
- `Accept-Ranges`: `bytes`
- `Content-Range`: `bytes {start}-{end}/{total}` (for range requests only)

**Status Codes**:

- `200 OK`: Full file stream
- `206 Partial Content`: Range request fulfilled
- `401 Unauthorized`: Not authenticated
- `403 Forbidden`: Invalid path (security check failed)
- `404 Not Found`: File doesn't exist
- `416 Range Not Satisfiable`: Invalid range
- `500 Internal Server Error`: S3 or filesystem error

**Example Usage**:

```typescript
// HTML5 Audio element (supports range requests automatically)
<audio src="/api/audio/The-Hobbit-by-J.R.R.-Tolkien/The-Hobbit.mp3" controls />

// JavaScript fetch with range
fetch('/api/audio/The-Hobbit-by-J.R.R.-Tolkien/The-Hobbit.mp3', {
  headers: {
    'Range': 'bytes=0-1023'
  }
})
```

**Implementation**: [`app/api/audio/[...path]/route.ts`](../../app/api/audio/[...path]/route.ts)

---

### Image Streaming

**Endpoint**: `GET /api/images/{...path}`

**Purpose**: Serve book cover images

**Authentication**: None (public access)

**File Pattern**: `/api/images/{book-folder}/{filename}.jpg`

**Features**:

- Supports both S3 (production) and filesystem (development)
- Content-Type detection (.jpg, .jpeg, .png)
- Aggressive caching headers (images are immutable)

**Response Headers**:

- `Content-Type`: `image/jpeg` or `image/png`
- `Content-Length`: File size
- `Cache-Control`: `public, max-age=31536000, immutable` (1 year)

**Status Codes**:

- `200 OK`: Image file
- `403 Forbidden`: Invalid path (security check failed)
- `404 Not Found`: File doesn't exist
- `500 Internal Server Error`: S3 or filesystem error

**Example Usage**:

```html
<img src="/api/images/The-Hobbit-by-J.R.R.-Tolkien/The-Hobbit.jpg" alt="Book cover" />
```

**Implementation**: [`app/api/images/[...path]/route.ts`](../../app/api/images/[...path]/route.ts)

---

## Security Considerations

### Path Validation

Both endpoints use `validateMediaPath()` to prevent directory traversal attacks:

```typescript
// Security: Validate the path is within the media directory
if (!validateMediaPath(requestedPath)) {
  return NextResponse.json({ error: 'Invalid file path' }, { status: 403 });
}
```

**Blocked patterns**:

- `..` (parent directory)
- Absolute paths outside media directory
- Symlinks pointing outside media directory

### Audio Authentication

Audio endpoints require authentication to prevent unauthorized access to audiobook files:

```typescript
const session = await getServerSession(authOptions);
if (!session?.user) {
  return NextResponse.json(
    { error: 'Authentication required to access audio files' },
    { status: 401 }
  );
}
```

Images are public (no auth required) since they're used for catalog browsing.

---

## Storage Backend

Both endpoints support dual storage backends:

### Development (Filesystem)

- Uses `MEDIA_DATA_PATH` environment variable
- Reads directly from local filesystem
- Fast, no external dependencies

### Production (S3)

- Uses AWS S3 for media storage
- Enabled when `AWS_S3_BUCKET` is configured
- Streams directly from S3 (no local buffering)
- Supports range requests via S3 SDK

**Configuration**:

```bash
# Development
MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"

# Production
AWS_S3_BUCKET="book-vault-media"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="..."
AWS_SECRET_ACCESS_KEY="..."
```

---

## NextAuth Dynamic Routes

**Endpoint**: `GET/POST /api/auth/[...nextauth]`

**Purpose**: NextAuth.js internal authentication routes

**Status**: Intentionally excluded from OpenAPI spec

**Reason**: These are dynamic routes handled entirely by the NextAuth.js library and are not part of our application's REST API contract. They handle the authentication flow internally.

**Routes handled by NextAuth**:

- `/api/auth/signin` - Sign in page
- `/api/auth/signout` - Sign out
- `/api/auth/callback/{provider}` - OAuth callbacks
- `/api/auth/session` - Session management
- `/api/auth/csrf` - CSRF token
- And other internal routes

**Implementation**: [`app/api/auth/[...nextauth]/route.ts`](../../app/api/auth/[...nextauth]/route.ts)

**Documentation**: See [NextAuth.js docs](https://next-auth.js.org/)

---

## Testing

Media streaming endpoints are NOT covered by OpenAPI contract tests since they don't return JSON.

**Manual testing**:

```bash
# Test audio streaming (requires auth)
curl -i -H "Cookie: next-auth.session-token=..." \
  http://localhost:3000/api/audio/The-Hobbit-by-J.R.R.-Tolkien/The-Hobbit.mp3

# Test range request
curl -i -H "Cookie: next-auth.session-token=..." \
  -H "Range: bytes=0-1023" \
  http://localhost:3000/api/audio/The-Hobbit-by-J.R.R.-Tolkien/The-Hobbit.mp3

# Test image (no auth required)
curl -i http://localhost:3000/api/images/The-Hobbit-by-J.R.R.-Tolkien/The-Hobbit.jpg
```

---

## Related Documentation

- [OpenAPI Specification](openapi.yaml) - REST JSON API contract
- [S3 Streaming Implementation](../../lib/s3.ts) - S3 streaming helpers
- [Media Helpers](../../lib/media.ts) - Path validation and URL generation
