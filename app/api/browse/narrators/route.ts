import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { parsePagination } from '@/lib/api-utils';

export async function GET(request: NextRequest) {
  // Check both auth methods
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const { page, limit, skip } = parsePagination(
      searchParams.get('page'),
      searchParams.get('limit')
    );

    const [narrators, total] = await Promise.all([
      prisma.narrator.findMany({
        skip,
        take: limit,
        include: {
          _count: {
            select: {
              books: true,
            },
          },
        },
        orderBy: {
          name: 'asc',
        },
      }),
      prisma.narrator.count(),
    ]);

    // Transform to include book count
    const transformedNarrators = narrators.map((narrator) => ({
      id: narrator.id,
      name: narrator.name,
      asin: narrator.asin,
      bookCount: narrator._count.books,
    }));

    return NextResponse.json({
      results: transformedNarrators,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('Error fetching narrators:', error);
    return NextResponse.json({ error: 'Failed to fetch narrators' }, { status: 500 });
  }
}
