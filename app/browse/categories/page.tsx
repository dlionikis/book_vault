import Link from 'next/link';
import BackButton from '@/components/BackButton';

interface CategoryWithCount {
  id: string;
  name: string;
  level: number;
  parentName?: string | null;
  bookCount: number;
}

async function getCategories(): Promise<CategoryWithCount[]> {
  try {
    const res = await fetch('http://localhost:3000/api/browse/categories', {
      next: { revalidate: 0 },
    });

    if (!res.ok) {
      return [];
    }

    const data = await res.json();
    return data.categories || [];
  } catch (error) {
    console.error('Error fetching categories:', error);
    return [];
  }
}

export default async function BrowseCategoriesPage() {
  const categories = await getCategories();

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <BackButton />

          <h1 className="text-3xl font-bold text-gray-900">Browse by Category</h1>
          <p className="text-gray-600 mt-2">
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
                className="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow block"
              >
                <h3 className="text-lg font-semibold text-gray-900 mb-1 hover:text-blue-600">
                  {category.name}
                </h3>
                {category.parentName && (
                  <p className="text-xs text-gray-500 mb-2">in {category.parentName}</p>
                )}
                <p className="text-sm text-gray-600">
                  {category.bookCount} {category.bookCount === 1 ? 'book' : 'books'}
                </p>
              </Link>
            ))}
          </div>
        ) : (
          <div className="text-center py-12">
            <svg
              className="mx-auto h-16 w-16 text-gray-400"
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
