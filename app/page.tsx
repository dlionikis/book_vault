import { BooksResponse } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import SearchBar from '@/components/SearchBar';

async function getBooks(): Promise<BooksResponse> {
  const res = await fetch(`http://localhost:3000/api/books?limit=20`, {
    cache: 'no-store',
  });
  
  if (!res.ok) {
    throw new Error('Failed to fetch books');
  }
  
  return res.json();
}

export default async function Home() {
  const data = await getBooks();

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <h1 className="text-3xl font-bold text-gray-900">📚 Book Vault</h1>
          <p className="mt-1 text-sm text-gray-600">
            Your personal audiobook library
          </p>
        </div>
      </header>

      {/* Search Bar */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <SearchBar />
      </div>

      {/* Books Grid */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-12">
        <div className="mb-6">
          <h2 className="text-xl font-semibold text-gray-900">
            All Books
            <span className="ml-2 text-sm font-normal text-gray-600">
              ({data.pagination.total} books)
            </span>
          </h2>
        </div>
        <BookGrid books={data.books} />
      </main>
    </div>
  );
}

