/**
 * Runtime validation tests for API responses using Zod schemas
 *
 * These tests ensure that actual API responses match the generated TypeScript types
 * from the OpenAPI specification. This catches any drift between:
 * 1. The OpenAPI spec (docs/api/openapi.yaml)
 * 2. The generated types (lib/api-types.ts)
 * 3. The actual API implementation (app/api/*)
 *
 * IMPORTANT: These are integration tests that require:
 * 1. Dev server running (npm run dev)
 * 2. Test database seeded (npm run db:seed)
 * 3. Valid test user (testuser / password123)
 */

import axios from 'axios';
import http from 'http';
import https from 'https';
import {
  BookSchema,
  BooksListResponseSchema,
  BookDetailResponseSchema,
  ChaptersResponseSchema,
  ProgressResponseSchema,
  AuthorsListResponseSchema,
  AuthorDetailResponseSchema,
  SeriesListResponseSchema,
  SeriesDetailResponseSchema,
  NarratorsListResponseSchema,
  NarratorDetailResponseSchema,
  CategoriesListResponseSchema,
  CategoryDetailResponseSchema,
  SearchResponseSchema,
  LoginResponseSchema,
  LibraryResponseSchema,
  LibraryCheckResponseSchema,
} from '../helpers/api-schemas';

// Configure axios to use Node.js adapters
axios.defaults.adapter = require('axios/lib/adapters/http');
axios.defaults.httpAgent = new http.Agent({ keepAlive: true });
axios.defaults.httpsAgent = new https.Agent({ keepAlive: true });
axios.defaults.validateStatus = () => true; // Don't throw on any status code

const API_BASE = process.env.TEST_API_URL || 'http://localhost:3000';
const TEST_USER = {
  username: process.env.TEST_USER_USERNAME || 'testuser',
  password: process.env.TEST_USER_PASSWORD || 'password123',
};

// Cache auth token to avoid repeated logins
let cachedAuthToken: string | null = null;

// Helper to get auth token for authenticated requests
async function getAuthToken(): Promise<string> {
  if (cachedAuthToken) return cachedAuthToken;

  const response = await axios.post(`${API_BASE}/api/auth/mobile/login`, TEST_USER, {
    headers: { 'Content-Type': 'application/json' },
  });

  if (response.status !== 200) {
    throw new Error(`Login failed: ${response.status}`);
  }

  const parsed = LoginResponseSchema.parse(response.data);
  cachedAuthToken = parsed.accessToken;
  return parsed.accessToken;
}

// Helper to get a sample book ID
async function getSampleBookId(authToken: string): Promise<string> {
  const response = await axios.get(`${API_BASE}/api/books?limit=1`, {
    headers: { Authorization: `Bearer ${authToken}` },
  });

  if (response.status !== 200) {
    throw new Error(`Failed to fetch books: ${response.status}`);
  }

  const parsed = BooksListResponseSchema.parse(response.data);

  if (parsed.books.length === 0) {
    throw new Error('No books available for testing');
  }

  return parsed.books[0].id;
}

// Skip these tests unless explicitly running contract tests with server
const runTests = process.env.RUN_CONTRACT_TESTS === 'true';
const describeFn = runTests ? describe : describe.skip;

describeFn('API Response Type Validation', () => {
  let authToken: string;
  let sampleBookId: string;

  // Generous timeout: this hits a dev server that may be compiling these
  // routes for the first time, which can exceed Jest's default 5s hook limit
  beforeAll(async () => {
    authToken = await getAuthToken();
    sampleBookId = await getSampleBookId(authToken);
  }, 30_000);

  describe('Books API', () => {
    it('validates /api/books response', async () => {
      const response = await axios.get(`${API_BASE}/api/books?page=1&limit=10`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = BooksListResponseSchema.parse(response.data);

      expect(parsed.books).toBeInstanceOf(Array);
      expect(parsed.pagination.page).toBe(1);
      expect(parsed.pagination.limit).toBe(10);
    });

    it('validates /api/books/{id} response', async () => {
      const response = await axios.get(`${API_BASE}/api/books/${sampleBookId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = BookDetailResponseSchema.parse(response.data);

      expect(parsed.id).toBe(sampleBookId);
      expect(parsed.title).toBeDefined();
      expect(parsed.authors).toBeInstanceOf(Array);
    });

    it('validates /api/books/{id}/chapters response', async () => {
      const response = await axios.get(`${API_BASE}/api/books/${sampleBookId}/chapters`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = ChaptersResponseSchema.parse(response.data);

      expect(parsed.chapters).toBeInstanceOf(Array);
    });
  });

  describe('Progress API', () => {
    it('validates GET /api/progress response', async () => {
      const response = await axios.get(`${API_BASE}/api/progress?bookId=${sampleBookId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = ProgressResponseSchema.parse(response.data);

      expect(parsed.positionSeconds).toBeGreaterThanOrEqual(0);
      expect(typeof parsed.completed).toBe('boolean');
    });

    it('validates POST /api/progress response', async () => {
      const response = await axios.post(
        `${API_BASE}/api/progress`,
        {
          bookId: sampleBookId,
          positionSeconds: 100.5,
          completed: false,
        },
        {
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${authToken}`,
          },
        }
      );
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = ProgressResponseSchema.parse(response.data);

      expect(parsed.positionSeconds).toBe(100.5);
      expect(parsed.completed).toBe(false);
    });
  });

  describe('Browse API', () => {
    it('validates /api/browse/authors response', async () => {
      const response = await axios.get(`${API_BASE}/api/browse/authors`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = AuthorsListResponseSchema.parse(response.data);

      expect(parsed.results).toBeInstanceOf(Array);
      if (parsed.results.length > 0) {
        expect(parsed.results[0].bookCount).toBeGreaterThan(0);
      }
    });

    it('validates /api/browse/series response', async () => {
      const response = await axios.get(`${API_BASE}/api/browse/series`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = SeriesListResponseSchema.parse(response.data);

      expect(parsed.results).toBeInstanceOf(Array);
    });

    it('validates /api/browse/narrators response', async () => {
      const response = await axios.get(`${API_BASE}/api/browse/narrators`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = NarratorsListResponseSchema.parse(response.data);

      expect(parsed.results).toBeInstanceOf(Array);
    });

    it('validates /api/browse/categories response', async () => {
      const response = await axios.get(`${API_BASE}/api/browse/categories`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = CategoriesListResponseSchema.parse(response.data);

      expect(parsed.results).toBeInstanceOf(Array);
    });
  });

  describe('Detail APIs', () => {
    let authorId: string;
    let seriesId: string;
    let narratorId: string;
    let categoryId: string;

    beforeAll(async () => {
      // Get sample IDs from browse endpoints
      const [authorsRes, seriesRes, narratorsRes, categoriesRes] = await Promise.all([
        axios.get(`${API_BASE}/api/browse/authors`, {
          headers: { Authorization: `Bearer ${authToken}` },
        }),
        axios.get(`${API_BASE}/api/browse/series`, {
          headers: { Authorization: `Bearer ${authToken}` },
        }),
        axios.get(`${API_BASE}/api/browse/narrators`, {
          headers: { Authorization: `Bearer ${authToken}` },
        }),
        axios.get(`${API_BASE}/api/browse/categories`, {
          headers: { Authorization: `Bearer ${authToken}` },
        }),
      ]);

      const authors = AuthorsListResponseSchema.parse(authorsRes.data);
      const series = SeriesListResponseSchema.parse(seriesRes.data);
      const narrators = NarratorsListResponseSchema.parse(narratorsRes.data);
      const categories = CategoriesListResponseSchema.parse(categoriesRes.data);

      authorId = authors.results[0]?.id;
      seriesId = series.results[0]?.id;
      narratorId = narrators.results[0]?.id;
      categoryId = categories.results[0]?.id;
    });

    it('validates /api/authors/{id} response', async () => {
      if (!authorId) {
        console.warn('Skipping author detail test - no authors available');
        return;
      }

      const response = await axios.get(`${API_BASE}/api/authors/${authorId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = AuthorDetailResponseSchema.parse(response.data);

      expect(parsed.id).toBe(authorId);
      expect(parsed.books).toBeInstanceOf(Array);
    });

    it('validates /api/series/{id} response', async () => {
      if (!seriesId) {
        console.warn('Skipping series detail test - no series available');
        return;
      }

      const response = await axios.get(`${API_BASE}/api/series/${seriesId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = SeriesDetailResponseSchema.parse(response.data);

      expect(parsed.id).toBe(seriesId);
      expect(parsed.books).toBeInstanceOf(Array);
    });

    it('validates /api/narrators/{id} response', async () => {
      if (!narratorId) {
        console.warn('Skipping narrator detail test - no narrators available');
        return;
      }

      const response = await axios.get(`${API_BASE}/api/narrators/${narratorId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = NarratorDetailResponseSchema.parse(response.data);

      expect(parsed.id).toBe(narratorId);
      expect(parsed.books).toBeInstanceOf(Array);
    });

    it('validates /api/categories/{id} response', async () => {
      if (!categoryId) {
        console.warn('Skipping category detail test - no categories available');
        return;
      }

      const response = await axios.get(`${API_BASE}/api/categories/${categoryId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = CategoryDetailResponseSchema.parse(response.data);

      expect(parsed.id).toBe(categoryId);
      expect(parsed.books).toBeInstanceOf(Array);
    });
  });

  describe('Search API', () => {
    it('validates /api/search response', async () => {
      const response = await axios.get(`${API_BASE}/api/search?q=${encodeURIComponent('the')}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = SearchResponseSchema.parse(response.data);

      expect(parsed.results).toBeInstanceOf(Array);
      expect(parsed.pagination).toBeDefined();
    });
  });

  describe('Library API', () => {
    it('validates GET /api/library response', async () => {
      const response = await axios.get(`${API_BASE}/api/library`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = LibraryResponseSchema.parse(response.data);

      expect(parsed.books).toBeInstanceOf(Array);
    });

    it('validates POST /api/library response', async () => {
      // Ensure a known starting state: the book may linger in the library from
      // a previous run or the sibling contract suite (both share the dev DB),
      // in which case the add correctly returns 200 instead of 201.
      await axios
        .delete(`${API_BASE}/api/library/${sampleBookId}`, {
          headers: { Authorization: `Bearer ${authToken}` },
        })
        .catch(() => {});

      const response = await axios.post(
        `${API_BASE}/api/library`,
        { bookId: sampleBookId },
        {
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${authToken}`,
          },
        }
      );
      expect(response.status).toBe(201);

      // Response should be a message object
      expect(response.data.message).toBeDefined();
      expect(typeof response.data.message).toBe('string');
    });

    it('validates /api/library/check response', async () => {
      const response = await axios.get(`${API_BASE}/api/library/check?bookId=${sampleBookId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = LibraryCheckResponseSchema.parse(response.data);

      expect(typeof parsed.inLibrary).toBe('boolean');
    });
  });

  describe('Auth API', () => {
    it('validates /api/auth/mobile/login response', async () => {
      const response = await axios.post(`${API_BASE}/api/auth/mobile/login`, TEST_USER, {
        headers: { 'Content-Type': 'application/json' },
      });
      expect(response.status).toBe(200);

      // This will throw if validation fails
      const parsed = LoginResponseSchema.parse(response.data);

      expect(parsed.accessToken).toBeDefined();
      expect(parsed.refreshToken).toBeDefined();
      expect(parsed.user.username).toBeDefined();
    });
  });

  describe('Individual Field Validation', () => {
    it('validates book schema fields match OpenAPI spec', async () => {
      const response = await axios.get(`${API_BASE}/api/books/${sampleBookId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      const book = BookDetailResponseSchema.parse(response.data);

      // Verify UUIDs are valid
      expect(book.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);

      // Verify URLs are valid
      expect(book.coverUrl).toMatch(/^https?:\/\//);
      expect(book.audioUrl).toMatch(/^https?:\/\//);

      // Verify nested arrays contain proper objects
      if (book.authors.length > 0) {
        const author = book.authors[0];
        expect(author.id).toMatch(
          /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        );
        expect(author.name).toBeDefined();
      }

      // Verify optional fields are nullable or undefined or string
      expect(
        book.description === null ||
          typeof book.description === 'undefined' ||
          typeof book.description === 'string'
      ).toBe(true);
      expect(
        book.releaseDate === null ||
          typeof book.releaseDate === 'undefined' ||
          typeof book.releaseDate === 'string'
      ).toBe(true);
      expect(
        book.publisher === null ||
          typeof book.publisher === 'undefined' ||
          typeof book.publisher === 'string'
      ).toBe(true);
    });

    it('validates progress schema datetime format', async () => {
      const response = await axios.get(`${API_BASE}/api/progress?bookId=${sampleBookId}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      const progress = ProgressResponseSchema.parse(response.data);

      // Verify lastPlayed is either null or valid ISO 8601 datetime
      if (progress.lastPlayed !== null) {
        const date = new Date(progress.lastPlayed);
        expect(date.toISOString()).toBe(progress.lastPlayed);
      }
    });
  });
});
