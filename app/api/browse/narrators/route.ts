import { NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { prisma } from '@/lib/db';

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const narrators = await prisma.narrator.findMany({
      include: {
        books: {
          include: {
            book: true,
          },
        },
      },
      orderBy: {
        name: 'asc',
      },
    });

    // Transform to include book count
    const transformedNarrators = narrators.map((narrator) => ({
      id: narrator.id,
      name: narrator.name,
      asin: narrator.asin,
      bookCount: narrator.books.length,
    }));

    return NextResponse.json({
      narrators: transformedNarrators,
      total: narrators.length,
    });
  } catch (error) {
    console.error('Error fetching narrators:', error);
    return NextResponse.json({ error: 'Failed to fetch narrators' }, { status: 500 });
  }
}
