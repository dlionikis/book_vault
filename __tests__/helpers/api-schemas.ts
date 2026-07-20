/**
 * Zod schemas for runtime validation of API responses
 * These schemas match the generated TypeScript types in lib/api-types.ts
 *
 * Purpose: Ensure that actual API responses conform to the OpenAPI specification
 * at runtime, catching any mismatches between spec and implementation.
 *
 * Why Zod?
 * - Runtime type checking (TypeScript only validates at compile time)
 * - Detailed error messages for debugging
 * - Type inference (schemas can generate TypeScript types)
 * - Transformation support (e.g., coerce strings to dates)
 * - Composable and reusable schemas
 */

import { z } from 'zod';

/**
 * Standard error response schema.
 * All API errors return this format with appropriate HTTP status code.
 */
export const ErrorSchema = z.object({
  /** Human-readable error message */
  error: z.string(),
});

/**
 * Pagination metadata schema.
 * Used in all paginated list endpoints for consistency.
 */
export const PaginationSchema = z.object({
  /** Current page number (1-indexed) */
  page: z.number(),

  /** Maximum items per page */
  limit: z.number(),

  /** Total items across all pages */
  total: z.number(),

  /** Total number of pages */
  pages: z.number(),
});

/**
 * Author schema with UUID validation.
 * UUID validation ensures IDs are properly formatted before database queries.
 */
export const AuthorSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Author name, required */
  name: z.string(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),
});

/**
 * Narrator schema with UUID validation.
 */
export const NarratorSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Narrator name, required */
  name: z.string(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),
});

/**
 * SeriesInfo schema including sequence number.
 * Sequence can be null if book position in series is unknown.
 */
export const SeriesInfoSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Series title */
  title: z.string(),

  /** Book's position in series (1-indexed), nullable if unknown */
  sequence: z.number().nullable().optional(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),
});

/**
 * Category/Genre schema.
 */
export const CategorySchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Category name (e.g., "Science Fiction") */
  name: z.string(),
});

/**
 * Complete book schema with all metadata and relationships.
 * This is the core schema used for book validation throughout the API.
 * URLs are validated to prevent serving broken links.
 */
export const BookSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Amazon Standard Identification Number */
  asin: z.string(),

  /** Book title, required */
  title: z.string(),

  /** Audio availability (S3 IT archive state). Optional: absent from pre-restore backends → treat as available. */
  archiveStatus: z.enum(['available', 'archived', 'restoring']).optional(),

  /** Publisher summary in Markdown, optional */
  description: z.string().nullable().optional(),

  /** Total runtime in minutes */
  runtimeMinutes: z.number(),

  /** Release date as ISO 8601 string (YYYY-MM-DD) */
  releaseDate: z.string().nullable().optional(),

  /** Publisher name */
  publisher: z.string().nullable().optional(),

  /** Cover image URL - validated as valid URL format */
  coverUrl: z.url(),

  /** Audio file URL - validated as valid URL format */
  audioUrl: z.url(),

  /** Array of authors - ensures at least empty array (never null) */
  authors: z.array(AuthorSchema),

  /** Array of narrators - optional, defaults to empty array */
  narrators: z.array(NarratorSchema).optional(),

  /** Array of series - optional, defaults to empty array */
  series: z.array(SeriesInfoSchema).optional(),

  /** Array of categories - optional, defaults to empty array */
  categories: z.array(CategorySchema).optional(),
});

/**
 * Chapter/section schema for book navigation.
 * Chapters divide audiobook into logical segments for easier navigation.
 * Times are in seconds from the start of the audiobook.
 */
export const ChapterSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Chapter name (e.g., "Prologue", "Chapter 1") */
  title: z.string(),

  /** Start position in seconds from beginning of audio file */
  startTime: z.number(),

  /** End position in seconds from beginning of audio file */
  endTime: z.number(),

  /** Chapter number (0-indexed), used for ordering */
  index: z.number(),
});

/**
 * User progress tracking schema.
 * Stores playback position and completion status per user per book.
 * Datetime validated to ensure proper ISO 8601 format.
 */
export const UserProgressSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Reference to the book being tracked */
  bookId: z.uuid(),

  /** Reference to the user */
  userId: z.uuid(),

  /** Current playback position in seconds */
  positionSeconds: z.number(),

  /** True if user has finished the book */
  completed: z.boolean(),

  /** ISO 8601 datetime string of most recent playback */
  lastPlayed: z.iso.datetime(),
});

/**
 * User account schema.
 * Contains minimal user information exposed to API.
 */
export const UserSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Username */
  username: z.string(),
});

/**
 * Author with book count schema.
 * Extended author info for browse pages showing how many books each author has.
 * bookCount is derived from Prisma _count aggregation.
 */
export const AuthorWithBookCountSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Author name */
  name: z.string(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),

  /** Number of books by this author in the database */
  bookCount: z.number(),
});

/**
 * Series with book count schema.
 * Extended series info showing total books in series.
 */
export const SeriesWithBookCountSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Series title */
  title: z.string(),

  /** Number of books in this series in the database */
  bookCount: z.number(),
});

/**
 * Narrator with book count schema.
 * Extended narrator info for browse pages.
 */
export const NarratorWithBookCountSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Narrator name */
  name: z.string(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),

  /** Number of books narrated by this narrator */
  bookCount: z.number(),
});

/**
 * Category with book count schema.
 * Extended category info for browse pages.
 */
export const CategoryWithBookCountSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Category name */
  name: z.string(),

  /** Number of books in this category */
  bookCount: z.number(),
});

/**
 * Response schemas for API endpoints.
 * These schemas validate the complete response structure including data and metadata.
 */

/**
 * Books list response schema.
 * Used by GET /api/books and similar paginated book list endpoints.
 */
export const BooksListResponseSchema = z.object({
  /** Array of books matching query */
  books: z.array(BookSchema),

  /** Pagination metadata for navigation */
  pagination: PaginationSchema,
});

/**
 * Single book detail response schema.
 * Used by GET /api/books/[id] endpoint.
 */
export const BookDetailResponseSchema = BookSchema;

/**
 * Chapters list response schema.
 * Used by GET /api/books/[id]/chapters endpoint.
 * Returns all chapters for a specific book.
 */
export const ChaptersResponseSchema = z.object({
  /** Array of chapters ordered by index */
  chapters: z.array(ChapterSchema),
});

/**
 * Progress status response schema.
 * Used by GET /api/progress to return user's current playback state.
 */
export const ProgressResponseSchema = z.object({
  /** Current playback position in seconds */
  positionSeconds: z.number(),

  /** Whether user has completed the book */
  completed: z.boolean(),

  /** ISO 8601 datetime of last playback, null if never played */
  lastPlayed: z.iso.datetime().nullable(),
});

/**
 * Authors list response schema.
 * Used by GET /api/authors for paginated author browsing.
 */
export const AuthorsListResponseSchema = z.object({
  /** Array of authors with book counts */
  results: z.array(AuthorWithBookCountSchema),

  /** Pagination metadata */
  pagination: PaginationSchema,
});

/**
 * Author detail response schema.
 * Used by GET /api/authors/[id] to show author info and their books.
 */
export const AuthorDetailResponseSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Author name */
  name: z.string(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),

  /** All books by this author */
  books: z.array(BookSchema),
});

/**
 * Series list response schema.
 * Used by GET /api/series for paginated series browsing.
 */
export const SeriesListResponseSchema = z.object({
  /** Array of series with book counts */
  results: z.array(SeriesWithBookCountSchema),

  /** Pagination metadata */
  pagination: PaginationSchema,
});

/**
 * Series detail response schema.
 * Used by GET /api/series/[id] to show series info and all books in series.
 */
export const SeriesDetailResponseSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Series title */
  title: z.string(),

  /** All books in this series, ordered by sequence */
  books: z.array(BookSchema),
});

/**
 * Narrators list response schema.
 * Used by GET /api/narrators for paginated narrator browsing.
 */
export const NarratorsListResponseSchema = z.object({
  /** Array of narrators with book counts */
  results: z.array(NarratorWithBookCountSchema),

  /** Pagination metadata */
  pagination: PaginationSchema,
});

/**
 * Narrator detail response schema.
 * Used by GET /api/narrators/[id] to show narrator info and their books.
 */
export const NarratorDetailResponseSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Narrator name */
  name: z.string(),

  /** Optional ASIN from Audible */
  asin: z.string().nullable().optional(),

  /** All books narrated by this person */
  books: z.array(BookSchema),
});

/**
 * Categories list response schema.
 * Used by GET /api/categories for paginated category browsing.
 */
export const CategoriesListResponseSchema = z.object({
  /** Array of categories with book counts */
  results: z.array(CategoryWithBookCountSchema),

  /** Pagination metadata */
  pagination: PaginationSchema,
});

/**
 * Category detail response schema.
 * Used by GET /api/categories/[id] to show all books in a category.
 */
export const CategoryDetailResponseSchema = z.object({
  /** UUID v4 format enforced */
  id: z.uuid(),

  /** Category name */
  name: z.string(),

  /** All books in this category */
  books: z.array(BookSchema),
});

/**
 * Search results response schema.
 * Used by GET /api/search for full-text search across books.
 * Returns books matching title, author, or narrator search query.
 */
export const SearchResponseSchema = z.object({
  /** Books matching search query */
  results: z.array(BookSchema),

  /** Pagination metadata */
  pagination: PaginationSchema,
});

/**
 * Authentication response schemas.
 * Used by mobile authentication endpoints for JWT token management.
 */

/**
 * Login response schema.
 * Used by POST /api/auth/mobile/login after successful authentication.
 * Returns JWT tokens for mobile API access.
 */
export const LoginResponseSchema = z.object({
  /** JWT access token (short-lived, ~15 min) */
  accessToken: z.string(),

  /** JWT refresh token (long-lived, ~7 days) */
  refreshToken: z.string(),

  /** Basic user information */
  user: UserSchema,
});

/**
 * Refresh token response schema.
 * Used by POST /api/auth/mobile/refresh to get new access token.
 */
export const RefreshTokenResponseSchema = z.object({
  /** New JWT access token */
  accessToken: z.string(),
});

/**
 * Token verification response schema.
 * Used by POST /api/auth/mobile/verify to check if token is valid.
 */
export const VerifyTokenResponseSchema = z.object({
  /** Whether the token is valid */
  valid: z.boolean(),

  /** User ID if token is valid, undefined otherwise */
  userId: z.uuid().optional(),
});

/**
 * Library response schemas.
 * Used by library management endpoints for tracking user's personal collection.
 */

/**
 * User library response schema.
 * Used by GET /api/library to return all books in user's library.
 */
export const LibraryResponseSchema = z.object({
  /** Books in user's personal library */
  books: z.array(BookSchema),
});

/**
 * Library check response schema.
 * Used by GET /api/library/check?bookId=... to verify if book is in library.
 * Useful for showing "Add to Library" vs "In Library" button states.
 */
export const LibraryCheckResponseSchema = z.object({
  /** True if book is in user's library */
  inLibrary: z.boolean(),
});
