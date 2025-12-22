import { notFound } from 'next/navigation';
import { Book, Author } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';

interface AuthorWithBooks extends Author {
  books: Book[];
}

async function getAuthor(id: string): Promise<AuthorWithBooks | null> {
  try {
    const res = await fetch(`http://localhost:3000/api/authors/${id}`, {
      next: { revalidate: 0 }
    });

    if (!res.ok) {
      return null;
    }

    return res.json();
  } catch (error) {
    console.error('Error fetching author:', error);
    return null;
  }
}

export default async function AuthorPage({ params }: { params: { id: string } }) {
  const author = await getAuthor(params.id);

  if (!author) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Author Header */}
        <div className="bg-white rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">
            {author.name}
          </h1>
          
          <div className="text-gray-600 text-lg">
            {author.books.length} {author.books.length === 1 ? 'book' : 'books'}
          </div>
        </div>

        {/* Books by Author */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">
            Books by {author.name}
          </h2>
          {author.books.length > 0 ? (
            <BookGrid books={author.books} />
          ) : (
            <div className="bg-white rounded-lg shadow p-8 text-center text-gray-500">
              No books found for this author
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
