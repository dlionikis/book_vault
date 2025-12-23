import { notFound } from 'next/navigation';
import { Book } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';

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
    const pageParam = page ? `?page=${page}` : '';
    const res = await fetch(`http://localhost:3000/api/categories/${id}${pageParam}`, {
      next: { revalidate: 0 },
    });

    if (!res.ok) {
      return null;
    }

    return res.json();
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
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Category Header */}
        <div className="bg-white rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">{category.name}</h1>

          {category.parentName && (
            <p className="text-lg text-gray-600 mb-2">in {category.parentName}</p>
          )}

          <div className="text-gray-600 text-lg">
            {category.books.length} {category.books.length === 1 ? 'book' : 'books'}
          </div>
        </div>

        {/* Books in Category */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">Books in {category.name}</h2>
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
            <div className="bg-white rounded-lg shadow p-8 text-center text-gray-500">
              No books found in this category
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
