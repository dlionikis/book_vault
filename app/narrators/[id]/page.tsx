import { notFound } from 'next/navigation';
import { Book, Narrator } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';

interface NarratorWithBooks extends Narrator {
  books: Book[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

async function getNarrator(id: string, page?: string): Promise<NarratorWithBooks | null> {
  try {
    const pageParam = page ? `?page=${page}` : '';
    const res = await fetch(`http://localhost:3000/api/narrators/${id}${pageParam}`, {
      next: { revalidate: 0 },
    });

    if (!res.ok) {
      return null;
    }

    return res.json();
  } catch (error) {
    console.error('Error fetching narrator:', error);
    return null;
  }
}

export default async function NarratorPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: Promise<{ page?: string }>;
}) {
  const sp = await searchParams;
  const narrator = await getNarrator(params.id, sp.page);

  if (!narrator) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Narrator Header */}
        <div className="bg-white rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">{narrator.name}</h1>

          <div className="text-gray-600 text-lg">
            {narrator.books.length} {narrator.books.length === 1 ? 'book' : 'books'}
          </div>
        </div>

        {/* Books by Narrator */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">
            Books narrated by {narrator.name}
          </h2>
          {narrator.books.length > 0 ? (
            <>
              <BookGrid books={narrator.books} />
              <Pagination
                currentPage={narrator.pagination.page}
                totalPages={narrator.pagination.pages}
                total={narrator.pagination.total}
                itemName="books"
              />
            </>
          ) : (
            <div className="bg-white rounded-lg shadow p-8 text-center text-gray-500">
              No books found for this narrator
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
