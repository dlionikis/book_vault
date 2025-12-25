import { Prisma } from '@prisma/client';

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
