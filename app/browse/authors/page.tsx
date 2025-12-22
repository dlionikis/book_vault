import Link from 'next/link';
import BackButton from '@/components/BackButton';

interface AuthorWithCount {
  id: string;
  name: string;
  asin?: string | null;
  bookCount: number;
}

async function getAuthors(): Promise<AuthorWithCount[]> {
  try {
    const res = await fetch('http://localhost:3000/api/browse/authors', {
      next: { revalidate: 0 }
    });

    if (!res.ok) {
      return [];
    }

    const data = await res.json();
    return data.authors || [];
  } catch (error) {
    console.error('Error fetching authors:', error);
    return [];
  }
}

export default async function BrowseAuthorsPage() {
  const authors = await getAuthors();

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <BackButton />
          
          <h1 className="text-3xl font-bold text-gray-900">Browse by Author</h1>
          <p className="text-gray-600 mt-2">
            {authors.length} {authors.length === 1 ? 'author' : 'authors'}
          </p>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {authors.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {authors.map((author) => (
              <Link
                key={author.id}
                href={`/authors/${author.id}`}
                className="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow block"
              >
                <h3 className="text-lg font-semibold text-gray-900 mb-2 hover:text-blue-600">
                  {author.name}
                </h3>
                <p className="text-sm text-gray-600">
                  {author.bookCount} {author.bookCount === 1 ? 'book' : 'books'}
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
                d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
              />
            </svg>
            <h3 className="mt-4 text-lg font-medium text-gray-900">No authors found</h3>
            <p className="mt-2 text-gray-500">
              Add some audiobooks to see authors here
            </p>
          </div>
        )}
      </main>
    </div>
  );
}
