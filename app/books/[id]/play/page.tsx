import Image from 'next/image';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Book } from '@/lib/types';
import { prisma } from '@/lib/db';
import { getCoverUrl, getAudioUrl } from '@/lib/media';
import PlaybackClient from '@/components/PlaybackClient';

async function getBook(id: string): Promise<Book | null> {
  try {
    const book = await prisma.book.findUnique({
      where: { id },
      include: {
        authors: {
          include: {
            author: true,
          },
          orderBy: {
            author: {
              name: 'asc',
            },
          },
        },
        narrators: {
          include: {
            narrator: true,
          },
          orderBy: {
            narrator: {
              name: 'asc',
            },
          },
        },
        series: {
          include: {
            series: true,
          },
          orderBy: {
            series: {
              title: 'asc',
            },
          },
        },
        categories: {
          include: {
            category: true,
          },
        },
      },
    });

    if (!book) {
      return null;
    }

    return {
      id: book.id,
      asin: book.asin,
      title: book.title,
      publisherSummary: book.publisherSummary,
      runtimeMinutes: book.runtimeMinutes,
      releaseDate: book.releaseDate,
      publisher: book.publisher,
      coverUrl: getCoverUrl(book.coverUrl),
      audioUrl: getAudioUrl(book.audioUrl),
      authors: book.authors.map((ba) => ba.author),
      narrators: book.narrators.map((bn) => bn.narrator),
      series: book.series.map((bs) => ({
        id: bs.series.id,
        title: bs.series.title,
        asin: bs.series.asin,
        sequence: bs.sequence,
      })),
      categories: book.categories.map((bc) => bc.category),
      createdAt: book.createdAt.toISOString(),
    };
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

export default async function PlayPage({ params }: { params: { id: string } }) {
  const book = await getBook(params.id);

  if (!book) {
    notFound();
  }

  if (!book.audioUrl) {
    return (
      <div className="min-h-screen bg-gray-50 dark:bg-gray-950 flex items-center justify-center">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">
            No Audio Available
          </h1>
          <p className="text-gray-600 dark:text-gray-400 mb-6">
            This book does not have an audio file.
          </p>
          <Link
            href={`/books/${book.id}`}
            className="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 hover:underline"
          >
            ← Back to book details
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950 pb-32">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center gap-4">
            <Link
              href={`/books/${book.id}`}
              className="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 font-medium flex items-center gap-2"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M15 19l-7-7 7-7"
                />
              </svg>
              Back to Details
            </Link>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Book Info Sidebar */}
          <div className="lg:col-span-1">
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 sticky top-24">
              {/* Cover Image */}
              {book.coverUrl ? (
                <div className="relative aspect-[2/3] w-full mb-4">
                  <Image
                    src={book.coverUrl}
                    alt={`Cover of ${book.title}`}
                    fill
                    className="object-contain rounded-lg"
                    priority
                  />
                </div>
              ) : (
                <div className="aspect-[2/3] w-full mb-4 bg-gray-200 dark:bg-gray-700 flex items-center justify-center text-gray-400 dark:text-gray-500 rounded-lg">
                  <svg className="w-24 h-24" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
                    />
                  </svg>
                </div>
              )}

              {/* Title */}
              <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                {book.title}
              </h1>

              {/* Series */}
              {book.series.length > 0 && (
                <div className="mb-3">
                  {book.series.map((s, idx) => (
                    <Link
                      key={idx}
                      href={`/series/${s.id}`}
                      className="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 text-sm hover:underline"
                    >
                      {s.title}
                      {s.sequence && ` #${s.sequence}`}
                    </Link>
                  ))}
                </div>
              )}

              {/* Authors */}
              {book.authors.length > 0 && (
                <div className="mb-3">
                  <span className="text-sm text-gray-600 dark:text-gray-400">By </span>
                  <span className="text-sm">
                    {book.authors.map((a, idx) => (
                      <span key={a.id}>
                        {idx > 0 && ', '}
                        <Link
                          href={`/authors/${a.id}`}
                          className="text-gray-900 dark:text-gray-200 hover:text-blue-600 dark:hover:text-blue-400 hover:underline"
                        >
                          {a.name}
                        </Link>
                      </span>
                    ))}
                  </span>
                </div>
              )}

              {/* Narrators */}
              {book.narrators.length > 0 && (
                <div className="mb-4">
                  <span className="text-sm text-gray-600 dark:text-gray-400">Narrated by </span>
                  <span className="text-sm">
                    {book.narrators.map((n, idx) => (
                      <span key={n.id}>
                        {idx > 0 && ', '}
                        <Link
                          href={`/narrators/${n.id}`}
                          className="text-gray-900 dark:text-gray-200 hover:text-blue-600 dark:hover:text-blue-400 hover:underline"
                        >
                          {n.name}
                        </Link>
                      </span>
                    ))}
                  </span>
                </div>
              )}

              {/* Runtime */}
              {book.runtimeMinutes && (
                <div className="text-sm text-gray-600 dark:text-gray-400 mb-2">
                  <span className="font-medium">Length:</span> {formatRuntime(book.runtimeMinutes)}
                </div>
              )}
            </div>
          </div>

          {/* Playback Area */}
          <div className="lg:col-span-2">
            <PlaybackClient
              audioUrl={book.audioUrl}
              title={book.title}
              author={book.authors.map((a) => a.name).join(', ')}
              bookId={book.id}
              coverUrl={book.coverUrl}
            />
          </div>
        </div>
      </main>
    </div>
  );
}
