import { Prisma } from '@/lib/generated/prisma/client';

/**
 * Parse comma-separated fields parameter into Prisma select object
 * @param fieldsParam - Comma-separated field list (e.g., "id,title,coverUrl")
 * @returns Prisma select object or undefined for all fields
 */
export function parseBookFields(fieldsParam: string | null): Prisma.BookSelect | undefined {
  if (!fieldsParam) {
    return undefined; // Return all fields
  }

  const requestedFields = fieldsParam.split(',').map((f) => f.trim());
  const select: Prisma.BookSelect = {};

  // Map common field names to database fields
  const fieldMap: Record<string, keyof Prisma.BookSelect> = {
    id: 'id',
    asin: 'asin',
    title: 'title',
    description: 'description',
    publisherSummary: 'publisherSummary',
    runtimeMinutes: 'runtimeMinutes',
    releaseDate: 'releaseDate',
    publisher: 'publisher',
    coverUrl: 'coverUrl',
    audioUrl: 'audioUrl',
    createdAt: 'createdAt',
    updatedAt: 'updatedAt',
    authors: 'authors',
    narrators: 'narrators',
    series: 'series',
    categories: 'categories',
    chapters: 'chapters',
  };

  // Build select object
  for (const field of requestedFields) {
    const dbField = fieldMap[field];
    if (dbField) {
      if (
        dbField === 'authors' ||
        dbField === 'narrators' ||
        dbField === 'series' ||
        dbField === 'categories' ||
        dbField === 'chapters'
      ) {
        // For relations, include with nested data
        if (dbField === 'authors') {
          select.authors = { include: { author: true } };
        } else if (dbField === 'narrators') {
          select.narrators = { include: { narrator: true } };
        } else if (dbField === 'series') {
          select.series = { include: { series: true } };
        } else if (dbField === 'categories') {
          select.categories = { include: { category: true } };
        } else if (dbField === 'chapters') {
          select.chapters = { orderBy: { chapterNumber: 'asc' } };
        }
      } else {
        select[dbField] = true;
      }
    }
  }

  // If select is empty, return undefined to get all fields
  return Object.keys(select).length > 0 ? select : undefined;
}

/**
 * Validate and constrain pagination parameters
 * @param pageParam - Page number (1-based)
 * @param limitParam - Results per page
 * @returns Validated pagination params
 */
export function parsePagination(
  pageParam: string | null,
  limitParam: string | null
): { page: number; limit: number; skip: number } {
  const page = Math.max(1, parseInt(pageParam || '1'));
  const limit = Math.min(100, Math.max(1, parseInt(limitParam || '20')));
  const skip = (page - 1) * limit;

  return { page, limit, skip };
}

/**
 * Normalize UUID to lowercase for database queries
 * Database stores UUIDs as lowercase text, but clients may send uppercase.
 * This ensures case-insensitive UUID matching.
 *
 * @param uuid - UUID string in any case
 * @returns Lowercase UUID string, or original value if null/undefined
 *
 * @example
 * normalizeUuid('6D211133-3B31-41B4-8B83-191121CEE02A') // '6d211133-3b31-41b4-8b83-191121cee02a'
 * normalizeUuid(null) // null
 */
export function normalizeUuid(uuid: string | null | undefined): string | null | undefined {
  return uuid ? uuid.toLowerCase() : uuid;
}

/**
 * Type guard to validate UUID format and ensure non-null type
 * Checks both truthiness and proper UUID format (8-4-4-4-12 hex pattern)
 *
 * @param uuid - UUID string to validate
 * @returns True if valid UUID format, false otherwise (with type narrowing)
 *
 * @example
 * const id = normalizeUuid(params.id);
 * if (!isValidUuid(id)) {
 *   return NextResponse.json({ error: 'Invalid ID' }, { status: 400 });
 * }
 * // TypeScript now knows id is string (not string | null | undefined)
 */
export function isValidUuid(uuid: string | null | undefined): uuid is string {
  if (!uuid) return false;

  // UUID v4 format: 8-4-4-4-12 hexadecimal characters
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

/**
 * Pagination result interface
 */
export interface PaginationResult {
  page: number;
  limit: number;
  total: number;
  pages: number;
}

/**
 * Build pagination object with calculated page count
 * Centralizes the pagination calculation logic used across all paginated endpoints
 *
 * @param page - Current page number (1-based)
 * @param limit - Items per page
 * @param total - Total number of items
 * @returns Pagination object with calculated pages
 *
 * @example
 * const pagination = buildPagination(1, 20, 157);
 * // { page: 1, limit: 20, total: 157, pages: 8 }
 */
export function buildPagination(page: number, limit: number, total: number): PaginationResult {
  return {
    page,
    limit,
    total,
    pages: Math.ceil(total / limit),
  };
}
