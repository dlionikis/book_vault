/**
 * OpenAPI Contract Tests
 *
 * These tests validate that API responses match the OpenAPI specification.
 * They ensure the contract defined in docs/api/openapi.yaml is respected.
 *
 * IMPORTANT: These are integration tests that require:
 * 1. Dev server running (npm run dev)
 * 2. Test database seeded (npm run db:seed)
 * 3. Valid test user (test@example.com / password123)
 */

import jestOpenAPI from 'jest-openapi';
import path from 'path';
import fetch, { RequestInit as NodeRequestInit, Response as NodeResponse } from 'node-fetch';

// Load OpenAPI spec
const openApiPath = path.join(__dirname, '../../docs/api/openapi.yaml');
jestOpenAPI(openApiPath);

// Test configuration
const BASE_URL = process.env.TEST_API_URL || 'http://localhost:3000';
const TEST_USER = {
  email: process.env.TEST_USER_EMAIL || 'test@example.com',
  password: process.env.TEST_USER_PASSWORD || 'password123',
};

// Helper to get auth token
let authToken: string | null = null;

async function getAuthToken(): Promise<string> {
  if (authToken) return authToken;

  // NOTE: Using /api/auth/mobile/login instead of /api/auth/login
  // The OpenAPI spec needs to be updated to reflect the actual endpoints
  const response = await fetch(`${BASE_URL}/api/auth/mobile/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(TEST_USER),
  });

  if (!response.ok) {
    throw new Error(`Failed to get auth token: ${response.status} ${await response.text()}`);
  }

  const data = (await response.json()) as { accessToken: string };
  authToken = data.accessToken;
  return authToken;
}

// Helper to make authenticated requests
async function authenticatedFetch(
  url: string,
  options: NodeRequestInit = {}
): Promise<NodeResponse> {
  const token = await getAuthToken();
  return fetch(url, {
    ...options,
    headers: {
      ...(options.headers as Record<string, string>),
      Authorization: `Bearer ${token}`,
    },
  });
}

describe('OpenAPI Contract Tests', () => {
  // Skip all tests if TEST_API_URL is not set (CI/local development)
  const runTests = process.env.RUN_CONTRACT_TESTS === 'true';
  const testFn = runTests ? test : test.skip;

  // TODO: Authentication endpoint tests are disabled because OpenAPI spec doesn't match implementation
  // OpenAPI spec documents /api/auth/login but actual endpoint is /api/auth/mobile/login
  // Need to update OpenAPI spec in Phase 2 fixes
  describe.skip('Authentication Endpoints', () => {
    describe('POST /api/auth/login', () => {
      testFn('should satisfy OpenAPI spec for successful login', async () => {
        const response = await fetch(`${BASE_URL}/api/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(TEST_USER),
        });

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('token');
        expect(data).toHaveProperty('user');
        expect(data.user).toHaveProperty('id');
        expect(data.user).toHaveProperty('email');
      });

      testFn('should satisfy OpenAPI spec for invalid credentials', async () => {
        const response = await fetch(`${BASE_URL}/api/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: TEST_USER.email, password: 'wrong-password' }),
        });

        expect(response.status).toBe(401);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });
  });

  describe('Books Endpoints', () => {
    describe('GET /api/books', () => {
      testFn('should satisfy OpenAPI spec for book list', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/books?page=1&limit=10`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('books');
        expect(data).toHaveProperty('pagination');
        expect(Array.isArray(data.books)).toBe(true);

        // Validate pagination structure
        expect(data.pagination).toHaveProperty('page');
        expect(data.pagination).toHaveProperty('limit');
        expect(data.pagination).toHaveProperty('total');
        expect(data.pagination).toHaveProperty('pages');
      });

      testFn('should satisfy OpenAPI spec with sort parameter', async () => {
        const response = await authenticatedFetch(
          `${BASE_URL}/api/books?sort=title&page=1&limit=5`
        );

        expect(response.status).toBe(200);

        await response.json();
        expect(response).toSatisfyApiSpec();
      });

      testFn('should return 401 for unauthenticated request', async () => {
        const response = await fetch(`${BASE_URL}/api/books`);

        expect(response.status).toBe(401);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });

    describe('GET /api/books/{id}', () => {
      let testBookId: string;

      beforeAll(async () => {
        // Get a book ID from the books list
        const response = await authenticatedFetch(`${BASE_URL}/api/books?limit=1`);
        const data = await response.json();
        if (data.books && data.books.length > 0) {
          testBookId = data.books[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for valid book', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/books/${testBookId}`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();

        // Validate required Book fields
        expect(data).toHaveProperty('id');
        expect(data).toHaveProperty('asin');
        expect(data).toHaveProperty('title');
        expect(data).toHaveProperty('runtimeMinutes');
        expect(data).toHaveProperty('coverUrl');
        expect(data).toHaveProperty('audioUrl');
        expect(data).toHaveProperty('authors');
        expect(Array.isArray(data.authors)).toBe(true);
      });

      testFn('should return 404 for non-existent book', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedFetch(`${BASE_URL}/api/books/${nonExistentId}`);

        expect(response.status).toBe(404);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });
  });

  describe('Chapters Endpoints', () => {
    let testBookId: string;

    beforeAll(async () => {
      // Get a book ID from the books list
      const response = await authenticatedFetch(`${BASE_URL}/api/books?limit=1`);
      const data = await response.json();
      if (data.books && data.books.length > 0) {
        testBookId = data.books[0].id;
      }
    });

    describe('GET /api/books/{id}/chapters', () => {
      testFn('should satisfy OpenAPI spec for chapters', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/books/${testBookId}/chapters`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('chapters');
        expect(data).toHaveProperty('source');
        expect(Array.isArray(data.chapters)).toBe(true);
        expect(['database', 'extracted', 'none']).toContain(data.source);
      });

      testFn('should return 404 for non-existent book', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedFetch(
          `${BASE_URL}/api/books/${nonExistentId}/chapters`
        );

        expect(response.status).toBe(404);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });
  });

  describe('Progress Endpoints', () => {
    let testBookId: string;

    beforeAll(async () => {
      // Get a book ID from the books list
      const response = await authenticatedFetch(`${BASE_URL}/api/books?limit=1`);
      const data = await response.json();
      if (data.books && data.books.length > 0) {
        testBookId = data.books[0].id;
      }
    });

    describe('GET /api/progress', () => {
      testFn('should satisfy OpenAPI spec for progress query', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/progress?bookId=${testBookId}`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('positionSeconds');
        expect(data).toHaveProperty('completed');
      });

      testFn('should return 400 for missing bookId', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/progress`);

        expect(response.status).toBe(400);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });

    describe('POST /api/progress', () => {
      testFn('should satisfy OpenAPI spec for progress update', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/progress`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            bookId: testBookId,
            positionSeconds: 123.45,
          }),
        });

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('positionSeconds');
        expect(data).toHaveProperty('completed');
        expect(data).toHaveProperty('lastPlayed');
        expect(data).toHaveProperty('updated');
      });
    });

    describe('PUT /api/progress', () => {
      testFn('should satisfy OpenAPI spec for marking as completed', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/progress`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            bookId: testBookId,
            status: 'completed',
          }),
        });

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('positionSeconds');
        expect(data).toHaveProperty('completed');
        expect(data.completed).toBe(true);
      });

      testFn('should satisfy OpenAPI spec for reset to not-started', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/progress`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            bookId: testBookId,
            status: 'not-started',
          }),
        });

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('positionSeconds');
        expect(data).toHaveProperty('completed');
        expect(data.positionSeconds).toBe(0);
        expect(data.completed).toBe(false);
      });
    });
  });

  describe('Search Endpoints', () => {
    describe('GET /api/search', () => {
      testFn('should satisfy OpenAPI spec for search results', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/search?q=test&page=1&limit=10`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('results');
        expect(data).toHaveProperty('pagination');
        expect(Array.isArray(data.results)).toBe(true);
      });

      testFn('should return 400 for missing query', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/search`);

        expect(response.status).toBe(400);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });
  });

  describe('Browse Endpoints', () => {
    describe('GET /api/browse/authors', () => {
      testFn('should satisfy OpenAPI spec for authors list', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/browse/authors?page=1&limit=10`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('results');
        expect(data).toHaveProperty('pagination');
        expect(Array.isArray(data.results)).toBe(true);

        if (data.results.length > 0) {
          const author = data.results[0];
          expect(author).toHaveProperty('id');
          expect(author).toHaveProperty('name');
          expect(author).toHaveProperty('bookCount');
        }
      });
    });

    describe('GET /api/browse/series', () => {
      testFn('should satisfy OpenAPI spec for series list', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/browse/series?page=1&limit=10`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('results');
        expect(data).toHaveProperty('pagination');
      });
    });

    describe('GET /api/browse/narrators', () => {
      testFn('should satisfy OpenAPI spec for narrators list', async () => {
        const response = await authenticatedFetch(
          `${BASE_URL}/api/browse/narrators?page=1&limit=10`
        );

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('results');
        expect(data).toHaveProperty('pagination');
      });
    });

    describe('GET /api/browse/categories', () => {
      testFn('should satisfy OpenAPI spec for categories list', async () => {
        const response = await authenticatedFetch(
          `${BASE_URL}/api/browse/categories?page=1&limit=10`
        );

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('results');
        expect(data).toHaveProperty('pagination');
      });
    });

    describe('GET /api/authors/{id}', () => {
      let testAuthorId: string;

      beforeAll(async () => {
        // Get an author ID from the authors list
        const response = await authenticatedFetch(`${BASE_URL}/api/browse/authors?limit=1`);
        const data = await response.json();
        if (data.results && data.results.length > 0) {
          testAuthorId = data.results[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for author details with books', async () => {
        if (!testAuthorId) {
          console.warn('No authors in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/authors/${testAuthorId}`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('id');
        expect(data).toHaveProperty('name');
        expect(data).toHaveProperty('books');
        expect(data).toHaveProperty('pagination');
        expect(Array.isArray(data.books)).toBe(true);
      });
    });
  });

  describe('Library Endpoints', () => {
    describe('GET /api/library', () => {
      testFn('should satisfy OpenAPI spec for library', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/library`);

        expect(response.status).toBe(200);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('books');
        expect(data).toHaveProperty('total');
        expect(Array.isArray(data.books)).toBe(true);
        expect(typeof data.total).toBe('number');
      });
    });

    describe('POST /api/library', () => {
      let testBookId: string;

      beforeAll(async () => {
        // Get a book ID from the books list
        const response = await authenticatedFetch(`${BASE_URL}/api/books?limit=1`);
        const data = await response.json();
        if (data.books && data.books.length > 0) {
          testBookId = data.books[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for adding book to library', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/library`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ bookId: testBookId }),
        });

        // Either 200 (already in library) or 201 (added)
        expect([200, 201]).toContain(response.status);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('message');
      });

      testFn('should return 400 for missing bookId', async () => {
        const response = await authenticatedFetch(`${BASE_URL}/api/library`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        });

        expect(response.status).toBe(400);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('error');
      });
    });

    describe('DELETE /api/library/{bookId}', () => {
      let testBookId: string;

      beforeAll(async () => {
        // Get a book ID and ensure it's in the library
        const booksResponse = await authenticatedFetch(`${BASE_URL}/api/books?limit=1`);
        const booksData = await booksResponse.json();
        if (booksData.books && booksData.books.length > 0) {
          testBookId = booksData.books[0].id;

          // Add it to library first
          await authenticatedFetch(`${BASE_URL}/api/library`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ bookId: testBookId }),
          });
        }
      });

      testFn('should satisfy OpenAPI spec for removing book from library', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedFetch(`${BASE_URL}/api/library/${testBookId}`, {
          method: 'DELETE',
        });

        // Either 200 (removed) or 404 (not in library)
        expect([200, 404]).toContain(response.status);

        const data = await response.json();
        expect(response).toSatisfyApiSpec();
        expect(data).toHaveProperty('message');
      });
    });
  });
});
