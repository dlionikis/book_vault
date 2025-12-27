# iOS-Backend Synchronization Tracker

**Last Updated**: December 25, 2025

> **TL;DR**: Track API changes and their iOS impact. Update this file whenever modifying APIs.

---

## Purpose

This document tracks synchronization points between the backend (Next.js) and iOS app (Swift/SwiftUI). Use this to:

1. **Coordinate API changes** - Understand iOS impact before changing backend
2. **Track implementation status** - What's implemented in iOS vs backend
3. **Plan breaking changes** - Version APIs that iOS depends on
4. **Facilitate handoffs** - Clear status for AI-assisted development

---

## API Change Workflow

When making API changes:

1. **Document change here** with iOS impact analysis
2. **Update OpenAPI spec** (`docs/api/openapi.yaml`)
3. **Regenerate types** (`npm run api:generate`)
4. **Implement backend** changes
5. **Test backend** with updated contract
6. **Update iOS** code if needed
7. **Test integration** (both systems)
8. **Commit atomically** (backend + iOS + OpenAPI)

---

## Current Sync Status

### Authentication ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 1)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `POST /api/auth/login` - ✅ Backend ready, ⏳ iOS pending
- `POST /api/auth/logout` - ✅ Backend ready, ⏳ iOS pending
- `GET /api/auth/validate` - ⏳ Needs implementation

**iOS Impact**: Phase 1 - Auth & Browsing
**Action Required**: Document in OpenAPI, implement token validation endpoint

---

### Books API ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 1)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/books` - ✅ Backend ready, ⏳ iOS pending
  - Pagination: ✅ Implemented
  - Filtering: ⏳ Could add filters (author, narrator, series)
- `GET /api/books/:id` - ✅ Backend ready, ⏳ iOS pending

**iOS Impact**: Phase 1 - Auth & Browsing
**Action Required**: Document in OpenAPI, consider adding filters

---

### Chapters API ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 5)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/books/:id/chapters` - ✅ Backend ready, ⏳ iOS pending

**iOS Impact**: Phase 5 - Chapter Navigation
**Action Required**: Document in OpenAPI

---

### Progress API ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 4)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/progress?bookId={id}` - ✅ Backend ready, ⏳ iOS pending
- `POST /api/progress` - ✅ Backend ready, ⏳ iOS pending

**iOS Impact**: Phase 4 - Progress Sync
**Action Required**: Document in OpenAPI

**Special Considerations**:

- iOS will auto-save every 10 seconds during playback
- Backend should handle rapid updates gracefully
- Consider rate limiting if needed

---

### Search API ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 6)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/search?q={query}&type={type}` - ✅ Backend ready, ⏳ iOS pending

**iOS Impact**: Phase 6 - Search & Browse
**Action Required**: Document in OpenAPI

---

### Browse API ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 6)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/browse/authors` - ✅ Backend ready, ⏳ iOS pending
- `GET /api/browse/series` - ✅ Backend ready, ⏳ iOS pending
- `GET /api/browse/narrators` - ✅ Backend ready, ⏳ iOS pending
- `GET /api/browse/categories` - ✅ Backend ready, ⏳ iOS pending
- `GET /api/browse/authors/:id/books` - ✅ Backend ready, ⏳ iOS pending
- `GET /api/browse/series/:id/books` - ✅ Backend ready, ⏳ iOS pending

**iOS Impact**: Phase 6 - Search & Browse
**Action Required**: Document in OpenAPI

---

### Library API ✅ Ready

**Backend Status**: Implemented
**iOS Status**: Not started (Phase 7)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/library` - ✅ Backend ready, ⏳ iOS pending
- `POST /api/library/add` - ✅ Backend ready, ⏳ iOS pending
- `POST /api/library/remove` - ✅ Backend ready, ⏳ iOS pending

**iOS Impact**: Phase 7 - User Lists
**Action Required**: Document in OpenAPI

---

### User Lists API ⚠️ Partially Ready

**Backend Status**: Partially implemented
**iOS Status**: Not started (Phase 7)
**OpenAPI Status**: ✅ Documented

**Endpoints**:

- `GET /api/lists` - ⏳ Needs implementation
- `GET /api/lists/:id` - ⏳ Needs implementation
- `GET /api/lists/:id/books` - ⏳ Needs implementation
- `POST /api/lists` - ⏳ Needs implementation
- `PUT /api/lists/:id` - ⏳ Needs implementation
- `DELETE /api/lists/:id` - ⏳ Needs implementation
- `POST /api/lists/:id/books` - ⏳ Needs implementation
- `DELETE /api/lists/:id/books/:bookId` - ⏳ Needs implementation
- `PUT /api/lists/:id/reorder` - ⏳ Needs implementation

**iOS Impact**: Phase 7 - User Lists
**Action Required**: Implement backend endpoints, document in OpenAPI

---

### Media Streaming ✅ Ready

**Backend Status**: Implemented (S3 + range requests)
**iOS Status**: Not started (Phase 2)
**OpenAPI Status**: N/A (direct URLs)

**Endpoints**:

- Images: S3 URLs with caching headers
- Audio: S3 URLs with range request support

**iOS Impact**: Phase 2 - Audio Playback
**Action Required**: None (iOS uses direct S3 URLs from book.audioUrl)

**Special Considerations**:

- iOS AVPlayer requires range request support ✅ Implemented
- Cover images should be served with proper cache headers ✅ Implemented
- Audio URLs must be absolute URLs ✅ Implemented

---

## Planned API Changes

### Token Refresh Endpoint

**Priority**: High (required for Phase 1)
**Endpoint**: `POST /api/auth/refresh`

**Request**:

```typescript
{
  refreshToken: string;
}
```

**Response**:

```typescript
{
  token: string;
  refreshToken: string;
}
```

**Backend Status**: ⏳ Not implemented
**iOS Impact**: Phase 1 - Required for token management
**Action Required**: Implement backend endpoint, update OpenAPI

---

### Bookmarks API (Future)

**Priority**: Low (post-MVP)
**Endpoints**: TBD

**Backend Status**: ⏳ Not implemented
**iOS Impact**: Future feature
**Action Required**: Design API, implement backend, document OpenAPI

---

### Download API (Future)

**Priority**: Medium (Phase 8)
**Endpoints**: TBD

**Backend Status**: ⏳ Not implemented
**iOS Impact**: Phase 8 - Offline Downloads
**Action Required**: Design API for download management

**Considerations**:

- Track downloaded books per user
- Manage download expiration
- Handle download resumption
- Or: iOS manages downloads locally without backend tracking

---

## Recent Changes

### 2025-12-25: Initial iOS Planning

**Changes**:

- Created iOS development plan
- Documented all existing APIs
- Identified gaps (token refresh, user lists)

**iOS Impact**: None (planning phase)

---

## Breaking Changes Policy

**Versioning Strategy**:

- Use semantic versioning for API (v1, v2, etc.)
- Add version prefix to breaking changes: `/api/v2/books`
- Maintain v1 endpoints until iOS migrates
- Coordinate breaking changes with iOS releases

**Example**:

```
Old: GET /api/books
New: GET /api/v2/books (with different response structure)
iOS: Update to v2 after backend deploys
Cleanup: Remove v1 endpoints after iOS migration complete
```

---

## OpenAPI Generation Status

### Backend (TypeScript)

**Status**: ✅ Tooling installed (Phase 0 complete)
**Command**: `npm run api:generate:ts`
**Output**: `lib/api-types.ts`
**Tooling**: `openapi-typescript` + `@redocly/cli`

**Action Required**: Create OpenAPI spec (Phase 1)

---

### iOS (Swift)

**Status**: ✅ Complete
**Command**: `npm run api:generate:swift`
**Output**: `ios/BookVault/Generated/Models/`
**Tooling**: `openapi-generator` (Homebrew)

**Verification**: 47 Swift models generated and compiling successfully

---

## Testing Coordination

### Shared Test Fixtures

**Status**: ✅ Complete
**Location**: `test-fixtures/`

**Files Created** (7 fixtures, 76K total):

- `books-list.json` (11K) - Paginated book list
- `book-detail.json` (27K) - Full book with all relations
- `user-progress.json` (71B) - User progress data
- `chapters-list.json` (101B) - Chapter metadata
- `search-results.json` (5.8K) - Search results
- `author-books.json` (9.8K) - Author with books
- `browse-authors.json` (1.1K) - Browse authors list

**Verification**: All fixtures validated as valid JSON and ready for testing

---

### Contract Testing

**Status**: ⏳ Not started

**Backend Tests** (`__tests__/api/mobile-integration.test.ts`):

- Validate responses match OpenAPI schema
- Ensure mobile-friendly URLs (absolute paths)
- Test pagination, filtering, sorting
- Verify error responses

**iOS Tests** (`BookVaultTests/Services/APIClientTests.swift`):

- Mock URLSession with test fixtures
- Validate request construction
- Test error handling
- Verify model decoding

**Action Required**: Implement contract tests on both sides

---

## Next Steps

### Before iOS Development Starts

1. ✅ **Setup Code Generation** (Phase 0 complete):
   - ✅ Install tooling (openapi-typescript, @redocly/cli, openapi-generator)
   - ✅ Add npm scripts
   - ⏳ Test generation with sample spec (after Phase 1)

2. **Create OpenAPI Specification** (Phase 1):
   - Document all existing endpoints
   - Define request/response schemas
   - Add authentication requirements
   - Include examples

3. **Implement Missing Endpoints**:
   - Token refresh endpoint
   - Token validation endpoint
   - User lists CRUD operations

4. **Create Test Fixtures**:
   - Export sample data from backend
   - Anonymize sensitive information
   - Share between backend and iOS tests

5. **Setup iOS Project**:
   - Create Xcode project in `ios/`
   - Configure for monorepo
   - Setup generated code directory

---

## Contact Points for Coordination

**When changing authentication**:

- Update: Auth endpoints, JWT structure, token expiry
- iOS Impact: Keychain storage, token refresh logic
- Coordinate: Before deploying breaking changes

**When changing book data structure**:

- Update: Book model, API responses
- iOS Impact: Codable models, UI display logic
- Coordinate: Version API if breaking

**When changing progress sync**:

- Update: Progress endpoints, sync frequency
- iOS Impact: Auto-save timing, conflict resolution
- Coordinate: Backward compatibility for migration

**When adding new features**:

- Update: OpenAPI spec first
- iOS Impact: Generate models, implement UI
- Coordinate: Feature flags for gradual rollout

---

## Useful Commands

```bash
# Validate OpenAPI spec (using Redocly)
npm run api:validate

# Generate API documentation
npm run api:docs

# Generate types for both platforms
npm run api:generate

# Generate everything (types + docs)
npm run docs:generate

# Watch OpenAPI for changes
npm run api:watch

# Run backend in mobile mode
npm run dev:mobile

# Test mobile APIs
npm test -- mobile-integration
```

---

## Reference Documentation

- [API Quick Reference](api-quick-ref.md) - Current API endpoints
- [Mobile iOS Plan](mobile-ios-plan.md) - Overall iOS strategy
- [API Integration Guide](mobile/api-integration.md) - iOS implementation examples
- [Implementation Phases](mobile/implementation-phases.md) - iOS development phases
