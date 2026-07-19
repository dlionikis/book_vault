import Link from 'next/link';
import BackButton from '@/components/BackButton';
import { prisma } from '@/lib/db';

// This page is DB-backed and must render per-request. Without this, Next tries
// to statically prerender it during `next build` (where DATABASE_URL is unset),
// the Prisma query throws, the try/catch swallows it, and the build log fills
// with PrismaClientInitializationError noise. force-dynamic makes Next render it
// at request time (as it already does in prod) and keeps the build log clean.
export const dynamic = 'force-dynamic';

interface CategoryWithCount {
  id: string;
  name: string;
  level: number;
  parentName?: string | null;
  bookCount: number;
}

async function getCategories(): Promise<CategoryWithCount[]> {
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

    return categories.map((category) => ({
      id: category.id,
      name: category.name,
      level: category.level,
      parentName: category.parent?.name || null,
      bookCount: category.books.length,
    }));
  } catch (error) {
    console.error('Error fetching categories:', error);
    return [];
  }
}

export default async function BrowseCategoriesPage() {
  const categories = await getCategories();

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <BackButton />

          <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Browse by Category</h1>
          <p className="text-gray-600 dark:text-gray-400 mt-2">
            {categories.length} {categories.length === 1 ? 'category' : 'categories'}
          </p>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {categories.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {categories.map((category) => (
              <Link
                key={category.id}
                href={`/categories/${category.id}`}
                className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow block"
              >
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-1 hover:text-blue-600 dark:hover:text-blue-400">
                  {category.name}
                </h3>
                {category.parentName && (
                  <p className="text-xs text-gray-500 dark:text-gray-400 mb-2">
                    in {category.parentName}
                  </p>
                )}
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  {category.bookCount} {category.bookCount === 1 ? 'book' : 'books'}
                </p>
              </Link>
            ))}
          </div>
        ) : (
          <div className="text-center py-12">
            <svg
              className="mx-auto h-16 w-16 text-gray-400 dark:text-gray-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"
              />
            </svg>
            <h3 className="mt-4 text-lg font-medium text-gray-900">No categories found</h3>
            <p className="mt-2 text-gray-500">Add some audiobooks to see categories here</p>
          </div>
        )}
      </main>
    </div>
  );
}
