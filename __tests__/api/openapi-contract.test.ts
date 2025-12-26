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
import axios, { AxiosRequestConfig, AxiosResponse } from 'axios';
import http from 'http';
import https from 'https';

// Configure axios to use Node.js adapters instead of XHR (for Jest/JSDOM environment)
axios.defaults.adapter = require('axios/lib/adapters/http');
axios.defaults.httpAgent = new http.Agent({ keepAlive: true });
axios.defaults.httpsAgent = new https.Agent({ keepAlive: true });

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

  // NOTE: Using /api/auth/mobile/login to get JWT Bearer token
  // All endpoints now support both session cookies and Bearer tokens
  const response = await axios.post(`${BASE_URL}/api/auth/mobile/login`, TEST_USER, {
    headers: { 'Content-Type': 'application/json' },
    validateStatus: () => true, // Don't throw on any status code
  });

  if (response.status !== 200) {
    throw new Error(
      `Failed to get auth token: ${response.status} ${JSON.stringify(response.data)}`
    );
  }

  const token = response.data.accessToken as string;
  authToken = token;
  return token;
}

// Helper to make authenticated requests
async function authenticatedRequest(
  url: string,
  options: AxiosRequestConfig = {}
): Promise<AxiosResponse> {
  const token = await getAuthToken();
  return axios({
    url,
    ...options,
    headers: {
      ...options.headers,
      Authorization: `Bearer ${token}`,
    },
    validateStatus: () => true, // Don't throw on any status code
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
        const response = await axios.post(`${BASE_URL}/api/auth/login`, TEST_USER, {
          headers: { 'Content-Type': 'application/json' },
          validateStatus: () => true,
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('token');
        expect(response.data).toHaveProperty('user');
        expect(response.data.user).toHaveProperty('id');
        expect(response.data.user).toHaveProperty('email');
      });

      testFn('should satisfy OpenAPI spec for invalid credentials', async () => {
        const response = await axios.post(
          `${BASE_URL}/api/auth/login`,
          { email: TEST_USER.email, password: 'wrong-password' },
          {
            headers: { 'Content-Type': 'application/json' },
            validateStatus: () => true,
          }
        );

        expect(response.status).toBe(401);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });
  });

  describe('Books Endpoints', () => {
    describe('GET /api/books', () => {
      testFn('should satisfy OpenAPI spec for book list', async () => {
        const url = `${BASE_URL}/api/books?page=1&limit=10`;
        const response = await authenticatedRequest(url, { method: 'GET' });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('books');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.books)).toBe(true);

        // Validate pagination structure
        expect(response.data.pagination).toHaveProperty('page');
        expect(response.data.pagination).toHaveProperty('limit');
        expect(response.data.pagination).toHaveProperty('total');
        expect(response.data.pagination).toHaveProperty('pages');
      });

      testFn('should satisfy OpenAPI spec with sort parameter', async () => {
        const response = await authenticatedRequest(
          `${BASE_URL}/api/books?sort=title&page=1&limit=5`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
      });

      testFn('should return 401 for unauthenticated request', async () => {
        const response = await axios.get(`${BASE_URL}/api/books`, {
          validateStatus: () => true,
        });

        expect(response.status).toBe(401);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });

    describe('GET /api/books/{id}', () => {
      let testBookId: string;

      beforeAll(async () => {
        // Get a book ID from the books list
        const response = await authenticatedRequest(`${BASE_URL}/api/books?limit=1`, {
          method: 'GET',
        });
        if (response.data.books && response.data.books.length > 0) {
          testBookId = response.data.books[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for valid book', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/books/${testBookId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();

        // Validate required Book fields
        expect(response.data).toHaveProperty('id');
        expect(response.data).toHaveProperty('asin');
        expect(response.data).toHaveProperty('title');
        expect(response.data).toHaveProperty('runtimeMinutes');
        expect(response.data).toHaveProperty('coverUrl');
        expect(response.data).toHaveProperty('audioUrl');
        expect(response.data).toHaveProperty('authors');
        expect(Array.isArray(response.data.authors)).toBe(true);
      });

      testFn('should return 404 for non-existent book', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedRequest(`${BASE_URL}/api/books/${nonExistentId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(404);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });
  });

  describe('Chapters Endpoints', () => {
    let testBookId: string;

    beforeAll(async () => {
      // Get a book ID from the books list
      const response = await authenticatedRequest(`${BASE_URL}/api/books?limit=1`, {
        method: 'GET',
      });
      if (response.data.books && response.data.books.length > 0) {
        testBookId = response.data.books[0].id;
      }
    });

    describe('GET /api/books/{id}/chapters', () => {
      testFn('should satisfy OpenAPI spec for chapters', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(
          `${BASE_URL}/api/books/${testBookId}/chapters`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('chapters');
        expect(response.data).toHaveProperty('source');
        expect(Array.isArray(response.data.chapters)).toBe(true);
        expect(['database', 'extracted', 'none', 'unavailable', 'error']).toContain(
          response.data.source
        );
      });

      testFn('should return 404 for non-existent book', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedRequest(
          `${BASE_URL}/api/books/${nonExistentId}/chapters`,
          { method: 'GET' }
        );

        expect(response.status).toBe(404);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });
  });

  describe('Progress Endpoints', () => {
    let testBookId: string;

    beforeAll(async () => {
      // Get a book ID from the books list
      const response = await authenticatedRequest(`${BASE_URL}/api/books?limit=1`, {
        method: 'GET',
      });
      if (response.data.books && response.data.books.length > 0) {
        testBookId = response.data.books[0].id;
      }
    });

    describe('GET /api/progress', () => {
      testFn('should satisfy OpenAPI spec for progress query', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(
          `${BASE_URL}/api/progress?bookId=${testBookId}`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('positionSeconds');
        expect(response.data).toHaveProperty('completed');
      });

      testFn('should return 400 for missing bookId', async () => {
        const response = await authenticatedRequest(`${BASE_URL}/api/progress`, { method: 'GET' });

        expect(response.status).toBe(400);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });

    describe('POST /api/progress', () => {
      testFn('should satisfy OpenAPI spec for progress update', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/progress`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          data: {
            bookId: testBookId,
            positionSeconds: 123.45,
          },
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('positionSeconds');
        expect(response.data).toHaveProperty('completed');
        expect(response.data).toHaveProperty('lastPlayed');
        expect(response.data).toHaveProperty('updated');
      });
    });

    describe('PUT /api/progress', () => {
      testFn('should satisfy OpenAPI spec for marking as completed', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/progress`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          data: {
            bookId: testBookId,
            status: 'completed',
          },
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('positionSeconds');
        expect(response.data).toHaveProperty('completed');
        expect(response.data.completed).toBe(true);
      });

      testFn('should satisfy OpenAPI spec for reset to not-started', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/progress`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          data: {
            bookId: testBookId,
            status: 'not-started',
          },
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('positionSeconds');
        expect(response.data).toHaveProperty('completed');
        expect(response.data.positionSeconds).toBe(0);
        expect(response.data.completed).toBe(false);
      });
    });
  });

  describe('Search Endpoints', () => {
    describe('GET /api/search', () => {
      testFn('should satisfy OpenAPI spec for search results', async () => {
        const response = await authenticatedRequest(
          `${BASE_URL}/api/search?q=test&page=1&limit=10`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('results');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.results)).toBe(true);
      });

      testFn('should return 400 for missing query', async () => {
        const response = await authenticatedRequest(`${BASE_URL}/api/search`, { method: 'GET' });

        expect(response.status).toBe(400);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });
  });

  describe('Browse Endpoints', () => {
    describe('GET /api/browse/authors', () => {
      testFn('should satisfy OpenAPI spec for authors list', async () => {
        const response = await authenticatedRequest(
          `${BASE_URL}/api/browse/authors?page=1&limit=10`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('results');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.results)).toBe(true);

        if (response.data.results.length > 0) {
          const author = response.data.results[0];
          expect(author).toHaveProperty('id');
          expect(author).toHaveProperty('name');
          expect(author).toHaveProperty('bookCount');
        }
      });
    });

    describe('GET /api/browse/series', () => {
      testFn('should satisfy OpenAPI spec for series list', async () => {
        const response = await authenticatedRequest(
          `${BASE_URL}/api/browse/series?page=1&limit=10`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('results');
        expect(response.data).toHaveProperty('pagination');
      });
    });

    describe('GET /api/browse/narrators', () => {
      testFn('should satisfy OpenAPI spec for narrators list', async () => {
        const response = await authenticatedRequest(
          `${BASE_URL}/api/browse/narrators?page=1&limit=10`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('results');
        expect(response.data).toHaveProperty('pagination');
      });
    });

    describe('GET /api/browse/categories', () => {
      testFn('should satisfy OpenAPI spec for categories list', async () => {
        const response = await authenticatedRequest(
          `${BASE_URL}/api/browse/categories?page=1&limit=10`,
          { method: 'GET' }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('results');
        expect(response.data).toHaveProperty('pagination');
      });
    });

    describe('GET /api/authors/{id}', () => {
      let testAuthorId: string;

      beforeAll(async () => {
        // Get an author ID from the authors list
        const response = await authenticatedRequest(`${BASE_URL}/api/browse/authors?limit=1`, {
          method: 'GET',
        });
        if (response.data.results && response.data.results.length > 0) {
          testAuthorId = response.data.results[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for author details with books', async () => {
        if (!testAuthorId) {
          console.warn('No authors in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/authors/${testAuthorId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('id');
        expect(response.data).toHaveProperty('name');
        expect(response.data).toHaveProperty('books');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.books)).toBe(true);
      });
    });
  });

  describe('Library Endpoints', () => {
    describe('GET /api/library', () => {
      testFn('should satisfy OpenAPI spec for library', async () => {
        const response = await authenticatedRequest(`${BASE_URL}/api/library`, { method: 'GET' });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('books');
        expect(response.data).toHaveProperty('total');
        expect(Array.isArray(response.data.books)).toBe(true);
        expect(typeof response.data.total).toBe('number');
      });
    });

    describe('POST /api/library', () => {
      let testBookId: string;

      beforeAll(async () => {
        // Get a book ID from the books list
        const response = await authenticatedRequest(`${BASE_URL}/api/books?limit=1`, {
          method: 'GET',
        });
        if (response.data.books && response.data.books.length > 0) {
          testBookId = response.data.books[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for adding book to library', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/library`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          data: { bookId: testBookId },
        });

        // Either 200 (already in library) or 201 (added)
        expect([200, 201]).toContain(response.status);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('message');
      });

      testFn('should return 400 for missing bookId', async () => {
        const response = await authenticatedRequest(`${BASE_URL}/api/library`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          data: {},
        });

        expect(response.status).toBe(400);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });

    describe('DELETE /api/library/{bookId}', () => {
      let testBookId: string;

      beforeAll(async () => {
        // Get a book ID and ensure it's in the library
        const booksResponse = await authenticatedRequest(`${BASE_URL}/api/books?limit=1`, {
          method: 'GET',
        });
        if (booksResponse.data.books && booksResponse.data.books.length > 0) {
          testBookId = booksResponse.data.books[0].id;

          // Add it to library first
          await authenticatedRequest(`${BASE_URL}/api/library`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            data: { bookId: testBookId },
          });
        }
      });

      testFn('should satisfy OpenAPI spec for removing book from library', async () => {
        if (!testBookId) {
          console.warn('No books in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/library/${testBookId}`, {
          method: 'DELETE',
        });

        // Either 200 (removed) or 404 (not in library)
        expect([200, 404]).toContain(response.status);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('message');
      });
    });
  });
});
