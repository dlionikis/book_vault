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

// Field validation helpers for strict OpenAPI compliance
type SchemaDefinition = Record<string, { required?: boolean; type?: string }>;

const SCHEMA_DEFINITIONS: Record<string, SchemaDefinition> = {
  Book: {
    id: { required: true, type: 'string' },
    asin: { required: true, type: 'string' },
    title: { required: true, type: 'string' },
    description: { required: false, type: 'string' },
    runtimeMinutes: { required: true, type: 'number' },
    releaseDate: { required: false, type: 'string' },
    publisher: { required: false, type: 'string' },
    coverUrl: { required: true, type: 'string' },
    audioUrl: { required: true, type: 'string' },
    authors: { required: true, type: 'array' },
    narrators: { required: false, type: 'array' },
    series: { required: false, type: 'array' },
    categories: { required: false, type: 'array' },
  },
  Author: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
  },
  Narrator: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
  },
  SeriesInfo: {
    id: { required: true, type: 'string' },
    title: { required: true, type: 'string' },
    sequence: { required: false, type: 'string' },
    asin: { required: false, type: 'string' },
  },
  Category: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
  },
  AuthorWithBookCount: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
    bookCount: { required: true, type: 'number' },
  },
  SeriesWithBookCount: {
    id: { required: true, type: 'string' },
    title: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
    bookCount: { required: true, type: 'number' },
  },
  NarratorWithBookCount: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
    bookCount: { required: true, type: 'number' },
  },
  CategoryWithBookCount: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    level: { required: false, type: 'number' },
    bookCount: { required: true, type: 'number' },
  },
  AuthorDetail: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
    books: { required: true, type: 'array' },
    pagination: { required: true, type: 'object' },
  },
  SeriesDetail: {
    id: { required: true, type: 'string' },
    title: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
    books: { required: true, type: 'array' },
    pagination: { required: true, type: 'object' },
  },
  NarratorDetail: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    asin: { required: false, type: 'string' },
    books: { required: true, type: 'array' },
    pagination: { required: true, type: 'object' },
  },
  CategoryDetail: {
    id: { required: true, type: 'string' },
    name: { required: true, type: 'string' },
    books: { required: true, type: 'array' },
    pagination: { required: true, type: 'object' },
  },
};

/**
 * Validates that an object contains ONLY the fields defined in the OpenAPI schema.
 * Catches extra fields like createdAt, updatedAt that shouldn't be exposed.
 *
 * @param obj - The object to validate
 * @param schemaName - Name of the schema from SCHEMA_DEFINITIONS
 * @param path - Path for nested validation (used in error messages)
 * @returns Array of validation errors (empty if valid)
 */
function validateFields(obj: any, schemaName: string, path = ''): string[] {
  const schema = SCHEMA_DEFINITIONS[schemaName];
  if (!schema) {
    return [`Unknown schema: ${schemaName}`];
  }

  const errors: string[] = [];
  const allowedFields = Object.keys(schema);
  const actualFields = Object.keys(obj);

  // Check for extra fields (the main purpose of this validator)
  const extraFields = actualFields.filter((field) => !allowedFields.includes(field));
  if (extraFields.length > 0) {
    errors.push(
      `${path ? path + '.' : ''}${schemaName} has extra fields: ${extraFields.join(', ')}`
    );
  }

  // Recursively validate nested objects
  for (const [field, value] of Object.entries(obj)) {
    const fieldSchema = schema[field];
    if (!fieldSchema) continue; // Already caught as extra field

    const fieldPath = path ? `${path}.${field}` : field;

    if (Array.isArray(value)) {
      // Validate array items based on field name
      const itemSchemaName = getArrayItemSchema(field);
      if (itemSchemaName) {
        value.forEach((item, index) => {
          if (typeof item === 'object' && item !== null) {
            const nestedErrors = validateFields(item, itemSchemaName, `${fieldPath}[${index}]`);
            errors.push(...nestedErrors);
          }
        });
      }
    } else if (typeof value === 'object' && value !== null && field === 'pagination') {
      // Pagination has its own schema
      const paginationErrors = validatePagination(value, fieldPath);
      errors.push(...paginationErrors);
    }
  }

  return errors;
}

/**
 * Get the schema name for array items based on field name.
 */
function getArrayItemSchema(fieldName: string): string | null {
  const mapping: Record<string, string> = {
    authors: 'Author',
    narrators: 'Narrator',
    series: 'SeriesInfo',
    categories: 'Category',
    books: 'Book',
    results: 'unknown', // Depends on endpoint context
  };
  return mapping[fieldName] || null;
}

/**
 * Validates pagination object structure.
 */
function validatePagination(obj: any, path: string): string[] {
  const allowedFields = ['page', 'limit', 'total', 'pages'];
  const actualFields = Object.keys(obj);
  const extraFields = actualFields.filter((field) => !allowedFields.includes(field));

  if (extraFields.length > 0) {
    return [`${path} has extra fields: ${extraFields.join(', ')}`];
  }
  return [];
}

describe('OpenAPI Contract Tests', () => {
  // Skip all tests if TEST_API_URL is not set (CI/local development)
  const runTests = process.env.RUN_CONTRACT_TESTS === 'true';
  const testFn = runTests ? test : test.skip;

  describe('Authentication Endpoints', () => {
    describe('POST /api/auth/mobile/login', () => {
      testFn('should satisfy OpenAPI spec for successful login', async () => {
        const response = await axios.post(`${BASE_URL}/api/auth/mobile/login`, TEST_USER, {
          headers: { 'Content-Type': 'application/json' },
          validateStatus: () => true,
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('accessToken');
        expect(response.data).toHaveProperty('refreshToken');
        expect(response.data).toHaveProperty('user');
        expect(response.data).toHaveProperty('expiresIn');
        expect(response.data.user).toHaveProperty('id');
        expect(response.data.user).toHaveProperty('email');
      });

      testFn('should satisfy OpenAPI spec for invalid credentials', async () => {
        const response = await axios.post(
          `${BASE_URL}/api/auth/mobile/login`,
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

    describe('POST /api/auth/register', () => {
      testFn('should satisfy OpenAPI spec for missing required fields', async () => {
        const response = await axios.post(
          `${BASE_URL}/api/auth/register`,
          { email: 'newuser@test.com' },
          {
            headers: { 'Content-Type': 'application/json' },
            validateStatus: () => true,
          }
        );

        expect(response.status).toBe(400);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });

      testFn('should satisfy OpenAPI spec for invalid email format', async () => {
        const response = await axios.post(
          `${BASE_URL}/api/auth/register`,
          { email: 'not-an-email', password: 'validpassword123' },
          {
            headers: { 'Content-Type': 'application/json' },
            validateStatus: () => true,
          }
        );

        expect(response.status).toBe(400);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });

      testFn('should satisfy OpenAPI spec for weak password (< 8 chars)', async () => {
        const response = await axios.post(
          `${BASE_URL}/api/auth/register`,
          { email: 'newuser@test.com', password: 'short' },
          {
            headers: { 'Content-Type': 'application/json' },
            validateStatus: () => true,
          }
        );

        expect(response.status).toBe(400);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });

      testFn('should satisfy OpenAPI spec for duplicate email', async () => {
        const response = await axios.post(
          `${BASE_URL}/api/auth/register`,
          { email: TEST_USER.email, password: 'validpassword123' },
          {
            headers: { 'Content-Type': 'application/json' },
            validateStatus: () => true,
          }
        );

        expect(response.status).toBe(409);
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

        // PHASE 2: Strict field validation - catch extra fields
        const fieldErrors = validateFields(response.data, 'Book');
        expect(fieldErrors).toEqual([]);
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

          // PHASE 2: Strict field validation - catch extra fields
          const fieldErrors = validateFields(author, 'AuthorWithBookCount');
          expect(fieldErrors).toEqual([]);
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

        if (response.data.results.length > 0) {
          // PHASE 2: Strict field validation - catch extra fields
          const fieldErrors = validateFields(response.data.results[0], 'SeriesWithBookCount');
          expect(fieldErrors).toEqual([]);
        }
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

        if (response.data.results.length > 0) {
          // PHASE 2: Strict field validation - catch extra fields
          const fieldErrors = validateFields(response.data.results[0], 'NarratorWithBookCount');
          expect(fieldErrors).toEqual([]);
        }
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

        if (response.data.results.length > 0) {
          // PHASE 2: Strict field validation - catch extra fields
          const fieldErrors = validateFields(response.data.results[0], 'CategoryWithBookCount');
          expect(fieldErrors).toEqual([]);
        }
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

        // PHASE 2: Strict field validation - catch extra fields
        const fieldErrors = validateFields(response.data, 'AuthorDetail');
        expect(fieldErrors).toEqual([]);
      });

      testFn('should return 404 for non-existent author', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedRequest(`${BASE_URL}/api/authors/${nonExistentId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(404);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });

    describe('GET /api/series/{id}', () => {
      let testSeriesId: string;

      beforeAll(async () => {
        // Get a series ID from the series list
        const response = await authenticatedRequest(`${BASE_URL}/api/browse/series?limit=1`, {
          method: 'GET',
        });
        if (response.data.results && response.data.results.length > 0) {
          testSeriesId = response.data.results[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for series details with books', async () => {
        if (!testSeriesId) {
          console.warn('No series in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/series/${testSeriesId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('id');
        expect(response.data).toHaveProperty('title');
        expect(response.data).toHaveProperty('books');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.books)).toBe(true);

        // PHASE 2: Strict field validation - catch extra fields
        const fieldErrors = validateFields(response.data, 'SeriesDetail');
        expect(fieldErrors).toEqual([]);
      });

      testFn('should return 404 for non-existent series', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedRequest(`${BASE_URL}/api/series/${nonExistentId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(404);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });

    describe('GET /api/narrators/{id}', () => {
      let testNarratorId: string;

      beforeAll(async () => {
        // Get a narrator ID from the narrators list
        const response = await authenticatedRequest(`${BASE_URL}/api/browse/narrators?limit=1`, {
          method: 'GET',
        });
        if (response.data.results && response.data.results.length > 0) {
          testNarratorId = response.data.results[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for narrator details with books', async () => {
        if (!testNarratorId) {
          console.warn('No narrators in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(`${BASE_URL}/api/narrators/${testNarratorId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('id');
        expect(response.data).toHaveProperty('name');
        expect(response.data).toHaveProperty('books');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.books)).toBe(true);

        // PHASE 2: Strict field validation - catch extra fields
        const fieldErrors = validateFields(response.data, 'NarratorDetail');
        expect(fieldErrors).toEqual([]);
      });

      testFn('should return 404 for non-existent narrator', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedRequest(`${BASE_URL}/api/narrators/${nonExistentId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(404);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
      });
    });

    describe('GET /api/categories/{id}', () => {
      let testCategoryId: string;

      beforeAll(async () => {
        // Get a category ID from the categories list
        const response = await authenticatedRequest(`${BASE_URL}/api/browse/categories?limit=1`, {
          method: 'GET',
        });
        if (response.data.results && response.data.results.length > 0) {
          testCategoryId = response.data.results[0].id;
        }
      });

      testFn('should satisfy OpenAPI spec for category details with books', async () => {
        if (!testCategoryId) {
          console.warn('No categories in database, skipping test');
          return;
        }

        const response = await authenticatedRequest(
          `${BASE_URL}/api/categories/${testCategoryId}`,
          {
            method: 'GET',
          }
        );

        expect(response.status).toBe(200);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('id');
        expect(response.data).toHaveProperty('name');
        expect(response.data).toHaveProperty('books');
        expect(response.data).toHaveProperty('pagination');
        expect(Array.isArray(response.data.books)).toBe(true);

        // PHASE 2: Strict field validation - catch extra fields
        const fieldErrors = validateFields(response.data, 'CategoryDetail');
        expect(fieldErrors).toEqual([]);
      });

      testFn('should return 404 for non-existent category', async () => {
        const nonExistentId = '00000000-0000-0000-0000-000000000000';
        const response = await authenticatedRequest(`${BASE_URL}/api/categories/${nonExistentId}`, {
          method: 'GET',
        });

        expect(response.status).toBe(404);
        expect(response).toSatisfyApiSpec();
        expect(response.data).toHaveProperty('error');
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
