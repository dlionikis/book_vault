import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';
import { getCoverUrl, getAudioUrl } from '@/lib/media';
import { parseBookFields, parsePagination, buildPagination } from '@/lib/api-utils';
import { buildSearchWhere, searchBooks } from '@/lib/queries/search-books';
import { logger, withLogging } from '@/lib/logger';

export const GET = withLogging(async (request: NextRequest) => {
  // Check both auth methods
  const auth = await requireUser(request);
  if (auth.error) return auth.error;
  try {
    const searchParams = request.nextUrl.searchParams;
    const query = (searchParams.get('q') || '').trim();
    const fieldsParam = searchParams.get('fields');
    const { page, limit, skip } = parsePagination(
      searchParams.get('page'),
      searchParams.get('limit')
    );

    if (!query) {
      return NextResponse.json({ error: 'Search query is required' }, { status: 400 });
    }

    // Parse field filtering
    const select = parseBookFields(fieldsParam);

    // Field-filtered responses (?fields=) need a bespoke `select`, so they run
    // their own query — but off the SAME where builder as the shared path, so
    // the visibility filter still applies.
    const where = buildSearchWhere(query);

    let transformedBooks: unknown[];
    let total: number;

    if (select) {
      const [rows, count] = await Promise.all([
        prisma.book.findMany({ where, skip, take: limit, select, orderBy: { title: 'asc' } }),
        prisma.book.count({ where }),
      ]);
      total = count;
      transformedBooks = await Promise.all(
        rows.map(async (book) => {
          const result: Record<string, unknown> = {};
          for (const [key, value] of Object.entries(book)) {
            if (key === 'coverUrl') {
              result[key] = await getCoverUrl(value as string | null);
            } else if (key === 'audioUrl') {
              result[key] = await getAudioUrl(value as string | null);
            } else {
              result[key] = value;
            }
          }
          return result;
        })
      );
    } else {
      const result = await searchBooks(query, { skip, limit });
      transformedBooks = result.books;
      total = result.total;
    }

    return NextResponse.json({
      results: transformedBooks,
      pagination: buildPagination(page, limit, total),
    });
  } catch (error) {
    logger.error('Error searching books', { error: String(error) });
    return NextResponse.json({ error: 'Failed to search books' }, { status: 500 });
  }
});
