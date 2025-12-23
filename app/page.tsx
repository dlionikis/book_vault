import { BooksResponse } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import SearchBar from '@/components/SearchBar';
import SortDropdown from '@/components/SortDropdown';
import Pagination from '@/components/Pagination';
import Link from 'next/link';

async function getBooks(page?: string, sort?: string): Promise<BooksResponse> {
  const pageParam = page ? `page=${page}` : 'page=1';
  const sortParam = sort ? `&sort=${sort}` : '';
  const res = await fetch(`http://localhost:3000/api/books?${pageParam}&limit=20${sortParam}`, {
    cache: 'no-store',
  });

  if (!res.ok) {
    throw new Error('Failed to fetch books');
  }

  return res.json();
}

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; sort?: string }>;
}) {
  const params = await searchParams;
  const data = await getBooks(params.page, params.sort);

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Search Bar */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <SearchBar />
      </div>

      {/* Browse Navigation */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-8">
        <div className="flex flex-wrap gap-3">
          <Link
            href="/browse/authors"
            className="inline-flex items-center px-4 py-2 bg-white border border-gray-300 rounded-lg shadow-sm text-gray-900 font-medium hover:shadow-md hover:border-blue-500 hover:text-blue-600 transition-all"
          >
            <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
              />
            </svg>
            Browse Authors
          </Link>
          <Link
            href="/browse/narrators"
            className="inline-flex items-center px-4 py-2 bg-white border border-gray-300 rounded-lg shadow-sm text-gray-900 font-medium hover:shadow-md hover:border-blue-500 hover:text-blue-600 transition-all"
          >
            <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
              />
            </svg>
            Browse Narrators
          </Link>
          <Link
            href="/browse/series"
            className="inline-flex items-center px-4 py-2 bg-white border border-gray-300 rounded-lg shadow-sm text-gray-900 font-medium hover:shadow-md hover:border-blue-500 hover:text-blue-600 transition-all"
          >
            <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
              />
            </svg>
            Browse Series
          </Link>
          <Link
            href="/browse/categories"
            className="inline-flex items-center px-4 py-2 bg-white border border-gray-300 rounded-lg shadow-sm text-gray-900 font-medium hover:shadow-md hover:border-blue-500 hover:text-blue-600 transition-all"
          >
            <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"
              />
            </svg>
            Browse Categories
          </Link>
        </div>
      </div>

      {/* Books Grid */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-12">
        <div className="mb-6 flex items-center justify-between">
          <h2 className="text-xl font-semibold text-gray-900">
            All Books
            <span className="ml-2 text-sm font-normal text-gray-600">
              ({data.pagination.total} books)
            </span>
          </h2>
          <SortDropdown />
        </div>
        <BookGrid books={data.books} />
        <Pagination
          currentPage={data.pagination.page}
          totalPages={data.pagination.pages}
          total={data.pagination.total}
          itemName="books"
        />
      </main>
    </div>
  );
}
