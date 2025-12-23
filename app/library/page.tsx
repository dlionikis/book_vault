import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { redirect } from 'next/navigation';
import { PrismaClient } from '@prisma/client';
import Image from 'next/image';
import Link from 'next/link';
import BackButton from '@/components/BackButton';
import AddToLibraryButton from '@/components/AddToLibraryButton';

const prisma = new PrismaClient();

interface LibraryBook {
  id: string;
  asin: string;
  title: string;
  coverUrl: string | null;
  runtimeMinutes: number | null;
  authors: Array<{
    id: string;
    name: string;
  }>;
  narrators: Array<{
    id: string;
    name: string;
  }>;
  series: Array<{
    id: string;
    title: string;
    sequence: string | null;
  }>;
  addedAt: string;
}

async function getLibraryBooks(userId: string): Promise<LibraryBook[]> {
  try {
    // Get user's library
    const library = await prisma.userList.findFirst({
      where: {
        userId,
        name: 'My Library',
      },
    });

    if (!library) {
      return [];
    }

    // Get books in library with full details
    const libraryBooks = await prisma.userListBook.findMany({
      where: {
        listId: library.id,
      },
      include: {
        book: {
          include: {
            authors: {
              include: {
                author: true,
              },
            },
            narrators: {
              include: {
                narrator: true,
              },
            },
            series: {
              include: {
                series: true,
              },
            },
          },
        },
      },
      orderBy: {
        addedAt: 'desc',
      },
    });

    return libraryBooks.map((lb) => ({
      id: lb.book.id,
      asin: lb.book.asin,
      title: lb.book.title,
      coverUrl: lb.book.coverUrl,
      runtimeMinutes: lb.book.runtimeMinutes,
      authors: lb.book.authors.map((a) => ({
        id: a.author.id,
        name: a.author.name,
      })),
      narrators: lb.book.narrators.map((n) => ({
        id: n.narrator.id,
        name: n.narrator.name,
      })),
      series: lb.book.series.map((s) => ({
        id: s.series.id,
        title: s.series.title,
        sequence: s.sequence,
      })),
      addedAt: lb.addedAt.toISOString(),
    }));
  } catch (error) {
    console.error('Error fetching library:', error);
    return [];
  }
}

function formatRuntime(minutes?: number | null) {
  if (!minutes) return null;
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${hours}h ${mins}m`;
}

export default async function LibraryPage() {
  const session = await getServerSession(authOptions);

  if (!session?.user?.id) {
    redirect('/auth/login');
  }

  const books = await getLibraryBooks(session.user.id);

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <BackButton />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 dark:text-white">My Library</h1>
          <p className="mt-2 text-gray-600 dark:text-gray-400">
            {books.length} {books.length === 1 ? 'book' : 'books'} in your library
          </p>
        </div>

        {books.length === 0 ? (
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-12 text-center">
            <svg
              className="mx-auto h-24 w-24 text-gray-400 dark:text-gray-600 mb-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
              />
            </svg>
            <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-2">
              Your library is empty
            </h3>
            <p className="text-gray-600 dark:text-gray-400 mb-6">
              Start adding books to your library to keep track of what you want to listen to.
            </p>
            <Link
              href="/"
              className="inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-md font-medium transition-colors"
            >
              Browse Books
            </Link>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-6">
            {books.map((book) => (
              <div
                key={book.id}
                className="bg-white dark:bg-gray-800 rounded-lg shadow hover:shadow-lg transition-shadow overflow-hidden group"
              >
                <Link href={`/books/${book.id}`} className="block">
                  {/* Cover Image */}
                  <div className="relative aspect-[2/3] w-full bg-gray-200 dark:bg-gray-700">
                    {book.coverUrl ? (
                      <Image
                        src={`/api/images/${book.coverUrl}`}
                        alt={`Cover of ${book.title}`}
                        fill
                        className="object-cover group-hover:scale-105 transition-transform duration-200"
                      />
                    ) : (
                      <div className="flex items-center justify-center h-full text-gray-400 dark:text-gray-500">
                        <svg
                          className="w-16 h-16"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
                          />
                        </svg>
                      </div>
                    )}
                  </div>
                </Link>

                {/* Book Info */}
                <div className="p-4">
                  <Link href={`/books/${book.id}`}>
                    <h3 className="font-semibold text-gray-900 dark:text-white mb-1 line-clamp-2 hover:text-blue-600 dark:hover:text-blue-400">
                      {book.title}
                    </h3>
                  </Link>

                  {/* Series */}
                  {book.series.length > 0 && (
                    <p className="text-sm text-blue-600 dark:text-blue-400 mb-1 line-clamp-1">
                      {book.series[0].title}
                      {book.series[0].sequence && ` #${book.series[0].sequence}`}
                    </p>
                  )}

                  {/* Authors */}
                  {book.authors.length > 0 && (
                    <p className="text-sm text-gray-600 dark:text-gray-400 mb-1 line-clamp-1">
                      {book.authors.map((a) => a.name).join(', ')}
                    </p>
                  )}

                  {/* Runtime */}
                  {book.runtimeMinutes && (
                    <p className="text-xs text-gray-500 dark:text-gray-500 mb-3">
                      {formatRuntime(book.runtimeMinutes)}
                    </p>
                  )}

                  {/* Remove Button */}
                  <AddToLibraryButton
                    bookId={book.id}
                    seriesId={book.series[0]?.id}
                    showSeriesOption={book.series.length > 0}
                    size="small"
                  />
                </div>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
