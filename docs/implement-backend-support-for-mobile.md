# Backend Work for iOS App Support

**Status**: Ready for phased implementation
**Last Updated**: December 24, 2025
**Token Efficiency**: Document designed for context resets between phases

---

## How to Execute This Plan

### Per-Phase Workflow (Context Reset Friendly)

**At start of each phase**:

1. Read this file first (skim to your phase)
2. Read CLAUDE.md sections 2, 3, and 5 (commands, patterns, schema)
3. Optional: Glance at [mobile-ios-plan.md](mobile-ios-plan.md) for context
4. Run: `docker-compose up -d && npm run dev`
5. Execute phase checklist below

**At end of each phase**:

1. Complete "Acceptance Criteria" verification
2. Run: `npm run validate` (format + lint + typecheck + test)
3. Git commit with message from "Stop Point & Handoff"
4. Record any deviations or notes in git commit body
5. **Update this file**: Mark phase as ✅ Done in heading
6. Clear context for next phase

**File reading budget per phase**: Max ~8 files (prefer existing patterns over exploration)

---

## Assumptions

- Existing API endpoints (`/api/books`, `/api/progress`, `/api/search`, etc.) are **already mobile-ready** (RESTful JSON, JWT auth)
- S3 streaming with range requests **already implemented** for audio seeking
- NextAuth.js JWT tokens **already compatible** with mobile Authorization headers
- Database schema (Prisma) supports all required data models
- No schema changes needed for MVP phases (1–7)

---

## Decisions Made ✅

### Phase 1 Decisions

- **Token refresh strategy**: ✅ **DECIDED** - Implement dedicated `/api/auth/refresh` endpoint with refresh token stored in separate table for explicit revocation support
- **CORS origins**: ✅ **DECIDED** - Start with `*` for development, lock down to iOS bundle ID before production deployment

### Phase 7 Decisions

- **Offline downloads**: ✅ **DECIDED** - Use pre-signed S3 URLs for direct downloads (less backend load, better performance, industry standard)

### Phase 8 Decisions

- **Push notifications**: ✅ **DECIDED** - **SKIP Phase 8** - Not implementing push notifications at this time (can be added later if needed)

### Cross-Phase Decisions

- **Rate limiting**: ✅ **DECIDED** - Implement basic rate limiting (100 req/min per user), tune based on real usage
- **Analytics**: ✅ **DECIDED** - Add simple logging for mobile-specific metrics (device type, iOS version), evaluate dedicated analytics service later

---

## Phase 1: Mobile Auth Foundation ✅ / ⏳ / ❌

**Goal**: Enable iOS app login and session management with JWT tokens

### 1. Objective

Modify NextAuth.js JWT configuration to support mobile clients with explicit token extraction and refresh mechanism. iOS app can authenticate with email/password and manage token lifecycle independently from web cookie-based sessions.

### 2. Scope

**In Scope**:

- Add CORS headers for mobile origins (iOS bundle ID)
- Create mobile-specific auth endpoints (return JWT in JSON response body, not cookies)
- Add refresh token table and refresh endpoint
- Add token verification endpoint for app launch
- Document JWT format and expiry for iOS team

**Out of Scope**:

- Social auth (Google, Apple) - future phase
- Multi-device session management UI - future phase
- Biometric auth logic (handled iOS-side)
- Token blacklist/revocation beyond refresh token invalidation

### 3. Implementation Checklist

**Step 1: Add refresh token support to database**

- [ ] Create migration: `npx prisma migrate dev --name add_refresh_tokens`
- [ ] Add to [prisma/schema.prisma](../prisma/schema.prisma):

  ```prisma
  model RefreshToken {
    id        String   @id @default(uuid())
    userId    String   @map("user_id")
    token     String   @unique
    expiresAt DateTime @map("expires_at")
    createdAt DateTime @default(now()) @map("created_at")

    user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)

    @@index([userId])
    @@index([token])
    @@map("refresh_tokens")
  }
  ```

- [ ] Add `refreshTokens RefreshToken[]` to `User` model
- [ ] Run: `npx prisma migrate dev` (apply migration)
- [ ] Run: `npx prisma generate` (regenerate Prisma Client)

**Step 2: Create mobile auth endpoints**

- [ ] Create [app/api/auth/mobile/login/route.ts](../app/api/auth/mobile/login/route.ts)
  - `POST` handler: validate credentials, generate access token (JWT, 1hr expiry) + refresh token (UUID, 30d expiry)
  - Store refresh token in `RefreshToken` table
  - Return JSON: `{ accessToken: string, refreshToken: string, user: { id, email }, expiresIn: 3600 }`
- [ ] Create [app/api/auth/mobile/refresh/route.ts](../app/api/auth/mobile/refresh/route.ts)
  - `POST` handler: accept `{ refreshToken: string }`, validate expiry, generate new access token
  - Return JSON: `{ accessToken: string, expiresIn: 3600 }`
  - Optionally rotate refresh token (issue new refresh token, invalidate old one)
- [ ] Create [app/api/auth/mobile/verify/route.ts](../app/api/auth/mobile/verify/route.ts)
  - `GET` handler: extract Bearer token from `Authorization` header, decode JWT, validate expiry
  - Return JSON: `{ valid: boolean, user: { id, email } | null }`
- [ ] Create [app/api/auth/mobile/logout/route.ts](../app/api/auth/mobile/logout/route.ts)
  - `POST` handler: accept `{ refreshToken: string }`, delete from `RefreshToken` table
  - Return JSON: `{ success: true }`

**Step 3: Add JWT utilities**

- [ ] Create [lib/jwt.ts](../lib/jwt.ts)
  - `generateAccessToken(userId, email)`: returns signed JWT (use `jsonwebtoken` or `jose` library)
  - `verifyAccessToken(token)`: returns decoded payload or throws error
  - Use `NEXTAUTH_SECRET` from env as signing key
  - Set expiry: 1 hour for access tokens

**Step 4: Add CORS middleware for mobile**

- [ ] Update [middleware.ts](../middleware.ts) or create [app/api/middleware.ts](../app/api/middleware.ts)
  - Add CORS headers to responses:
    ```typescript
    res.headers.set('Access-Control-Allow-Origin', process.env.MOBILE_CORS_ORIGIN || '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    ```
  - Handle `OPTIONS` preflight requests
- [ ] Add `MOBILE_CORS_ORIGIN` to [.env.example](../.env.example)

**Step 5: Add mobile auth middleware helper**

- [ ] Update [lib/auth.ts](../lib/auth.ts)
  - Add `getAuthUserFromRequest(request: NextRequest)` function
  - Check for `Authorization: Bearer <token>` header
  - If present, verify JWT and return user object
  - If absent or invalid, return `null`
  - Existing endpoints can use this OR `getServerSession` (both supported)

**Step 6: Update environment variables**

- [ ] Add to [.env](../.env) and [.env.example](../.env.example):
  ```bash
  # Mobile auth
  MOBILE_CORS_ORIGIN="*"  # Lock down in production (e.g., "capacitor://localhost" for Capacitor apps)
  JWT_ACCESS_TOKEN_EXPIRY="3600"  # 1 hour in seconds
  JWT_REFRESH_TOKEN_EXPIRY="2592000"  # 30 days in seconds
  ```

**Step 7: Add dependencies**

- [ ] Run: `npm install jsonwebtoken @types/jsonwebtoken` OR `npm install jose` (choose one)
  - **Recommendation**: Use `jose` (modern, TypeScript-native, no types package needed)

### 4. API Contract Changes

**New Endpoints**:

**`POST /api/auth/mobile/login`**

- Request: `{ email: string, password: string }`
- Response (200): `{ accessToken: string, refreshToken: string, user: { id: string, email: string }, expiresIn: number }`
- Errors:
  - 400: `{ error: "Email and password required" }`
  - 401: `{ error: "Invalid credentials" }`
  - 500: `{ error: "Login failed" }`

**`POST /api/auth/mobile/refresh`**

- Request: `{ refreshToken: string }`
- Response (200): `{ accessToken: string, expiresIn: number }`
- Errors:
  - 400: `{ error: "Refresh token required" }`
  - 401: `{ error: "Invalid or expired refresh token" }`
  - 500: `{ error: "Token refresh failed" }`

**`GET /api/auth/mobile/verify`**

- Headers: `Authorization: Bearer <accessToken>`
- Response (200): `{ valid: true, user: { id: string, email: string } }`
- Response (401): `{ valid: false, user: null }`

**`POST /api/auth/mobile/logout`**

- Request: `{ refreshToken: string }`
- Response (200): `{ success: true }`
- Errors:
  - 400: `{ error: "Refresh token required" }`
  - 500: `{ error: "Logout failed" }`

### 5. Data Model Changes

**New Table: `RefreshToken`**

- Fields: `id`, `userId`, `token` (UUID), `expiresAt`, `createdAt`
- Indexes: `userId`, `token` (unique)
- Cascade delete when user deleted

**Migration**:

```bash
npx prisma migrate dev --name add_refresh_tokens
```

**Backward Compatibility**:

- Web app auth unchanged (still uses NextAuth.js session cookies)
- Mobile auth is additive (new endpoints, no breaking changes)

### 6. Tests / Verification

**Unit Tests** (create [app/api/auth/mobile/login/route.test.ts](../app/api/auth/mobile/login/route.test.ts), etc.):

- [ ] Login with valid credentials returns tokens
- [ ] Login with invalid credentials returns 401
- [ ] Refresh with valid token returns new access token
- [ ] Refresh with expired/invalid token returns 401
- [ ] Verify with valid token returns user
- [ ] Verify with invalid token returns 401
- [ ] Logout invalidates refresh token

**Manual Verification**:

```bash
# Test login
curl -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Expected: { accessToken: "...", refreshToken: "...", user: {...}, expiresIn: 3600 }

# Test verify (use accessToken from above)
curl -X GET http://localhost:3000/api/auth/mobile/verify \
  -H "Authorization: Bearer <accessToken>"

# Expected: { valid: true, user: {...} }

# Test refresh (use refreshToken from login)
curl -X POST http://localhost:3000/api/auth/mobile/refresh \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"<refreshToken>"}'

# Expected: { accessToken: "...", expiresIn: 3600 }

# Test logout
curl -X POST http://localhost:3000/api/auth/mobile/logout \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"<refreshToken>"}'

# Expected: { success: true }
```

**Integration Test**:

- [ ] Web app login still works (session cookies)
- [ ] Mobile login returns tokens
- [ ] Mobile API calls with Bearer token succeed
- [ ] Expired tokens rejected
- [ ] Logout invalidates tokens

### 7. Acceptance Criteria

- [ ] iOS can authenticate with email/password via `POST /api/auth/mobile/login`
- [ ] Login returns access token (JWT) and refresh token (UUID) in JSON response body
- [ ] iOS can verify token on app launch via `GET /api/auth/mobile/verify`
- [ ] iOS can refresh access token via `POST /api/auth/mobile/refresh` without re-login
- [ ] iOS can logout via `POST /api/auth/mobile/logout` (invalidates refresh token)
- [ ] All tests pass (`npm test`)
- [ ] No breaking changes to web app auth (session cookies still work)
- [ ] CORS headers allow mobile origins

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): add mobile auth endpoints with JWT tokens

- Add RefreshToken table for mobile session management
- Create /api/auth/mobile/* endpoints (login, refresh, verify, logout)
- Add JWT utilities with access/refresh token generation
- Configure CORS for mobile origins
- Add tests for mobile auth flow

Enables iOS app to authenticate and manage sessions independently
from web cookie-based auth. Web app auth unchanged.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `prisma/migrations/*_add_refresh_tokens/migration.sql`
- `prisma/schema.prisma` (updated)
- `lib/jwt.ts` (new)
- `lib/auth.ts` (updated with mobile helper)
- `app/api/auth/mobile/login/route.ts` (new)
- `app/api/auth/mobile/refresh/route.ts` (new)
- `app/api/auth/mobile/verify/route.ts` (new)
- `app/api/auth/mobile/logout/route.ts` (new)
- `app/api/auth/mobile/*/route.test.ts` (new tests)
- `middleware.ts` (updated CORS)
- `.env.example` (updated)

**Notes to Record**:

- JWT expiry settings chosen (1hr access, 30d refresh)
- CORS origin configured (update in production)
- Refresh token rotation strategy (if implemented)

**Resume Next Phase**:

1. Read this file (Phase 2 section)
2. Read CLAUDE.md sections 2, 3, 5
3. Git pull latest changes
4. Start Docker + dev server
5. Begin Phase 2 checklist

---

## Phase 2: Playback Metadata & Progress Sync ✅

**Goal**: Support iOS audio playback with high-frequency position sync and "Continue Listening" performance

### 1. Objective

Optimize existing `/api/progress` endpoints for mobile usage patterns (high-frequency updates every 10s), add batch sync for offline mode, and ensure "Continue Listening" queries are fast with proper indexes.

### 2. Scope

**In Scope**:

- Add database index on `UserProgress(userId, lastPlayed)` for fast queries
- Add `/api/progress/batch` endpoint for offline sync
- Add conflict resolution logic (timestamp-based last-write-wins)
- Validate `/api/progress` performance under mobile load
- Document audio URL format for iOS AVPlayer

**Out of Scope**:

- Playback speed tracking (future enhancement)
- Chapter-level progress (Phase 4)
- Multi-device conflict UI (future - server automatically resolves)
- Progress analytics/reports

### 3. Implementation Checklist

**Step 1: Add database index for Continue Listening**

- [ ] Update [prisma/schema.prisma](../prisma/schema.prisma)
  - Index already exists: `@@index([userId, lastPlayed(sort: Desc)])` on `UserProgress` ✅
  - Verify in schema, no migration needed
- [ ] Run query to test performance:

  ```sql
  EXPLAIN ANALYZE
  SELECT * FROM user_progress
  WHERE user_id = '<uuid>'
  ORDER BY last_played DESC
  LIMIT 10;
  ```

  - Should use index, <10ms for 1000s of records

**Step 2: Create batch progress endpoint**

- [ ] Create [app/api/progress/batch/route.ts](../app/api/progress/batch/route.ts)
  - `POST` handler: accept array of progress updates
  - Request: `{ updates: [{ bookId: string, positionSeconds: number, timestamp: string }] }`
  - Conflict resolution: Compare `timestamp` from client with existing `lastPlayed`, use newer value
  - Use `prisma.$transaction` to batch upserts
  - Return: `{ updated: number, conflicts: number }`

**Step 3: Add timestamp tracking to existing endpoints**

- [ ] Update [app/api/progress/route.ts](../app/api/progress/route.ts)
  - Modify `POST` handler to accept optional `timestamp` field in request body
  - If `timestamp` provided, compare with existing `lastPlayed` before updating
  - Only update if client timestamp is newer OR no existing record
  - Return conflict info: `{ updated: boolean, reason?: "conflict" }`

**Step 4: Add audio URL documentation**

- [ ] Create [docs/api-mobile.md](../docs/api-mobile.md)
  - Document audio streaming URL format:
    - Development: `http://localhost:3000/api/audio/<book-folder>/<filename>.mp3`
    - Production: S3 pre-signed URL or CloudFront URL
  - Document range request support (HTTP 206 Partial Content)
  - Example iOS AVPlayer setup code snippet
  - Example curl commands for testing range requests

**Step 5: Add performance monitoring**

- [ ] Update [app/api/progress/route.ts](../app/api/progress/route.ts)
  - Add timing logs for slow queries (>100ms)
  - Log: `console.warn('Slow progress query', { userId, duration:Ms })`
  - Add simple metrics endpoint (optional): `GET /api/admin/metrics` (require admin auth)

**Step 6: Add rate limiting (optional but recommended)**

- [ ] Install: `npm install express-rate-limit` OR implement simple in-memory rate limiter
- [ ] Create [lib/rate-limit.ts](../lib/rate-limit.ts)
  - Simple Map-based limiter: max 100 requests/min per user
  - `checkRateLimit(userId: string): boolean`
- [ ] Apply to progress endpoints (return 429 if exceeded)

### 4. API Contract Changes

**Modified Endpoint**:

**`POST /api/progress`** (existing, enhanced)

- Request: `{ bookId: string, positionSeconds: number, timestamp?: string }` (timestamp new)
- Response (200): `{ positionSeconds: number, completed: boolean, lastPlayed: string, updated: boolean }`
- New field: `updated: boolean` (false if conflict, true if saved)
- Errors:
  - 429: `{ error: "Rate limit exceeded" }` (new)

**New Endpoint**:

**`POST /api/progress/batch`**

- Headers: `Authorization: Bearer <accessToken>`
- Request: `{ updates: [{ bookId: string, positionSeconds: number, timestamp: string }] }`
- Response (200): `{ updated: number, conflicts: number, details: [{ bookId: string, status: "updated" | "conflict" }] }`
- Errors:
  - 400: `{ error: "Updates array required" }`
  - 401: `{ error: "Unauthorized" }`
  - 429: `{ error: "Rate limit exceeded" }`
  - 500: `{ error: "Batch update failed" }`

### 5. Data Model Changes

**No Schema Changes** (index already exists)

**Behavior Changes**:

- `UserProgress.lastPlayed` now used for conflict resolution (was just tracking timestamp)
- Client timestamps (ISO 8601 strings) compared with server timestamps
- Last-write-wins strategy based on `timestamp` field

**Backward Compatibility**:

- Existing progress updates without `timestamp` field still work (use server time)
- Web app unchanged (continues to use server timestamps)

### 6. Tests / Verification

**Unit Tests**:

- [ ] Create [app/api/progress/batch/route.test.ts](../app/api/progress/batch/route.test.ts)
  - Batch update with no conflicts saves all
  - Batch update with conflicts rejects older timestamps
  - Empty updates array returns 400
  - Unauthorized request returns 401
- [ ] Update [app/api/progress/route.test.ts](../app/api/progress/route.test.ts)
  - Progress update with newer timestamp succeeds
  - Progress update with older timestamp rejected (conflict)
  - Progress update without timestamp uses server time (backward compat)

**Performance Tests**:

```bash
# Test Continue Listening query performance
# Via Prisma Studio: http://localhost:5555
# Run query: UserProgress.findMany({ where: { userId: "..." }, orderBy: { lastPlayed: "desc" }, take: 10 })
# Check query time (should be <10ms)

# Test batch update performance (simulate offline sync)
curl -X POST http://localhost:3000/api/progress/batch \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "updates": [
      {"bookId":"<id1>","positionSeconds":120,"timestamp":"2025-12-24T10:00:00Z"},
      {"bookId":"<id2>","positionSeconds":300,"timestamp":"2025-12-24T10:05:00Z"}
    ]
  }'

# Expected: { updated: 2, conflicts: 0, details: [...] }
```

**Manual Verification**:

- [ ] Web app playback still saves progress correctly
- [ ] Mobile progress updates (10s interval) don't cause DB slowdown
- [ ] "Continue Listening" section loads in <500ms
- [ ] Conflicting updates from web + mobile resolve correctly (newer wins)

### 7. Acceptance Criteria

- [ ] iOS can save position every 10s via `POST /api/progress` without performance degradation
- [ ] iOS can batch-sync offline progress via `POST /api/progress/batch`
- [ ] "Continue Listening" query (recent books ordered by `lastPlayed`) returns in <500ms
- [ ] Position syncs between web and mobile within 10s (when both online)
- [ ] Conflicts resolved by last-write-wins (timestamp comparison)
- [ ] All tests pass (`npm test`)
- [ ] No breaking changes to existing web app progress tracking

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): add batch progress sync and conflict resolution

- Add POST /api/progress/batch for offline sync
- Add timestamp-based conflict resolution (last-write-wins)
- Add performance monitoring for slow queries
- Verify UserProgress index for Continue Listening queries
- Document audio streaming format for iOS AVPlayer

Enables iOS app to sync playback progress efficiently, including
offline mode batch uploads with conflict resolution.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `app/api/progress/batch/route.ts` (new)
- `app/api/progress/route.ts` (updated)
- `app/api/progress/batch/route.test.ts` (new)
- `app/api/progress/route.test.ts` (updated)
- `lib/rate-limit.ts` (new, optional)
- `docs/api-mobile.md` (new)

**Notes to Record**:

- Rate limiting strategy (if implemented)
- Conflict resolution behavior tested
- Continue Listening query performance baseline

**Resume Next Phase**: Read this file (Phase 3), CLAUDE.md, git pull, start services

---

## Phase 3: Background Playback Support ✅ / ⏳ / ❌

**Goal**: Ensure backend audio streaming fully supports iOS background audio and AVPlayer requirements

### 1. Objective

Validate that `/api/audio/[...path]` correctly handles HTTP range requests (critical for AVPlayer seeking) and optimize S3 streaming configuration for mobile clients. No new endpoints needed - this is validation and documentation.

### 2. Scope

**In Scope**:

- Validate range request handling in audio API route
- Add logging for range request patterns
- Document iOS AVPlayer integration (headers, error handling)
- Test seek performance with range requests
- Add CloudWatch/logging for debugging mobile streaming issues

**Out of Scope**:

- Audio transcoding/format conversion (assume .mp3 compatible with iOS)
- Adaptive bitrate streaming (future enhancement)
- Audio caching strategies (handle client-side)
- DRM/encryption (not needed for personal library)

### 3. Implementation Checklist

**Step 1: Validate range request support**

- [ ] Review [app/api/audio/[...path]/route.ts](../app/api/audio/%5B...path%5D/route.ts)
  - Check if `Range` header is read from request
  - Check if `Content-Range` header is set in response
  - Check if status 206 (Partial Content) is returned for range requests
  - Check if status 200 (full file) is returned for non-range requests
- [ ] If missing range support, add:
  ```typescript
  const range = request.headers.get('range');
  if (range) {
    // Parse range header (e.g., "bytes=0-1023")
    // Return 206 with Content-Range header
  }
  ```

**Step 2: Validate S3 range request support**

- [ ] Review [lib/s3.ts](../lib/s3.ts)
  - Check if S3 GetObject command includes `Range` parameter when forwarding client range request
  - Check if S3 response headers (`Content-Range`, `Content-Length`) are forwarded to client
- [ ] Test S3 range requests:
  ```bash
  curl -I -H "Range: bytes=0-1023" http://localhost:3000/api/audio/<path>
  # Expected: HTTP 206, Content-Range: bytes 0-1023/total
  ```

**Step 3: Add range request logging**

- [ ] Update [app/api/audio/[...path]/route.ts](../app/api/audio/%5B...path%5D/route.ts)
  - Log range requests: `console.log('Range request', { path, range, userId })`
  - Log errors: `console.error('Audio streaming error', { path, error })`
  - Optional: Add metrics for range request patterns (for future caching optimization)

**Step 4: Document iOS integration**

- [ ] Update [docs/api-mobile.md](../docs/api-mobile.md)
  - Add section: "iOS AVPlayer Integration"
  - Document required headers: `Authorization: Bearer <token>`, `Range: bytes=<start>-<end>`
  - Document response codes: 200 (full), 206 (partial), 401 (unauthorized), 404 (not found)
  - Add Swift code example:
    ```swift
    var request = URLRequest(url: audioURL)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let player = AVPlayer(url: audioURL) // AVPlayer handles range requests automatically
    ```
  - Document error handling (network errors, auth errors, file not found)

**Step 5: Add integration test**

- [ ] Create [app/api/audio/range-requests.test.ts](../app/api/audio/range-requests.test.ts)
  - Test full file request (no Range header) returns 200
  - Test range request returns 206 with correct Content-Range header
  - Test invalid range returns 416 (Range Not Satisfiable)
  - Test unauthorized request returns 401
  - Mock S3 client to avoid real S3 calls in tests

**Step 6: Test with real audio file**

- [ ] Manual test with curl:

  ```bash
  # Get full file
  curl -I http://localhost:3000/api/audio/<path>
  # Expected: 200, Content-Length: <size>

  # Get range
  curl -I -H "Range: bytes=0-1023" http://localhost:3000/api/audio/<path>
  # Expected: 206, Content-Range: bytes 0-1023/<size>

  # Get middle range (seek simulation)
  curl -I -H "Range: bytes=1000000-1001023" http://localhost:3000/api/audio/<path>
  # Expected: 206, Content-Range: bytes 1000000-1001023/<size>
  ```

### 4. API Contract Changes

**No New Endpoints** (validation only)

**Clarified Behavior for `GET /api/audio/[...path]`**:

- Headers (request):
  - `Authorization: Bearer <token>` (required)
  - `Range: bytes=<start>-<end>` (optional, for seeking)
- Headers (response):
  - `Content-Type: audio/mpeg` (or detected MIME type)
  - `Content-Length: <size>` (for full file)
  - `Content-Range: bytes <start>-<end>/<total>` (for range requests)
  - `Accept-Ranges: bytes` (to signal range support)
- Status codes:
  - 200: Full file returned (no Range header)
  - 206: Partial content returned (Range header present)
  - 401: Unauthorized (missing/invalid token)
  - 404: File not found
  - 416: Range Not Satisfiable (invalid range)
  - 500: Server error

### 5. Data Model Changes

**No Schema Changes**

### 6. Tests / Verification

**Unit Tests**:

- [ ] Range request returns 206 with correct headers
- [ ] Non-range request returns 200 with full file
- [ ] Invalid range returns 416
- [ ] Unauthorized request returns 401
- [ ] Missing file returns 404

**Manual Verification**:

```bash
# Test range requests with curl
curl -v -H "Range: bytes=0-1023" http://localhost:3000/api/audio/<book-folder>/<file>.mp3

# Expected response:
# HTTP/1.1 206 Partial Content
# Content-Range: bytes 0-1023/<total-size>
# Content-Length: 1024
# Accept-Ranges: bytes

# Test seek performance (request from middle of file)
time curl -H "Range: bytes=5000000-5001023" http://localhost:3000/api/audio/<path> > /dev/null
# Expected: <1 second response time
```

**iOS AVPlayer Test** (if iOS dev available):

- [ ] Audio plays immediately when user taps play
- [ ] Seeking to any position works instantly (<1s)
- [ ] No buffering issues during playback
- [ ] Background audio continues when app backgrounded
- [ ] Lock screen controls work (Phase 3 focus: backend streaming, not iOS implementation)

### 7. Acceptance Criteria

- [ ] Audio streaming endpoint handles byte-range requests correctly (returns HTTP 206)
- [ ] Range requests verified with curl (start, middle, end of file)
- [ ] S3 range requests forwarded correctly (if using S3)
- [ ] No backend changes break iOS background audio (streaming works continuously)
- [ ] Documentation updated with iOS AVPlayer integration guide
- [ ] All tests pass (`npm test`)

### 8. Stop Point & Handoff

**Commit Message**:

```
docs(mobile): validate and document range request support for iOS

- Verify /api/audio/* handles HTTP Range requests (206 responses)
- Add logging for range request patterns
- Document iOS AVPlayer integration in api-mobile.md
- Add tests for range request handling
- Validate S3 range request forwarding

Confirms backend audio streaming is fully compatible with iOS
AVPlayer seeking and background playback requirements.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `app/api/audio/[...path]/route.ts` (validated/updated)
- `lib/s3.ts` (validated)
- `docs/api-mobile.md` (updated)
- `app/api/audio/range-requests.test.ts` (new)

**Notes to Record**:

- Range request patterns observed (for future caching)
- Seek performance baseline (response time for range requests)
- Any iOS-specific streaming issues discovered

**Resume Next Phase**: Read this file (Phase 4), CLAUDE.md, git pull, start services

---

## Phase 4: Chapter Metadata Optimization ✅ / ⏳ / ❌

**Goal**: Fast chapter loading for iOS chapter navigation UI

### 1. Objective

Optimize chapter queries for mobile clients, add optional prefetch endpoint to reduce round-trips, and add caching headers to minimize bandwidth for rarely-changing chapter data.

### 2. Scope

**In Scope**:

- Verify `Chapter(bookId, chapterNumber)` index exists and performs well
- Add optional `?include=chapters` to `/api/books/[id]` (reduce round-trips)
- Add caching headers to chapter responses (24hr cache)
- Document chapter timestamp format for iOS parsing

**Out of Scope**:

- Chapter artwork/images (future enhancement)
- User-created chapter markers (future feature)
- Chapter descriptions beyond title (not in Libation metadata)
- Chapter progress tracking (already handled by position sync)

### 3. Implementation Checklist

**Step 1: Validate chapter index**

- [ ] Check [prisma/schema.prisma](../prisma/schema.prisma)
  - Index exists: `@@index([bookId])` on `Chapter` ✅
  - Unique constraint exists: `@@unique([bookId, chapterNumber])` ✅
  - No migration needed
- [ ] Test query performance:

  ```sql
  EXPLAIN ANALYZE
  SELECT * FROM chapters
  WHERE book_id = '<uuid>'
  ORDER BY chapter_number ASC;
  ```

  - Should use index, <10ms for 100 chapters

**Step 2: Add chapters to book detail endpoint**

- [ ] Update [app/api/books/[id]/route.ts](../app/api/books/%5Bid%5D/route.ts)
  - Add optional query param: `?include=chapters`
  - If present, add `include: { chapters: { orderBy: { chapterNumber: 'asc' } } }` to Prisma query
  - Return chapters in response: `{ ...book, chapters: [...] }`
  - If absent, omit chapters (backward compat)

**Step 3: Add caching headers to chapter responses**

- [ ] Update [app/api/books/[id]/chapters/route.ts](../app/api/books/%5Bid%5D/chapters/route.ts) (if exists)
  - Add headers: `Cache-Control: public, max-age=86400` (24 hours)
  - Add header: `ETag: <hash of chapters data>` (optional, for conditional requests)
- [ ] Update [app/api/books/[id]/route.ts](../app/api/books/%5Bid%5D/route.ts) when `include=chapters`
  - Add same caching headers when chapters included

**Step 4: Document chapter format**

- [ ] Update [docs/api-mobile.md](../docs/api-mobile.md)
  - Add section: "Chapter Navigation"
  - Document chapter object schema:
    ```typescript
    {
      id: string,
      chapterNumber: number,
      title: string,
      startTime: number,  // seconds (decimal)
      endTime: number,    // seconds (decimal)
      duration: number    // seconds (decimal)
    }
    ```
  - Note: `startTime` is in seconds (e.g., 123.45), not milliseconds
  - Add Swift parsing example: `let startTime = chapter.startTime` (no conversion needed)

**Step 5: Add performance test**

- [ ] Create [app/api/books/chapters-performance.test.ts](../app/api/books/chapters-performance.test.ts)
  - Test fetching chapters for book with 50 chapters (<500ms)
  - Test fetching book with `?include=chapters` returns chapters
  - Test fetching book without `?include=chapters` omits chapters (backward compat)
  - Test caching headers present in response

**Step 6: Optimize chapter extraction (if not already done)**

- [ ] Review chapter extraction logic (likely in import script or lazy-load on first play)
  - If chapters lazy-loaded on first playback, ensure fast extraction (<2s for typical audiobook)
  - If chapters pre-extracted during import, verify all books have chapters

### 4. API Contract Changes

**Modified Endpoint**:

**`GET /api/books/[id]`** (existing, enhanced)

- Query params: `?include=chapters` (new, optional)
- Response (200):
  ```typescript
  {
    id: string,
    title: string,
    // ... other book fields
    chapters?: [  // Only present if ?include=chapters
      {
        id: string,
        chapterNumber: number,
        title: string,
        startTime: number,
        endTime: number,
        duration: number
      }
    ]
  }
  ```
- Headers (response):
  - `Cache-Control: public, max-age=86400` (when chapters included)
- Errors: (unchanged)

**Existing Endpoint** (clarified):

**`GET /api/books/[id]/chapters`** (if exists)

- Headers (response):
  - `Cache-Control: public, max-age=86400` (new)
- Response: Array of chapter objects (unchanged)

### 5. Data Model Changes

**No Schema Changes** (index already exists)

**Behavior Changes**:

- Chapters now cached client-side for 24 hours
- Single request can fetch book + chapters (optional optimization)

### 6. Tests / Verification

**Unit Tests**:

- [ ] Book detail with `?include=chapters` returns chapters array
- [ ] Book detail without query param omits chapters
- [ ] Chapter list endpoint returns caching headers
- [ ] Chapter timestamps in correct format (seconds, decimal)

**Performance Tests**:

```bash
# Test chapter query performance
curl -w "@curl-format.txt" http://localhost:3000/api/books/<id>/chapters
# Expected: <500ms for 50 chapters

# Test prefetch optimization
curl -w "@curl-format.txt" http://localhost:3000/api/books/<id>?include=chapters
# Expected: <500ms (similar to separate requests, but one round-trip)

# Verify caching headers
curl -I http://localhost:3000/api/books/<id>/chapters
# Expected: Cache-Control: public, max-age=86400
```

**Manual Verification**:

- [ ] Web app book detail page loads correctly (no chapters in response by default)
- [ ] iOS can fetch book + chapters in one request (`?include=chapters`)
- [ ] Chapter times parse correctly in iOS (no conversion needed)
- [ ] Caching reduces bandwidth on repeated requests

### 7. Acceptance Criteria

- [ ] Chapter list loads in <500ms for books with 50+ chapters
- [ ] iOS can parse chapter timestamps without conversion (seconds, decimal)
- [ ] Caching headers reduce bandwidth on repeated chapter fetches
- [ ] Optional `?include=chapters` on book detail reduces round-trips
- [ ] All tests pass (`npm test`)
- [ ] No breaking changes to web app (chapters not included by default)

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): optimize chapter queries and add prefetch option

- Add optional ?include=chapters to GET /api/books/[id]
- Add Cache-Control headers (24hr) to chapter responses
- Verify Chapter index performance (<500ms for 50 chapters)
- Document chapter timestamp format (seconds decimal) for iOS

Enables iOS app to fetch chapters efficiently with reduced
round-trips and bandwidth via caching.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `app/api/books/[id]/route.ts` (updated)
- `app/api/books/[id]/chapters/route.ts` (updated, if exists)
- `docs/api-mobile.md` (updated)
- `app/api/books/chapters-performance.test.ts` (new)

**Notes to Record**:

- Chapter query performance baseline
- Caching strategy effectiveness (monitor cache hit rate if logging added)

**Resume Next Phase**: Read this file (Phase 5), CLAUDE.md, git pull, start services

---

## Phase 5: Search & Browse Performance ✅ / ⏳ / ❌

**Goal**: Fast search and browsing for iOS with pagination, field filtering, and autocomplete

### 1. Objective

Add pagination to all browse endpoints, optimize search queries with indexes, add autocomplete endpoint for fast suggestions, and add field filtering to reduce payload size for mobile clients.

### 2. Scope

**In Scope**:

- Add pagination params (`page`, `limit`) to `/api/search` and `/api/browse/*`
- Add database indexes on `Book.title`, `Author.name`, `Narrator.name`, `Series.title`
- Create `/api/search/suggestions` for autocomplete (top 10 results, <200ms)
- Add `?fields=id,title,coverUrl` for selective response fields
- Document search query syntax (case-insensitive, partial match behavior)

**Out of Scope**:

- Full-text search (Elasticsearch, Algolia) - use Prisma's `contains` for MVP
- Advanced filters (date range, duration, rating) - future enhancement
- Search history/suggestions based on user behavior - future feature
- Voice search integration - handled iOS-side

### 3. Implementation Checklist

**Step 1: Add search/browse indexes**

- [ ] Update [prisma/schema.prisma](../prisma/schema.prisma)
  - Check existing indexes:
    - `Book`: `@@index([title])` ✅ (already exists)
    - `Author`: `@@index([name])` ✅ (already exists)
    - `Narrator`: `@@index([name])` ✅ (already exists)
    - `Series`: `@@index([title])` ✅ (already exists)
  - No migration needed (indexes already present)

**Step 2: Add pagination to search endpoint**

- [ ] Update [app/api/search/route.ts](../app/api/search/route.ts)
  - Add query params: `page` (default: 1), `limit` (default: 20, max: 100)
  - Calculate `skip`: `(page - 1) * limit`
  - Add to Prisma query: `take: limit, skip: skip`
  - Return pagination metadata:
    ```typescript
    {
      results: [...],
      pagination: {
        page: number,
        limit: number,
        total: number,  // Total matching results
        pages: number   // Math.ceil(total / limit)
      }
    }
    ```
  - Count total results: `await prisma.book.count({ where: { ... } })`

**Step 3: Add pagination to browse endpoints**

- [ ] Update [app/api/browse/authors/route.ts](../app/api/browse/authors/route.ts) (if exists)
  - Add same pagination logic
- [ ] Update [app/api/browse/series/route.ts](../app/api/browse/series/route.ts) (if exists)
  - Add same pagination logic
- [ ] Update [app/api/browse/narrators/route.ts](../app/api/browse/narrators/route.ts) (if exists)
  - Add same pagination logic
- [ ] Update [app/api/browse/categories/route.ts](../app/api/browse/categories/route.ts) (if exists)
  - Add same pagination logic

**Step 4: Create autocomplete endpoint**

- [ ] Create [app/api/search/suggestions/route.ts](../app/api/search/suggestions/route.ts)
  - `GET` handler: accept `?q=<query>` (min 2 characters)
  - Search across books, authors, narrators (parallel queries)
  - Return top 10 results total (mixed: 5 books, 3 authors, 2 narrators)
  - Fast queries: use `take: 5` and `select: { id, name/title, coverUrl }` (minimal fields)
  - Response:
    ```typescript
    {
      books: [{ id, title, coverUrl }],
      authors: [{ id, name }],
      narrators: [{ id, name }]
    }
    ```
  - Target: <200ms response time

**Step 5: Add field filtering**

- [ ] Create helper in [lib/api-utils.ts](../lib/api-utils.ts)
  - `parseFields(fieldsParam: string): Prisma.BookSelect`
  - Parse `?fields=id,title,coverUrl` into Prisma `select` object
  - Default fields if not specified: all fields
- [ ] Update search and browse endpoints to use `parseFields`
  - Apply to Prisma query: `select: parseFields(request.nextUrl.searchParams.get('fields'))`

**Step 6: Document search behavior**

- [ ] Update [docs/api-mobile.md](../docs/api-mobile.md)
  - Add section: "Search & Browse"
  - Document pagination params: `page` (1-based), `limit` (default 20, max 100)
  - Document field filtering: `?fields=id,title,coverUrl` (comma-separated)
  - Document search syntax:
    - Case-insensitive
    - Partial match (contains, not exact)
    - Searches across: title, author names, narrator names, series titles
  - Add example requests with curl

**Step 7: Add performance tests**

- [ ] Create [app/api/search/performance.test.ts](../app/api/search/performance.test.ts)
  - Test search with 1000+ books returns in <500ms
  - Test autocomplete returns in <200ms
  - Test pagination works correctly (page 1, page 2, last page)
  - Test field filtering reduces response size

### 4. API Contract Changes

**Modified Endpoints**:

**`GET /api/search`** (existing, enhanced)

- Query params:
  - `q`: Search query (required)
  - `page`: Page number (default: 1)
  - `limit`: Results per page (default: 20, max: 100)
  - `fields`: Comma-separated field list (optional, e.g., `id,title,coverUrl`)
- Response (200):
  ```typescript
  {
    results: [...],  // Array of books (or partial books if fields specified)
    pagination: {
      page: number,
      limit: number,
      total: number,
      pages: number
    }
  }
  ```
- Errors:
  - 400: `{ error: "Search query required" }`

**`GET /api/browse/{authors|series|narrators|categories}`** (existing, enhanced)

- Query params: `page`, `limit`, `fields` (same as search)
- Response: Same pagination structure

**New Endpoint**:

**`GET /api/search/suggestions`**

- Query params: `q` (min 2 characters)
- Response (200):
  ```typescript
  {
    books: [{ id: string, title: string, coverUrl?: string }],
    authors: [{ id: string, name: string }],
    narrators: [{ id: string, name: string }]
  }
  ```
- Errors:
  - 400: `{ error: "Query must be at least 2 characters" }`

### 5. Data Model Changes

**No Schema Changes** (indexes already exist)

**Behavior Changes**:

- Search and browse now return paginated results (default: 20 per page)
- Field filtering reduces response size for mobile bandwidth optimization

**Backward Compatibility**:

- If no pagination params, use defaults (page 1, limit 20)
- If no fields param, return all fields (existing behavior)

### 6. Tests / Verification

**Unit Tests**:

- [ ] Search with pagination returns correct page
- [ ] Pagination metadata is accurate (total, pages)
- [ ] Field filtering returns only requested fields
- [ ] Autocomplete returns top 10 mixed results
- [ ] Autocomplete rejects queries <2 characters

**Performance Tests**:

```bash
# Test search performance (large dataset)
time curl "http://localhost:3000/api/search?q=the&page=1&limit=20"
# Expected: <500ms

# Test autocomplete performance
time curl "http://localhost:3000/api/search/suggestions?q=har"
# Expected: <200ms

# Test field filtering (reduced payload)
curl "http://localhost:3000/api/search?q=harry&fields=id,title,coverUrl"
# Expected: Smaller response than full fields
```

**Manual Verification**:

- [ ] Search results match expected books
- [ ] Pagination works (page 1, 2, last page)
- [ ] Autocomplete suggestions are relevant
- [ ] Field filtering reduces bandwidth (check response size)

### 7. Acceptance Criteria

- [ ] Search returns results in <500ms for queries with 1000+ books
- [ ] Browse endpoints support pagination (page/limit params)
- [ ] Autocomplete endpoint returns top 10 mixed results in <200ms
- [ ] Field filtering reduces response payload size for mobile
- [ ] All tests pass (`npm test`)
- [ ] Backward compatibility maintained (defaults work without params)

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): add pagination, autocomplete, and field filtering to search

- Add pagination to /api/search and /api/browse/* endpoints
- Create /api/search/suggestions for autocomplete (<200ms)
- Add ?fields param for selective response fields
- Verify indexes on Book, Author, Narrator, Series
- Document search syntax and pagination behavior

Enables iOS app to search efficiently with reduced bandwidth
and fast autocomplete for better UX.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `app/api/search/route.ts` (updated)
- `app/api/search/suggestions/route.ts` (new)
- `app/api/browse/*/route.ts` (updated for pagination)
- `lib/api-utils.ts` (new, field filtering helper)
- `docs/api-mobile.md` (updated)
- `app/api/search/performance.test.ts` (new)

**Notes to Record**:

- Search performance baseline (1000+ books)
- Autocomplete response time
- Field filtering bandwidth savings

**Resume Next Phase**: Read this file (Phase 6), CLAUDE.md, git pull, start services

---

## Phase 6: User Lists & Library Sync ✅ / ⏳ / ❌

**Goal**: Enable iOS to manage user lists and library with cross-device sync

### 1. Objective

Validate existing `/api/library/*` endpoints support concurrent updates, add list reordering endpoint, add endpoint to fetch all user lists with metadata, and document conflict resolution strategy.

### 2. Scope

**In Scope**:

- Verify `/api/library/*` endpoints handle concurrent updates (optimistic locking or last-write-wins)
- Add `PUT /api/library/lists/[id]/reorder` for drag-to-reorder books
- Add `GET /api/library/lists` to fetch all lists with book counts
- Document conflict resolution strategy for cross-device sync
- Add tests for concurrent list updates

**Out of Scope**:

- Real-time sync (WebSocket/SSE) - use polling for MVP
- List sharing with other users - future feature
- List templates/presets - future feature
- List cover art customization - future feature

### 3. Implementation Checklist

**Step 1: Audit existing library endpoints**

- [ ] Review [app/api/library/route.ts](../app/api/library/route.ts) (if exists)
  - Check `POST` (add book to library) uses upsert or handles duplicates
  - Check `DELETE` uses proper user + book filtering
- [ ] Review list endpoints (if exist)
  - Check for race conditions in concurrent updates
  - Add transaction wrapping if needed: `prisma.$transaction([...])`

**Step 2: Create list overview endpoint**

- [ ] Create [app/api/library/lists/route.ts](../app/api/library/lists/route.ts)
  - `GET` handler: fetch all lists for authenticated user
  - Include book count:
    ```typescript
    await prisma.userList.findMany({
      where: { userId: session.user.id },
      include: {
        _count: { select: { books: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
    ```
  - Response:
    ```typescript
    {
      lists: [{
        id: string,
        name: string,
        description?: string,
        bookCount: number,
        createdAt: string,
        updatedAt: string
      }]
    }
    ```

**Step 3: Create list reorder endpoint**

- [ ] Create [app/api/library/lists/[id]/reorder/route.ts](../app/api/library/lists/%5Bid%5D/reorder/route.ts)
  - `PUT` handler: accept `{ bookIds: string[] }` (ordered array)
  - Validate list belongs to user
  - Update `UserListBook.position` for each book:
    ```typescript
    await prisma.$transaction(
      bookIds.map((bookId, index) =>
        prisma.userListBook.update({
          where: { listId_bookId: { listId, bookId } },
          data: { position: index },
        })
      )
    );
    ```
  - Return: `{ success: true, updated: number }`

**Step 4: Add list creation/update endpoints (if not exist)**

- [ ] Create [app/api/library/lists/route.ts](../app/api/library/lists/route.ts)
  - `POST` handler: create new list `{ name: string, description?: string }`
  - `PUT` handler: update list metadata `{ id: string, name?: string, description?: string }`
  - `DELETE` handler: delete list (cascade deletes books via Prisma schema)

**Step 5: Add book-to-list endpoints**

- [ ] Create [app/api/library/lists/[id]/books/route.ts](../app/api/library/lists/%5Bid%5D/books/route.ts)
  - `POST` handler: add book to list `{ bookId: string }`
  - `DELETE` handler: remove book from list `?bookId=<id>`
  - Handle duplicates: use `upsert` or check existence

**Step 6: Document sync strategy**

- [ ] Update [docs/api-mobile.md](../docs/api-mobile.md)
  - Add section: "Library & Lists Sync"
  - Document conflict resolution:
    - **List metadata** (name, description): Last-write-wins based on `updatedAt` timestamp
    - **List contents** (books added/removed): Merge changes (no conflicts - each change is independent)
    - **Book order** (position): Last-write-wins (entire list reordered atomically)
  - Recommend polling interval: 30s when app active, on launch
  - Example iOS sync flow:
    1. Fetch lists on app launch
    2. Poll for changes every 30s (compare `updatedAt` timestamps)
    3. Push local changes immediately (don't wait for poll)

**Step 7: Add concurrency tests**

- [ ] Create [app/api/library/concurrency.test.ts](../app/api/library/concurrency.test.ts)
  - Test adding same book to library from 2 concurrent requests (no duplicate)
  - Test reordering list while adding book (transaction isolation)
  - Test deleting list while adding book (graceful failure)

### 4. API Contract Changes

**New Endpoints**:

**`GET /api/library/lists`**

- Headers: `Authorization: Bearer <token>`
- Response (200):
  ```typescript
  {
    lists: [{
      id: string,
      name: string,
      description?: string,
      bookCount: number,
      createdAt: string,
      updatedAt: string
    }]
  }
  ```

**`POST /api/library/lists`**

- Request: `{ name: string, description?: string }`
- Response (201): `{ id: string, name: string, ... }`

**`PUT /api/library/lists/[id]`**

- Request: `{ name?: string, description?: string }`
- Response (200): `{ id: string, name: string, ... }`

**`DELETE /api/library/lists/[id]`**

- Response (200): `{ success: true }`

**`PUT /api/library/lists/[id]/reorder`**

- Request: `{ bookIds: string[] }`
- Response (200): `{ success: true, updated: number }`
- Errors:
  - 400: `{ error: "Book IDs array required" }`
  - 403: `{ error: "Not your list" }`
  - 404: `{ error: "List not found" }`

**`POST /api/library/lists/[id]/books`**

- Request: `{ bookId: string }`
- Response (201): `{ success: true }`

**`DELETE /api/library/lists/[id]/books?bookId=<id>`**

- Response (200): `{ success: true }`

### 5. Data Model Changes

**No Schema Changes** (existing `UserList` and `UserListBook` tables support all features)

**Index Verification**:

- `UserList`: `@@index([userId])` ✅ (already exists)
- `UserListBook`: `@@index([listId, position])` ✅ (already exists)

**Behavior Changes**:

- `UserListBook.position` now actively used for ordering (may have been NULL before)
- Conflict resolution: last-write-wins for metadata, merge for contents

### 6. Tests / Verification

**Unit Tests**:

- [ ] Create list returns 201 with new list ID
- [ ] Fetch lists returns all user lists with book counts
- [ ] Reorder list updates positions correctly
- [ ] Add book to list succeeds
- [ ] Remove book from list succeeds
- [ ] Concurrent add to library doesn't create duplicates

**Manual Verification**:

```bash
# Create list
curl -X POST http://localhost:3000/api/library/lists \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Favorites","description":"My favorite books"}'

# Add books to list
curl -X POST http://localhost:3000/api/library/lists/<list-id>/books \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookId":"<book-id-1>"}'

# Reorder books
curl -X PUT http://localhost:3000/api/library/lists/<list-id>/reorder \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"bookIds":["<book-id-2>","<book-id-1>","<book-id-3>"]}'

# Fetch all lists
curl http://localhost:3000/api/library/lists \
  -H "Authorization: Bearer <token>"
```

### 7. Acceptance Criteria

- [ ] iOS can create/delete custom lists via API
- [ ] iOS can add/remove books from lists
- [ ] iOS can reorder books in lists (drag-to-reorder)
- [ ] List changes sync between web and mobile within polling interval (~30s)
- [ ] Concurrent updates don't create duplicates or data corruption
- [ ] All tests pass (`npm test`)

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): add list management and reordering endpoints

- Add GET /api/library/lists (fetch all lists with book counts)
- Add POST/PUT/DELETE /api/library/lists (create/update/delete lists)
- Add PUT /api/library/lists/[id]/reorder (drag-to-reorder books)
- Add POST/DELETE /api/library/lists/[id]/books (add/remove books)
- Document conflict resolution strategy (last-write-wins + merge)
- Add concurrency tests for library operations

Enables iOS app to manage user lists with cross-device sync.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `app/api/library/lists/route.ts` (new)
- `app/api/library/lists/[id]/route.ts` (new)
- `app/api/library/lists/[id]/reorder/route.ts` (new)
- `app/api/library/lists/[id]/books/route.ts` (new)
- `docs/api-mobile.md` (updated)
- `app/api/library/concurrency.test.ts` (new)

**Notes to Record**:

- Conflict resolution strategy chosen (last-write-wins)
- Polling interval recommendation (30s)

**Resume Next Phase**: Read this file (Phase 7), CLAUDE.md, git pull, start services

---

## Phase 7: Offline Download Support ✅ / ⏳ / ❌

**Goal**: Enable iOS to download books for offline playback with S3 pre-signed URLs

### 1. Objective

Create endpoint to generate time-limited S3 pre-signed URLs for audio downloads, add download tracking for analytics and future storage quotas, implement eligibility checks, and add rate limiting to prevent abuse.

### 2. Scope

**In Scope**:

- Add `POST /api/downloads/[bookId]` to generate pre-signed S3 URL (1hr expiry)
- Add `GET /api/downloads/[bookId]/check` to validate download eligibility
- Add `UserDownload` tracking table (analytics, future quota enforcement)
- Add rate limiting (max 10 downloads per day per user)
- Document S3 pre-signed URL format and iOS URLSession integration

**Out of Scope**:

- Storage quota enforcement (future - just track for now)
- Download progress tracking (handled iOS-side)
- Resume partial downloads (S3 + iOS handle automatically)
- Automatic re-download when files updated (future feature)

### 3. Implementation Checklist

**Step 1: Add download tracking table**

- [ ] Update [prisma/schema.prisma](../prisma/schema.prisma)
  - Add model:

    ```prisma
    model UserDownload {
      id           String   @id @default(uuid())
      userId       String   @map("user_id")
      bookId       String   @map("book_id")
      downloadedAt DateTime @default(now()) @map("downloaded_at")
      deviceId     String?  @map("device_id")  // iOS sends device UUID

      user         User     @relation(fields: [userId], references: [id], onDelete: Cascade)
      book         Book     @relation(fields: [bookId], references: [id], onDelete: Cascade)

      @@index([userId, downloadedAt(sort: Desc)])
      @@index([bookId])
      @@map("user_downloads")
    }
    ```

  - Add `downloads UserDownload[]` to `User` model
  - Add `downloads UserDownload[]` to `Book` model

- [ ] Run migration: `npx prisma migrate dev --name add_user_downloads`
- [ ] Generate client: `npx prisma generate`

**Step 2: Create download eligibility endpoint**

- [ ] Create [app/api/downloads/[bookId]/check/route.ts](../app/api/downloads/%5BbookId%5D/check/route.ts)
  - `GET` handler: verify user can download this book
  - Current eligibility: Always `true` (all users can download all books in personal library)
  - Future: Check if book in user's library, check storage quota, etc.
  - Response:
    ```typescript
    {
      eligible: boolean,
      reason?: string  // If not eligible, explain why
    }
    ```

**Step 3: Create pre-signed URL endpoint**

- [ ] Create [app/api/downloads/[bookId]/route.ts](../app/api/downloads/%5BbookId%5D/route.ts)
  - `POST` handler: accept `{ deviceId?: string }`
  - Check eligibility (call internal eligibility logic)
  - Check rate limit (max 10 downloads/day via `UserDownload` count)
  - Generate S3 pre-signed URL using AWS SDK:

    ```typescript
    import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
    import { GetObjectCommand } from '@aws-sdk/client-s3';

    const command = new GetObjectCommand({
      Bucket: process.env.AWS_S3_BUCKET,
      Key: `<book-folder>/<audio-file>.mp3`,
    });
    const url = await getSignedUrl(s3Client, command, { expiresIn: 3600 });
    ```

  - Record download in `UserDownload` table
  - Response:
    ```typescript
    {
      downloadUrl: string,  // Pre-signed S3 URL
      expiresAt: string,    // ISO timestamp (1 hour from now)
      fileSize: number      // Bytes (from S3 or Book table)
    }
    ```

**Step 4: Add rate limiting logic**

- [ ] Update [lib/rate-limit.ts](../lib/rate-limit.ts) (or create if not exists)
  - Add `checkDownloadLimit(userId: string): Promise<boolean>`
  - Query `UserDownload` count for user in last 24 hours
  - Return `false` if count >= 10
- [ ] Apply to download endpoint (return 429 if exceeded)

**Step 5: Add download history endpoint (optional)**

- [ ] Create [app/api/downloads/route.ts](../app/api/downloads/route.ts)
  - `GET` handler: fetch user's download history
  - Response:
    ```typescript
    {
      downloads: [{
        bookId: string,
        bookTitle: string,
        downloadedAt: string,
        deviceId?: string
      }],
      dailyCount: number  // Downloads in last 24h
    }
    ```

**Step 6: Document iOS integration**

- [ ] Update [docs/api-mobile.md](../docs/api-mobile.md)
  - Add section: "Offline Downloads"
  - Document download flow:
    1. Check eligibility: `GET /api/downloads/[bookId]/check`
    2. Request download URL: `POST /api/downloads/[bookId]`
    3. Download file with URLSession background task
    4. Store file in app's Documents directory
  - Document S3 pre-signed URL format (standard AWS format)
  - Document URL expiry (1 hour - complete download within this time)
  - Add Swift code example:
    ```swift
    let task = URLSession.shared.downloadTask(with: downloadURL) { localURL, response, error in
      // Move file to permanent location
      try? FileManager.default.moveItem(at: localURL, to: permanentURL)
    }
    task.resume()
    ```

**Step 7: Handle non-S3 development mode**

- [ ] Update download endpoint to handle local file mode
  - If `AWS_S3_BUCKET` not configured, return error or local file URL
  - Recommend: Return 501 (Not Implemented) in development, document S3 required for downloads

### 4. API Contract Changes

**New Endpoints**:

**`GET /api/downloads/[bookId]/check`**

- Headers: `Authorization: Bearer <token>`
- Response (200): `{ eligible: boolean, reason?: string }`
- Errors:
  - 401: `{ error: "Unauthorized" }`
  - 404: `{ error: "Book not found" }`

**`POST /api/downloads/[bookId]`**

- Headers: `Authorization: Bearer <token>`
- Request: `{ deviceId?: string }`
- Response (200):
  ```typescript
  {
    downloadUrl: string,
    expiresAt: string,
    fileSize: number
  }
  ```
- Errors:
  - 400: `{ error: "Invalid request" }`
  - 401: `{ error: "Unauthorized" }`
  - 403: `{ error: "Download not allowed", reason: "..." }`
  - 404: `{ error: "Book not found" }`
  - 429: `{ error: "Download limit exceeded (10/day)" }`
  - 501: `{ error: "Downloads require S3 configuration" }` (development mode)

**`GET /api/downloads`** (optional)

- Headers: `Authorization: Bearer <token>`
- Response (200):
  ```typescript
  {
    downloads: [{
      bookId: string,
      bookTitle: string,
      downloadedAt: string
    }],
    dailyCount: number
  }
  ```

### 5. Data Model Changes

**New Table: `UserDownload`**

- Fields: `id`, `userId`, `bookId`, `downloadedAt`, `deviceId`
- Indexes: `[userId, downloadedAt]`, `[bookId]`
- Cascade delete when user or book deleted

**Migration**:

```bash
npx prisma migrate dev --name add_user_downloads
```

**Backward Compatibility**:

- New feature, no breaking changes
- Download tracking is additive

### 6. Tests / Verification

**Unit Tests**:

- [ ] Create [app/api/downloads/route.test.ts](../app/api/downloads/route.test.ts)
  - Check eligibility returns true for valid book
  - Generate download URL returns pre-signed S3 URL
  - Rate limit enforced (11th download in 24h rejected)
  - Download recorded in UserDownload table
  - Unauthorized request returns 401

**Manual Verification**:

```bash
# Check eligibility
curl http://localhost:3000/api/downloads/<book-id>/check \
  -H "Authorization: Bearer <token>"
# Expected: { eligible: true }

# Request download URL
curl -X POST http://localhost:3000/api/downloads/<book-id> \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"iOS-device-uuid"}'
# Expected: { downloadUrl: "https://s3...", expiresAt: "...", fileSize: 12345678 }

# Test rate limit (11th download)
# (Run 11 download requests within 24h)
# Expected: 11th returns 429

# Verify download recorded
# Check Prisma Studio: http://localhost:5555
# UserDownload table should have entries
```

**Integration Test**:

- [ ] Download URL is valid (can download file with curl)
- [ ] URL expires after 1 hour (test with delayed request)
- [ ] Download count increments correctly

### 7. Acceptance Criteria

- [ ] iOS can check download eligibility via `GET /api/downloads/[bookId]/check`
- [ ] iOS can request pre-signed S3 URL via `POST /api/downloads/[bookId]`
- [ ] Pre-signed URL is valid for 1 hour
- [ ] Downloads are tracked in `UserDownload` table (userId, bookId, timestamp)
- [ ] Rate limiting enforced (max 10 downloads per day per user)
- [ ] All tests pass (`npm test`)
- [ ] S3 configuration required (501 error in development without S3)

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): add offline download support with S3 pre-signed URLs

- Add UserDownload table for tracking downloads
- Create POST /api/downloads/[bookId] (generate pre-signed S3 URLs)
- Create GET /api/downloads/[bookId]/check (eligibility validation)
- Add rate limiting (max 10 downloads/day per user)
- Document iOS URLSession integration for background downloads

Enables iOS app to download audiobooks for offline playback.
Downloads tracked for future analytics and quota enforcement.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `prisma/migrations/*_add_user_downloads/migration.sql` (new)
- `prisma/schema.prisma` (updated)
- `app/api/downloads/[bookId]/route.ts` (new)
- `app/api/downloads/[bookId]/check/route.ts` (new)
- `app/api/downloads/route.ts` (new, optional)
- `lib/rate-limit.ts` (updated)
- `docs/api-mobile.md` (updated)
- `app/api/downloads/route.test.ts` (new)

**Notes to Record**:

- Rate limit threshold (10/day)
- S3 pre-signed URL expiry (1 hour)
- Future: Consider storage quotas, analytics on popular downloads

**Resume Next Phase**: Read this file (Phase 8), CLAUDE.md, git pull, start services

---

## Phase 8: Push Notifications & Background Sync (Optional) ✅ / ⏳ / ❌

**Goal**: Enable push notifications for new books, progress sync updates, and other events

### 1. Objective

Set up push notification infrastructure with device token registration, notification preferences, and triggered push delivery. Choose APNs direct for simplicity and privacy.

### 2. Scope

**In Scope**:

- Choose push provider (APNs direct recommended)
- Add `POST /api/devices` to register iOS device tokens
- Add `PUT /api/user/notifications` to manage preferences
- Implement push triggers (new book added, playback synced from web, etc.)
- Add background job queue for async push delivery (optional: BullMQ or simple queue)
- Add logging for push delivery success/failure

**Out of Scope**:

- Android push support (FCM) - future if Android app planned
- Rich push notifications (images, actions) - future enhancement
- Notification history/inbox in app - future feature
- Scheduled notifications (e.g., "continue listening" reminders) - future feature

### 3. Implementation Checklist

**Step 1: Choose push provider**

- [ ] **Decision**: Use APNs direct (recommended)
  - Pros: No third-party dependencies, better privacy, simpler setup
  - Cons: iOS-only (need FCM for Android if planned)
- [ ] Alternative: OneSignal (if multi-platform planned)
- [ ] Create Apple Developer account if not exists
- [ ] Generate APNs auth key (.p8 file) from Apple Developer portal
- [ ] Add to environment variables:
  ```bash
  APNS_KEY_ID="..."
  APNS_TEAM_ID="..."
  APNS_KEY_PATH="/path/to/AuthKey_XXX.p8"
  APNS_TOPIC="com.bookvault.app"  # iOS bundle ID
  APNS_PRODUCTION="false"  # Set true for production
  ```

**Step 2: Add device registration table**

- [ ] Update [prisma/schema.prisma](../prisma/schema.prisma)
  - Add model:

    ```prisma
    model UserDevice {
      id           String   @id @default(uuid())
      userId       String   @map("user_id")
      deviceToken  String   @map("device_token")  // APNs device token
      platform     String   // "ios" or "android"
      deviceName   String?  @map("device_name")   // e.g., "Demetri's iPhone"
      isActive     Boolean  @default(true) @map("is_active")
      createdAt    DateTime @default(now()) @map("created_at")
      lastSeenAt   DateTime @default(now()) @map("last_seen_at")

      user         User     @relation(fields: [userId], references: [id], onDelete: Cascade)

      @@unique([deviceToken])
      @@index([userId])
      @@map("user_devices")
    }
    ```

  - Add `devices UserDevice[]` to `User` model

- [ ] Run migration: `npx prisma migrate dev --name add_user_devices`
- [ ] Generate client: `npx prisma generate`

**Step 3: Create device registration endpoint**

- [ ] Create [app/api/devices/route.ts](../app/api/devices/route.ts)
  - `POST` handler: accept `{ deviceToken: string, platform: "ios", deviceName?: string }`
  - Upsert device (update `lastSeenAt` if exists, create if new)
  - Response: `{ id: string, success: true }`
- [ ] Add `DELETE` handler: remove device token (when user logs out or uninstalls)

**Step 4: Create notification preferences endpoint**

- [ ] Update [prisma/schema.prisma](../prisma/schema.prisma)
  - Add to `User` model:
    ```prisma
    notifyNewBooks       Boolean @default(true) @map("notify_new_books")
    notifyProgressSync   Boolean @default(true) @map("notify_progress_sync")
    notifyListChanges    Boolean @default(false) @map("notify_list_changes")
    ```
- [ ] Run migration: `npx prisma migrate dev --name add_notification_preferences`
- [ ] Create [app/api/user/notifications/route.ts](../app/api/user/notifications/route.ts)
  - `GET` handler: fetch current preferences
  - `PUT` handler: update preferences `{ notifyNewBooks?: boolean, ... }`

**Step 5: Set up APNs client**

- [ ] Install: `npm install apns2`
- [ ] Create [lib/push-notifications.ts](../lib/push-notifications.ts)
  - Initialize APNs client:

    ```typescript
    import apn from 'apns2';

    const client = new apn.Client({
      team: process.env.APNS_TEAM_ID,
      keyId: process.env.APNS_KEY_ID,
      signingKey: fs.readFileSync(process.env.APNS_KEY_PATH),
      defaultTopic: process.env.APNS_TOPIC,
      production: process.env.APNS_PRODUCTION === 'true',
    });
    ```

  - Add function: `sendPushNotification(deviceToken, title, body, data?)`
  - Handle errors (invalid token, expired token) - mark device as inactive

**Step 6: Implement push triggers**

- [ ] Create [lib/push-triggers.ts](../lib/push-triggers.ts)
  - `notifyNewBook(userId, book)`: Send push when new book added to user's library
  - `notifyProgressSync(userId, book)`: Send push when playback position updated from web
  - `notifyListChange(userId, listName)`: Send push when list updated from web
- [ ] Call triggers from relevant endpoints:
  - New book: Import script or library add endpoint
  - Progress sync: `/api/progress` when position updated
  - List change: `/api/library/lists/*` when list modified

**Step 7: Add background job queue (optional but recommended)**

- [ ] Choose queue: BullMQ (Redis-based) or simple in-memory queue
- [ ] If BullMQ:
  - Install: `npm install bullmq ioredis`
  - Create [lib/queue.ts](../lib/queue.ts)
  - Define job types: `send-push-notification`
  - Worker processes jobs and calls `sendPushNotification`
- [ ] If simple queue:
  - Use in-memory array + setInterval processor
  - Less robust but simpler for MVP

**Step 8: Add push delivery logging**

- [ ] Update [lib/push-notifications.ts](../lib/push-notifications.ts)
  - Log successful pushes: `console.log('Push sent', { userId, deviceToken, title })`
  - Log failures: `console.error('Push failed', { userId, deviceToken, error })`
  - Store delivery status in database (optional: `PushNotificationLog` table)

### 4. API Contract Changes

**New Endpoints**:

**`POST /api/devices`**

- Headers: `Authorization: Bearer <token>`
- Request: `{ deviceToken: string, platform: "ios", deviceName?: string }`
- Response (200): `{ id: string, success: true }`
- Errors:
  - 400: `{ error: "Device token and platform required" }`
  - 401: `{ error: "Unauthorized" }`

**`DELETE /api/devices?deviceToken=<token>`**

- Headers: `Authorization: Bearer <token>`
- Response (200): `{ success: true }`

**`GET /api/user/notifications`**

- Headers: `Authorization: Bearer <token>`
- Response (200):
  ```typescript
  {
    notifyNewBooks: boolean,
    notifyProgressSync: boolean,
    notifyListChanges: boolean
  }
  ```

**`PUT /api/user/notifications`**

- Headers: `Authorization: Bearer <token>`
- Request: `{ notifyNewBooks?: boolean, notifyProgressSync?: boolean, notifyListChanges?: boolean }`
- Response (200): `{ success: true, preferences: {...} }`

### 5. Data Model Changes

**New Table: `UserDevice`**

- Fields: `id`, `userId`, `deviceToken`, `platform`, `deviceName`, `isActive`, `createdAt`, `lastSeenAt`
- Indexes: `[deviceToken]` (unique), `[userId]`
- Cascade delete when user deleted

**Updated Table: `User`**

- New fields: `notifyNewBooks`, `notifyProgressSync`, `notifyListChanges` (boolean flags)

**Migrations**:

```bash
npx prisma migrate dev --name add_user_devices
npx prisma migrate dev --name add_notification_preferences
```

**Backward Compatibility**:

- New fields have defaults (notifications enabled by default)
- Existing users can opt out via preferences endpoint

### 6. Tests / Verification

**Unit Tests**:

- [ ] Create [app/api/devices/route.test.ts](../app/api/devices/route.test.ts)
  - Register device token succeeds
  - Duplicate device token updates `lastSeenAt`
  - Delete device token succeeds
- [ ] Create [lib/push-notifications.test.ts](../lib/push-notifications.test.ts)
  - Send push notification (mock APNs client)
  - Handle invalid device token (mark device inactive)

**Manual Verification**:

```bash
# Register device
curl -X POST http://localhost:3000/api/devices \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"deviceToken":"<ios-device-token>","platform":"ios","deviceName":"Test iPhone"}'

# Update notification preferences
curl -X PUT http://localhost:3000/api/user/notifications \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"notifyNewBooks":true,"notifyProgressSync":false}'

# Trigger test push (internal function call or test endpoint)
# Verify push received on iOS device
```

**Integration Test**:

- [ ] iOS app registers for push notifications on first launch
- [ ] Device token saved in `UserDevice` table
- [ ] Test push notification received on device
- [ ] Push notification triggers on progress sync from web

### 7. Acceptance Criteria

- [ ] iOS can register for push notifications via `POST /api/devices`
- [ ] Backend can send test push notification to registered device
- [ ] Push triggers implemented (new book, progress sync, list changes)
- [ ] User can manage notification preferences via API
- [ ] Failed push deliveries logged (invalid/expired tokens)
- [ ] All tests pass (`npm test`)

### 8. Stop Point & Handoff

**Commit Message**:

```
feat(mobile): add push notifications with APNs integration

- Add UserDevice table for device token registration
- Create POST /api/devices (register device for push)
- Create PUT /api/user/notifications (manage preferences)
- Implement APNs client for push delivery
- Add push triggers (new books, progress sync, list changes)
- Add logging for push delivery success/failure

Enables iOS app to receive push notifications for key events.
APNs direct integration for simplicity and privacy.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Required Files**:

- `prisma/migrations/*_add_user_devices/migration.sql` (new)
- `prisma/migrations/*_add_notification_preferences/migration.sql` (new)
- `prisma/schema.prisma` (updated)
- `app/api/devices/route.ts` (new)
- `app/api/user/notifications/route.ts` (new)
- `lib/push-notifications.ts` (new)
- `lib/push-triggers.ts` (new)
- `lib/queue.ts` (new, if using BullMQ)
- `app/api/devices/route.test.ts` (new)
- `.env.example` (updated with APNs vars)

**Notes to Record**:

- APNs configuration (team ID, key ID, topic)
- Push triggers implemented
- Background job queue choice (BullMQ vs simple)

**Resume Next Session**: Phase 8 is final phase. Deploy to production!

---

## Summary

**Total Phases**: 8 (Phases 1–7 core, Phase 8 optional)

**Completion Tracking**: Update phase headings with status:

- ✅ Done
- ⏳ In Progress
- ❌ Blocked/Skipped

**Estimated Effort**:

- Phase 1: 2-3 hours (auth + JWT + refresh tokens)
- Phase 2: 1-2 hours (batch sync + indexing)
- Phase 3: 1 hour (validation + docs)
- Phase 4: 1 hour (chapter optimization)
- Phase 5: 2 hours (search + pagination + autocomplete)
- Phase 6: 2 hours (lists + reordering)
- Phase 7: 2-3 hours (downloads + S3 pre-signed URLs)
- Phase 8: 3-4 hours (push notifications + APNs)

**Total**: ~14-18 hours (excluding Phase 8: ~11-14 hours)

**Post-Implementation**:

1. Deploy to AWS (ECS/Lambda + RDS + S3)
2. Update mobile CORS origins (lock down from `*`)
3. Configure CloudFront CDN for S3 assets
4. Monitor API performance and tune indexes
5. Begin iOS app development (use [mobile-ios-plan.md](mobile-ios-plan.md))
