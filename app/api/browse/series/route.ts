import { NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET() {
  try {
    const series = await prisma.series.findMany({
      include: {
        books: {
          include: {
            book: true,
          },
          orderBy: {
            sequence: 'asc',
          },
        },
      },
      orderBy: {
        title: 'asc',
      },
    });

    // Transform to include book count
    const transformedSeries = series.map(s => ({
      id: s.id,
      title: s.title,
      asin: s.asin,
      bookCount: s.books.length,
    }));

    return NextResponse.json({
      series: transformedSeries,
      total: series.length,
    });
  } catch (error) {
    console.error('Error fetching series:', error);
    return NextResponse.json(
      { error: 'Failed to fetch series' },
      { status: 500 }
    );
  } finally {
    await prisma.$disconnect();
  }
}
