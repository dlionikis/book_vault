/**
 * Zod schemas for runtime validation of API responses
 * These schemas match the generated TypeScript types in lib/api-types.ts
 *
 * Purpose: Ensure that actual API responses conform to the OpenAPI specification
 * at runtime, catching any mismatches between spec and implementation.
 */

import { z } from 'zod';

// Base schemas
export const ErrorSchema = z.object({
  error: z.string(),
});

export const PaginationSchema = z.object({
  page: z.number(),
  limit: z.number(),
  total: z.number(),
  pages: z.number(),
});

// Author schema
export const AuthorSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  asin: z.string().nullable().optional(),
});

// Narrator schema
export const NarratorSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  asin: z.string().nullable().optional(),
});

// SeriesInfo schema
export const SeriesInfoSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  sequence: z.string().nullable().optional(),
  asin: z.string().nullable().optional(),
});

// Category schema
export const CategorySchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
});

// Book schema (full)
export const BookSchema = z.object({
  id: z.string().uuid(),
  asin: z.string(),
  title: z.string(),
  description: z.string().nullable().optional(),
  runtimeMinutes: z.number(),
  releaseDate: z.string().nullable().optional(),
  publisher: z.string().nullable().optional(),
  coverUrl: z.string().url(),
  audioUrl: z.string().url(),
  authors: z.array(AuthorSchema),
  narrators: z.array(NarratorSchema).optional(),
  series: z.array(SeriesInfoSchema).optional(),
  categories: z.array(CategorySchema).optional(),
});

// Chapter schema
export const ChapterSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  startTime: z.number(),
  endTime: z.number(),
  index: z.number(),
});

// UserProgress schema
export const UserProgressSchema = z.object({
  id: z.string().uuid(),
  bookId: z.string().uuid(),
  userId: z.string().uuid(),
  positionSeconds: z.number(),
  completed: z.boolean(),
  lastPlayed: z.string().datetime(),
});

// User schema
export const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
});

// AuthorWithBookCount schema
export const AuthorWithBookCountSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  asin: z.string().nullable().optional(),
  bookCount: z.number(),
});

// SeriesWithBookCount schema
export const SeriesWithBookCountSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  bookCount: z.number(),
});

// NarratorWithBookCount schema
export const NarratorWithBookCountSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  asin: z.string().nullable().optional(),
  bookCount: z.number(),
});

// CategoryWithBookCount schema
export const CategoryWithBookCountSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  bookCount: z.number(),
});

// Response schemas (API endpoint responses)

// Books list response
export const BooksListResponseSchema = z.object({
  books: z.array(BookSchema),
  pagination: PaginationSchema,
});

// Book detail response
export const BookDetailResponseSchema = BookSchema;

// Chapters response
export const ChaptersResponseSchema = z.object({
  chapters: z.array(ChapterSchema),
});

// Progress response
export const ProgressResponseSchema = z.object({
  positionSeconds: z.number(),
  completed: z.boolean(),
  lastPlayed: z.string().datetime().nullable(),
});

// Authors list response
export const AuthorsListResponseSchema = z.object({
  results: z.array(AuthorWithBookCountSchema),
  pagination: PaginationSchema,
});

// Author detail response
export const AuthorDetailResponseSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  asin: z.string().nullable().optional(),
  books: z.array(BookSchema),
});

// Series list response
export const SeriesListResponseSchema = z.object({
  results: z.array(SeriesWithBookCountSchema),
  pagination: PaginationSchema,
});

// Series detail response
export const SeriesDetailResponseSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  books: z.array(BookSchema),
});

// Narrators list response
export const NarratorsListResponseSchema = z.object({
  results: z.array(NarratorWithBookCountSchema),
  pagination: PaginationSchema,
});

// Narrator detail response
export const NarratorDetailResponseSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  asin: z.string().nullable().optional(),
  books: z.array(BookSchema),
});

// Categories list response
export const CategoriesListResponseSchema = z.object({
  results: z.array(CategoryWithBookCountSchema),
  pagination: PaginationSchema,
});

// Category detail response
export const CategoryDetailResponseSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  books: z.array(BookSchema),
});

// Search response
export const SearchResponseSchema = z.object({
  results: z.array(BookSchema),
  pagination: PaginationSchema,
});

// Auth responses
export const LoginResponseSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  user: UserSchema,
});

export const RefreshTokenResponseSchema = z.object({
  accessToken: z.string(),
});

export const VerifyTokenResponseSchema = z.object({
  valid: z.boolean(),
  userId: z.string().uuid().optional(),
});

// Library responses
export const LibraryResponseSchema = z.object({
  books: z.array(BookSchema),
});

export const LibraryCheckResponseSchema = z.object({
  inLibrary: z.boolean(),
});
