import { NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET() {
  try {
    const categories = await prisma.category.findMany({
      include: {
        books: {
          include: {
            book: true,
          },
        },
        parent: true,
      },
      orderBy: {
        name: 'asc',
      },
    });

    // Transform to include book count and parent name
    const transformedCategories = categories.map(category => ({
      id: category.id,
      name: category.name,
      level: category.level,
      parentName: category.parent?.name || null,
      bookCount: category.books.length,
    }));

    return NextResponse.json({
      categories: transformedCategories,
      total: categories.length,
    });
  } catch (error) {
    console.error('Error fetching categories:', error);
    return NextResponse.json(
      { error: 'Failed to fetch categories' },
      { status: 500 }
    );
  } finally {
    await prisma.$disconnect();
  }
}
