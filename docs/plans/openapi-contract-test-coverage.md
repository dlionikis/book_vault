# OpenAPI Contract Test Coverage Implementation Plan

**Created**: January 3, 2026
**Status**: Planning
**Priority**: Medium-High (ensures API stability for iOS + Web)

---

## Overview

This plan addresses the gap in OpenAPI contract test coverage. Currently, only **43% (18/42)** of API endpoints have contract tests. This plan outlines a phased approach to achieve **100% coverage**.

### Why This Matters

1. **iOS Stability** - Contract tests ensure the API responses match what the iOS app expects
2. **Regression Prevention** - Catches breaking changes before they reach production
3. **Documentation Accuracy** - Validates that OpenAPI spec matches actual implementation
4. **CI/CD Gate** - Prevents merging code that breaks API contracts

---

## Current State

### Endpoints WITH Contract Tests (18)

| Category | Endpoints                                                                                 | Coverage |
| -------- | ----------------------------------------------------------------------------------------- | -------- |
| Books    | `GET /api/books`, `GET /api/books/{id}`                                                   | 2/2      |
| Browse   | All 8 endpoints (authors, series, narrators, categories - list + detail)                  | 8/8      |
| Progress | `GET`, `POST`, `PUT /api/progress`                                                        | 3/4      |
| Auth     | `POST /api/auth/mobile/login`, `POST /api/auth/mobile/refresh`, `POST /api/auth/register` | 3/5      |
| Search   | `GET /api/search`                                                                         | 1/2      |
| Library  | `GET /api/library`, `POST /api/library`, `DELETE /api/library/{bookId}`                   | 3/13     |
| Chapters | `GET /api/books/{id}/chapters`                                                            | 1/2      |

### Endpoints WITHOUT Contract Tests (24)

| Priority | Category       | Endpoint                                | Notes                             |
| -------- | -------------- | --------------------------------------- | --------------------------------- |
| **P0**   | Auth           | `POST /api/auth/mobile/verify`          | Critical for iOS token validation |
| **P0**   | Auth           | `POST /api/auth/mobile/logout`          | Critical for iOS - token rotation |
| **P1**   | Progress       | `POST /api/progress/batch`              | iOS offline sync                  |
| **P1**   | Search         | `GET /api/search/suggestions`           | iOS autocomplete                  |
| **P1**   | Library        | `GET /api/library/check`                | iOS library status                |
| **P2**   | Library Lists  | `GET /api/library/lists`                | User lists feature                |
| **P2**   | Library Lists  | `POST /api/library/lists`               | Create list                       |
| **P2**   | Library Lists  | `PUT /api/library/lists/{id}`           | Update list                       |
| **P2**   | Library Lists  | `DELETE /api/library/lists/{id}`        | Delete list                       |
| **P2**   | Library Lists  | `POST /api/library/lists/{id}/books`    | Add book to list                  |
| **P2**   | Library Lists  | `DELETE /api/library/lists/{id}/books`  | Remove book from list             |
| **P2**   | Library Lists  | `PUT /api/library/lists/{id}/reorder`   | Reorder list                      |
| **P2**   | Library Series | `POST /api/library/series/{seriesId}`   | Add series to library             |
| **P2**   | Library Series | `DELETE /api/library/series/{seriesId}` | Remove series from library        |
| **P1**   | Downloads      | `GET /api/downloads`                    | Download history                  |
| **P1**   | Downloads      | `POST /api/downloads/{bookId}`          | Generate download URL             |
| **P1**   | Downloads      | `GET /api/downloads/{bookId}/check`     | Check download eligibility        |
| **P2**   | Chapters       | `POST /api/books/{id}/chapters`         | Re-extract chapters               |
| **P2**   | User           | `PUT /api/user/password`                | Password change                   |
| **P3**   | Media          | `GET /api/audio/{path}`                 | Audio streaming (complex)         |
| **P3**   | Media          | `GET /api/images/{path}`                | Image streaming                   |
| **P3**   | Health         | `GET /api/health`                       | Simple health check               |

---

## Implementation Phases

### Phase 1: Critical iOS Auth Endpoints (P0)

**Estimated Tests**: 6-8
**Files Modified**: `__tests__/api/openapi-contract.test.ts`

#### 1.1 POST /api/auth/mobile/verify

```typescript
describe('POST /api/auth/mobile/verify', () => {
  testFn('should return valid:true for valid token', async () => {
    // Use token from getAuthToken()
    // Verify response: { valid: true, user: { id, email } }
  });

  testFn('should return valid:false for invalid token', async () => {
    // Send request with invalid/expired token
    // Verify response: { valid: false, user: null }
  });
});
```

#### 1.2 POST /api/auth/mobile/logout

```typescript
describe('POST /api/auth/mobile/logout', () => {
  testFn('should satisfy OpenAPI spec for successful logout', async () => {
    // Login to get tokens
    // Call logout with refreshToken
    // Verify 200 response: { message: 'Logged out successfully' }
  });

  testFn('should return 401 for invalid refresh token', async () => {
    // Call logout with invalid refreshToken
    // Verify 401 response
  });
});
```

---

### Phase 2: iOS Feature Endpoints (P1)

**Estimated Tests**: 12-15

#### 2.1 POST /api/progress/batch

```typescript
describe('POST /api/progress/batch', () => {
  testFn('should satisfy OpenAPI spec for batch update', async () => {
    // Send array of progress updates with timestamps
    // Verify: { updated: number, conflicts: number, details: [...] }
  });

  testFn('should return 400 for missing updates array', async () => {
    // Send empty body
    // Verify 400 response
  });

  testFn('should handle timestamp conflicts correctly', async () => {
    // Send update with old timestamp
    // Verify conflict is reported in details
  });
});
```

#### 2.2 GET /api/search/suggestions

```typescript
describe('GET /api/search/suggestions', () => {
  testFn('should return suggestions for valid query', async () => {
    // Search with q=test (2+ chars)
    // Verify: { books: [], authors: [], narrators: [] }
  });

  testFn('should return 400 for query < 2 chars', async () => {
    // Search with q=a
    // Verify 400 response
  });
});
```

#### 2.3 GET /api/library/check

```typescript
describe('GET /api/library/check', () => {
  testFn('should return inLibrary status', async () => {
    // Check book in library
    // Verify: { inLibrary: boolean }
  });

  testFn('should return 400 for missing bookId', async () => {
    // Call without bookId param
    // Verify 400 response
  });
});
```

#### 2.4 Downloads Endpoints

```typescript
describe('Downloads Endpoints', () => {
  describe('GET /api/downloads', () => {
    testFn('should return download history', async () => {
      // Verify: { downloads: [], dailyCount: number }
    });
  });

  describe('POST /api/downloads/{bookId}', () => {
    testFn('should return 501 when S3 not configured', async () => {
      // In dev environment, S3 is not configured
      // Verify 501 response
    });

    testFn('should return 404 for non-existent book', async () => {
      // Use invalid bookId
      // Verify 404 response
    });
  });

  describe('GET /api/downloads/{bookId}/check', () => {
    testFn('should return eligibility for valid book', async () => {
      // Verify: { eligible: boolean }
    });

    testFn('should return 404 for non-existent book', async () => {
      // Verify 404 response
    });
  });
});
```

---

### Phase 3: Library Lists Feature (P2)

**Estimated Tests**: 20-25

#### 3.1 List CRUD Operations

```typescript
describe('Library Lists Endpoints', () => {
  let testListId: string;

  describe('GET /api/library/lists', () => {
    testFn('should return user lists', async () => {
      // Verify: { lists: [{ id, name, bookCount, createdAt, updatedAt }] }
    });
  });

  describe('POST /api/library/lists', () => {
    testFn('should create new list', async () => {
      // Create list with name + description
      // Verify 201 response with list object
      // Save testListId for later tests
    });

    testFn('should return 400 for missing name', async () => {
      // Verify 400 response
    });
  });

  describe('PUT /api/library/lists/{id}', () => {
    testFn('should update list metadata', async () => {
      // Update name/description
      // Verify 200 response
    });

    testFn('should return 404 for non-existent list', async () => {
      // Verify 404 response
    });
  });

  describe('DELETE /api/library/lists/{id}', () => {
    testFn('should delete list', async () => {
      // Verify: { success: true }
    });
  });
});
```

#### 3.2 List Book Management

```typescript
describe('List Book Management', () => {
  describe('POST /api/library/lists/{id}/books', () => {
    testFn('should add book to list', async () => {
      // Verify 201: { success: true }
    });

    testFn('should return 404 for non-existent list', async () => {
      // Verify 404 response
    });
  });

  describe('DELETE /api/library/lists/{id}/books', () => {
    testFn('should remove book from list', async () => {
      // Verify: { success: true }
    });
  });

  describe('PUT /api/library/lists/{id}/reorder', () => {
    testFn('should reorder books in list', async () => {
      // Send bookIds array
      // Verify: { success: true, updated: number }
    });
  });
});
```

#### 3.3 Series Library Management

```typescript
describe('Series Library Management', () => {
  describe('POST /api/library/series/{seriesId}', () => {
    testFn('should add series to library', async () => {
      // Verify: { message, added, total }
    });

    testFn('should return 404 for non-existent series', async () => {
      // Verify 404 response
    });
  });

  describe('DELETE /api/library/series/{seriesId}', () => {
    testFn('should remove series from library', async () => {
      // Verify: { message, removed }
    });
  });
});
```

---

### Phase 4: Remaining Endpoints (P2-P3)

**Estimated Tests**: 8-10

#### 4.1 Chapter Re-extraction

```typescript
describe('POST /api/books/{id}/chapters', () => {
  testFn('should re-extract chapters', async () => {
    // Note: Requires ffprobe, may return source: 'unavailable'
    // Verify response matches spec
  });

  testFn('should return 404 for non-existent book', async () => {
    // Verify 404 response
  });
});
```

#### 4.2 User Password

```typescript
describe('PUT /api/user/password', () => {
  // Note: Cannot test success case without breaking test user
  testFn('should return 400 for wrong current password', async () => {
    // Send wrong currentPassword
    // Verify 400 response
  });

  testFn('should return 400 for weak new password', async () => {
    // Send newPassword < 8 chars
    // Verify 400 response
  });
});
```

#### 4.3 Health Check

```typescript
describe('GET /api/health', () => {
  testFn('should return healthy status', async () => {
    // No auth required
    // Verify: { status: 'ok' }
  });
});
```

---

### Phase 5: Media Streaming (P3 - Special Handling)

**Estimated Tests**: 4-6

Media endpoints require special handling due to binary responses.

#### 5.1 Image Streaming

```typescript
describe('GET /api/images/{path}', () => {
  testFn('should return image with correct headers', async () => {
    // Get a book with coverUrl
    // Extract path from coverUrl
    // Verify Content-Type is image/*
    // Verify Cache-Control header
  });

  testFn('should return 404 for non-existent image', async () => {
    // Request invalid path
    // Verify 404 response
  });
});
```

#### 5.2 Audio Streaming

```typescript
describe('GET /api/audio/{path}', () => {
  testFn('should return audio with correct headers', async () => {
    // Get a book with audioUrl
    // Make HEAD request to check headers
    // Verify Content-Type is audio/*
  });

  testFn('should support range requests (206)', async () => {
    // Send Range: bytes=0-1023 header
    // Verify 206 Partial Content
    // Verify Content-Range header
  });

  testFn('should return 401 without auth', async () => {
    // Request without token
    // Verify 401 response
  });

  testFn('should return 404 for non-existent audio', async () => {
    // Request invalid path
    // Verify 404 response
  });
});
```

---

## Test Infrastructure Updates

### Schema Definitions to Add

Add these to `SCHEMA_DEFINITIONS` in the test file:

```typescript
const SCHEMA_DEFINITIONS: Record<string, SchemaDefinition> = {
  // ... existing schemas ...

  // New schemas for library lists
  UserList: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    description: { required: false, type: 'string' },
    bookCount: { required: true, type: 'number' },
    createdAt: { required: true, type: 'string' },
    updatedAt: { required: true, type: 'string' },
  },

  // Download history item
  DownloadHistoryItem: {
    bookId: { required: true, type: 'string' },
    bookTitle: { required: true, type: 'string' },
    downloadedAt: { required: true, type: 'string' },
    deviceId: { required: false, type: 'string' },
  },

  // Search suggestion schemas
  BookSuggestion: {
    id: { required: true, type: 'string' },
    title: { required: true, type: 'string' },
    coverUrl: { required: true, type: 'string' },
  },
  AuthorSuggestion: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
  },
  NarratorSuggestion: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
  },
};
```

### Helper Functions to Add

```typescript
// Helper for testing binary responses (media endpoints)
async function authenticatedBinaryRequest(
  url: string,
  options: AxiosRequestConfig = {}
): Promise<AxiosResponse> {
  const token = await getAuthToken();
  return axios({
    url,
    ...options,
    responseType: 'arraybuffer',
    headers: {
      ...options.headers,
      Authorization: `Bearer ${token}`,
    },
    validateStatus: () => true,
  });
}

// Helper to get fresh tokens for logout test
async function getFreshTokens(): Promise<{ accessToken: string; refreshToken: string }> {
  const response = await axios.post(`${BASE_URL}/api/auth/mobile/login`, TEST_USER, {
    headers: { 'Content-Type': 'application/json' },
    validateStatus: () => true,
  });
  return {
    accessToken: response.data.accessToken,
    refreshToken: response.data.refreshToken,
  };
}
```

---

## Execution Order

1. **Phase 1** - Critical iOS auth (1-2 hours)
2. **Phase 2** - iOS features (2-3 hours)
3. **Phase 3** - Library lists (2-3 hours)
4. **Phase 4** - Remaining endpoints (1 hour)
5. **Phase 5** - Media streaming (1-2 hours)

**Total Estimated Effort**: 7-11 hours

---

## Success Criteria

- [ ] All 42 endpoints have at least one contract test
- [ ] All tests pass with `npm run test:contract`
- [ ] Coverage includes both success and error cases
- [ ] Schema validation catches extra/missing fields
- [ ] CI pipeline enforces contract tests

---

## Testing Strategy Notes

### Endpoints That Require Special Handling

1. **`POST /api/auth/mobile/logout`** - Invalidates refresh token, need fresh tokens for each test
2. **`PUT /api/user/password`** - Cannot test success without breaking test user
3. **`POST /api/downloads/{bookId}`** - Returns 501 in dev (S3 not configured)
4. **Media endpoints** - Return binary data, need special assertions

### Test Data Dependencies

Tests assume:

- Test user exists (`test@example.com`)
- At least one book exists in database
- At least one author, series, narrator, category exists

### Environment Variables

Contract tests require:

```bash
RUN_CONTRACT_TESTS=true  # Enable contract tests
TEST_API_URL=http://localhost:3000  # Optional, defaults to localhost
```

---

## Related Documentation

- [OpenAPI Spec](../api/openapi.yaml)
- [Testing Guide](../testing.md)
- [API Quick Reference](../api-quick-ref.md)
- [Data Validation Layers](../data-validation-layers.md)
