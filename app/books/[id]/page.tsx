import Image from 'next/image';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Book } from '@/lib/types';

async function getBook(id: string): Promise<Book | null> {
  try {
    const res = await fetch(`http://localhost:3000/api/books/${id}`, {
      cache: 'no-store',
    });
    
    if (!res.ok) {
      return null;
    }
    
    return res.json();
  } catch (error) {
    console.error('Error fetching book:', error);
    return null;
  }
}

function formatRuntime(minutes?: number | null) {
  if (!minutes) return null;
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${hours} hr ${mins} min`;
}

function formatDate(dateString?: string | null) {
  if (!dateString) return null;
  const date = new Date(dateString);
  return date.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
}

export default async function BookDetailPage({ params }: { params: { id: string } }) {
  const book = await getBook(params.id);

  if (!book) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <Link href="/" className="text-blue-600 hover:text-blue-800 flex items-center gap-2">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
            Back to Library
          </Link>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="bg-white rounded-lg shadow-lg overflow-hidden">
          <div className="md:flex">
            {/* Cover Image */}
            <div className="md:w-1/3 lg:w-1/4 flex-shrink-0">
              {book.coverUrl ? (
                <div className="relative aspect-[2/3] w-full max-h-[600px]">
                  <Image
                    src={book.coverUrl}
                    alt={`Cover of ${book.title}`}
                    fill
                    className="object-contain"
                    priority
                  />
                </div>
              ) : (
                <div className="aspect-[2/3] w-full max-h-[600px] bg-gray-200 flex items-center justify-center text-gray-400">
                  <svg className="w-24 h-24" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
                  </svg>
                </div>
              )}
            </div>

            {/* Book Details */}
            <div className="p-8 md:flex-1">
              {/* Title */}
              <h1 className="text-3xl font-bold text-gray-900 mb-4">{book.title}</h1>

              {/* Series */}
              {book.series.length > 0 && (
                <div className="mb-4">
                  {book.series.map((s, idx) => (
                    <p key={idx} className="text-lg text-blue-600 font-medium">
                      {s.title}
                      {s.sequence && ` #${s.sequence}`}
                    </p>
                  ))}
                </div>
              )}

              {/* Authors */}
              {book.authors.length > 0 && (
                <div className="mb-4">
                  <span className="text-gray-600">By </span>
                  <span className="text-lg font-medium text-gray-900">
                    {book.authors.map(a => a.name).join(', ')}
                  </span>
                </div>
              )}

              {/* Narrators */}
              {book.narrators.length > 0 && (
                <div className="mb-6">
                  <span className="text-gray-600">Narrated by </span>
                  <span className="text-gray-900">
                    {book.narrators.map(n => n.name).join(', ')}
                  </span>
                </div>
              )}

              {/* Metadata Grid */}
              <div className="grid grid-cols-2 gap-4 mb-6 pb-6 border-b">
                {book.runtimeMinutes && (
                  <div>
                    <p className="text-sm text-gray-600">Length</p>
                    <p className="font-medium">{formatRuntime(book.runtimeMinutes)}</p>
                  </div>
                )}
                {book.releaseDate && (
                  <div>
                    <p className="text-sm text-gray-600">Release Date</p>
                    <p className="font-medium">{formatDate(book.releaseDate)}</p>
                  </div>
                )}
                {book.publisher && (
                  <div>
                    <p className="text-sm text-gray-600">Publisher</p>
                    <p className="font-medium">{book.publisher}</p>
                  </div>
                )}
                {book.asin && (
                  <div>
                    <p className="text-sm text-gray-600">ASIN</p>
                    <p className="font-medium">{book.asin}</p>
                  </div>
                )}
              </div>

              {/* Categories */}
              {book.categories && book.categories.length > 0 && (
                <div className="mb-6">
                  <h3 className="text-sm font-semibold text-gray-600 uppercase mb-2">Categories</h3>
                  <div className="flex flex-wrap gap-2">
                    {book.categories.map((cat) => (
                      <span
                        key={cat.id}
                        className="px-3 py-1 bg-gray-100 text-gray-700 text-sm rounded-full"
                      >
                        {cat.name}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Publisher Summary */}
              {book.publisherSummary && (
                <div className="mb-6">
                  <h3 className="text-lg font-semibold text-gray-900 mb-2">About this audiobook</h3>
                  <div 
                    className="text-gray-700 leading-relaxed prose prose-sm max-w-none"
                    dangerouslySetInnerHTML={{ __html: book.publisherSummary }}
                  />
                </div>
              )}

              {/* Audio Player Placeholder */}
              {book.audioUrl && (
                <div className="mt-8 p-4 bg-gray-100 rounded-lg">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-sm font-medium text-gray-700">Audio Player</span>
                    <span className="text-xs text-gray-500">Coming soon</span>
                  </div>
                  <div className="h-12 bg-gray-200 rounded flex items-center justify-center text-gray-500">
                    <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}
