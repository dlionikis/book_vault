import { notFound } from 'next/navigation';
import { Book, Series } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';

interface SeriesWithBooks extends Series {
  books: Book[];
}

async function getSeries(id: string): Promise<SeriesWithBooks | null> {
  try {
    const res = await fetch(`http://localhost:3000/api/series/${id}`, {
      next: { revalidate: 0 }
    });

    if (!res.ok) {
      return null;
    }

    return res.json();
  } catch (error) {
    console.error('Error fetching series:', error);
    return null;
  }
}

export default async function SeriesPage({ params }: { params: { id: string } }) {
  const series = await getSeries(params.id);

  if (!series) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Series Header */}
        <div className="bg-white rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">
            {series.name}
          </h1>
          
          <div className="text-gray-600 text-lg">
            {series.books.length} {series.books.length === 1 ? 'book' : 'books'} in this series
          </div>
        </div>

        {/* Books in Series */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">
            Books in Series Order
          </h2>
          {series.books.length > 0 ? (
            <BookGrid books={series.books} />
          ) : (
            <div className="bg-white rounded-lg shadow p-8 text-center text-gray-500">
              No books found in this series
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
