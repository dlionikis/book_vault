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
    const authors = await prisma.author.findMany({
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
    const transformedAuthors = authors.map((author) => ({
      id: author.id,
      name: author.name,
      asin: author.asin,
      bookCount: author.books.length,
    }));

    return NextResponse.json({
      authors: transformedAuthors,
      total: authors.length,
    });
  } catch (error) {
    console.error('Error fetching authors:', error);
    return NextResponse.json({ error: 'Failed to fetch authors' }, { status: 500 });
  }

}
