import { notFound } from 'next/navigation';
import { Book } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';

interface CategoryWithBooks {
  id: string;
  name: string;
  level: number;
  parentName?: string | null;
  books: Book[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

async function getCategory(id: string, page?: string): Promise<CategoryWithBooks | null> {
  try {
    const pageNum = parseInt(page || '1');
    const limit = 20;
    const skip = (pageNum - 1) * limit;

    const category = await prisma.category.findUnique({
      where: { id },
      include: {
        parent: true,
      },
    });

    if (!category) {
      return null;
    }

    const [bookCategoryEntries, total] = await Promise.all([
      prisma.bookCategory.findMany({
        where: { categoryId: id },
        skip,
        take: limit,
        include: {
          book: {
            include: BOOK_INCLUDE,
          },
        },
        orderBy: {
          book: {
            title: 'asc',
          },
        },
      }),
      prisma.bookCategory.count({
        where: { categoryId: id },
      }),
    ]);

    // Transform books using centralized transformer
    const books = await Promise.all(bookCategoryEntries.map((entry) => transformBook(entry.book)));

    return {
      id: category.id,
      name: category.name,
      level: category.level,
      parentName: category.parent?.name,
      books,
      pagination: {
        page: pageNum,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    };
  } catch (error) {
    console.error('Error fetching category:', error);
    return null;
  }
}

export default async function CategoryPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: Promise<{ page?: string }>;
}) {
  const sp = await searchParams;
  const category = await getCategory(params.id, sp.page);

  if (!category) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Category Header */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-2">{category.name}</h1>

          {category.parentName && (
            <p className="text-lg text-gray-600 dark:text-gray-400 mb-2">
              in {category.parentName}
            </p>
          )}

          <div className="text-gray-600 dark:text-gray-400 text-lg">
            {category.books.length} {category.books.length === 1 ? 'book' : 'books'}
          </div>
        </div>

        {/* Books in Category */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 dark:text-white mb-4">
            Books in {category.name}
          </h2>
          {category.books.length > 0 ? (
            <>
              <BookGrid books={category.books} />
              <Pagination
                currentPage={category.pagination.page}
                totalPages={category.pagination.pages}
                total={category.pagination.total}
                itemName="books"
              />
            </>
          ) : (
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-8 text-center text-gray-500 dark:text-gray-400">
              No books found in this category
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
