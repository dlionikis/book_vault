import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { logger } from '@/lib/logger';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';
import { normalizeUuid, buildPagination, parsePagination } from '@/lib/api-utils';

/**
 * Configuration for entity detail endpoints that return paginated books.
 * Used by handleEntityDetailWithBooks() to customize behavior per entity type.
 */
export interface EntityDetailConfig<TEntity> {
  /** The Prisma model for the main entity (e.g., prisma.author) */
  entityModel: any;

  /** The Prisma model for the join table (e.g., prisma.bookAuthor) */
  joinTableModel: any;

  /** The name of the ID field in the where clause (e.g., 'authorId') */
  idFieldName: string;

  /** Entity name for error messages (e.g., 'Author') */
  entityName: string;

  /** Function to extract response fields from the entity */
  getResponseFields: (entity: TEntity) => Record<string, any>;

  /** Optional: Custom orderBy for books (defaults to book.title asc) */
  orderBy?: any;

  /** Optional: Additional include fields for entity fetch */
  entityInclude?: any;
}

/**
 * Generic handler for entity detail endpoints that return paginated books.
 * Handles authentication, validation, entity fetching, book fetching, and pagination.
 *
 * This helper consolidates the common pattern used by:
 * - GET /api/authors/{id}
 * - GET /api/narrators/{id}
 * - GET /api/series/{id}
 * - GET /api/categories/{id}
 *
 * @example
 * // Authors endpoint
 * return handleEntityDetailWithBooks(request, params, {
 *   entityModel: prisma.author,
 *   joinTableModel: prisma.bookAuthor,
 *   idFieldName: 'authorId',
 *   entityName: 'Author',
 *   getResponseFields: (author) => ({
 *     id: author.id,
 *     name: author.name,
 *     asin: author.asin,
 *   }),
 * });
 *
 * @example
 * // Series endpoint with custom sort
 * return handleEntityDetailWithBooks(request, params, {
 *   entityModel: prisma.series,
 *   joinTableModel: prisma.bookSeries,
 *   idFieldName: 'seriesId',
 *   entityName: 'Series',
 *   getResponseFields: (series) => ({
 *     id: series.id,
 *     title: series.title,
 *     asin: series.asin,
 *   }),
 *   orderBy: [{ sequence: 'asc' }], // Sort by series sequence instead of title
 * });
 *
 * @param request - Next.js request object
 * @param params - Route params containing the entity ID
 * @param config - Configuration object specifying entity-specific behavior
 * @returns NextResponse with entity details and paginated books
 */
export async function handleEntityDetailWithBooks<TEntity>(
  request: NextRequest,
  params: { id: string },
  config: EntityDetailConfig<TEntity>
): Promise<NextResponse> {
  // 1. Check authentication (both session and mobile bearer token)
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  // 2. Normalize and validate UUID
  const entityId = normalizeUuid(params.id);
  if (!entityId) {
    return NextResponse.json(
      { error: `Invalid ${config.entityName.toLowerCase()} ID format` },
      { status: 400 }
    );
  }

  try {
    // 3. Parse pagination parameters
    const searchParams = request.nextUrl.searchParams;
    // parsePagination caps limit at 100 (same as /api/books) — a raw parseInt
    // here let `limit=1000000` through on the entity-detail endpoints.
    const { page, limit, skip } = parsePagination(
      searchParams.get('page'),
      searchParams.get('limit')
    );

    // 4. Fetch the main entity
    const entity = await config.entityModel.findUnique({
      where: { id: entityId },
      include: config.entityInclude,
    });

    if (!entity) {
      return NextResponse.json({ error: `${config.entityName} not found` }, { status: 404 });
    }

    // 5. Fetch related books via join table with pagination
    // Default orderBy to book.title asc unless custom orderBy provided
    const orderBy = config.orderBy || { book: { title: 'asc' } };
    const whereClause = { [config.idFieldName]: entityId };

    const [joinEntries, total] = await Promise.all([
      config.joinTableModel.findMany({
        where: whereClause,
        skip,
        take: limit,
        include: {
          book: {
            include: BOOK_INCLUDE,
          },
        },
        orderBy,
      }),
      config.joinTableModel.count({
        where: whereClause,
      }),
    ]);

    // 6. Transform book data to include full URLs and proper structure
    // Note: transformBook is async (generates presigned URLs), so we must await all
    const booksWithUrls = await Promise.all(
      joinEntries.map((entry: any) => transformBook(entry.book))
    );

    // 7. Build and return response
    return NextResponse.json({
      ...config.getResponseFields(entity),
      books: booksWithUrls,
      pagination: buildPagination(page, limit, total),
    });
  } catch (error) {
    logger.error(`Error fetching ${config.entityName.toLowerCase()}`, { error: String(error) });
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
