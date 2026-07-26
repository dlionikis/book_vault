import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { redirect } from 'next/navigation';
import { prisma } from '@/lib/db';
import Link from 'next/link';
import BackButton from '@/components/BackButton';
import AddToLibraryButton from '@/components/AddToLibraryButton';
import ProgressStatus from '@/components/ProgressStatus';
import BookGrid from '@/components/BookGrid';
import SeriesModeSection from '@/components/SeriesModeSection';
import { LIBRARY_VIEW_MODE_KEY } from '@/components/ViewModeToggle';
import { BOOK_INCLUDE, transformLibraryBook } from '@/lib/book-transformer';

interface LibraryBookProgress {
  positionSeconds: number;
  completed: boolean;
}

async function getLibraryBooks(userId: string) {
  try {
    // Get user's library
    const library = await prisma.userList.findFirst({
      where: {
        userId,
        name: 'My Library',
      },
    });

    if (!library) {
      return { books: [], progressByBookId: new Map() };
    }

    // Get books in library with full details
    const libraryBooks = await prisma.userListBook.findMany({
      where: {
        listId: library.id,
      },
      include: {
        book: {
          include: BOOK_INCLUDE,
        },
      },
      orderBy: {
        addedAt: 'desc',
      },
    });

    // Get progress for all books
    const bookIds = libraryBooks.map((lb) => lb.book.id);
    const progressRecords = await prisma.userProgress.findMany({
      where: {
        userId,
        bookId: {
          in: bookIds,
        },
      },
    });

    const progressByBookId = new Map(
      progressRecords.map((p) => [
        p.bookId,
        { positionSeconds: p.positionSeconds, completed: p.completed },
      ])
    );

    const books = await Promise.all(libraryBooks.map(transformLibraryBook));

    return { books, progressByBookId };
  } catch (error) {
    console.error('Error fetching library:', error);
    return { books: [], progressByBookId: new Map() };
  }
}

export default async function LibraryPage() {
  const session = await getServerSession(authOptions);

  if (!session?.user?.id) {
    redirect('/auth/login');
  }

  const { books, progressByBookId } = await getLibraryBooks(session.user.id);

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
          <SeriesModeSection
            storageKey={LIBRARY_VIEW_MODE_KEY}
            endpoint="/api/browse/library-series-view"
            booksHeading={
              <p className="text-gray-600 dark:text-gray-400">
                {books.length} {books.length === 1 ? 'book' : 'books'} in your library
              </p>
            }
            seriesHeadingTitle=""
            seriesCountTemplate="{count} series in your library"
            seriesHeadingAs="p"
            seriesHeadingClassName="text-gray-600 dark:text-gray-400"
          >
            <BookGrid
              books={books}
              renderFooter={(book) => {
                const progress = progressByBookId.get(book.id);
                return (
                  <>
                    <ProgressStatus
                      bookId={book.id}
                      initialProgress={{
                        positionSeconds: progress?.positionSeconds ?? 0,
                        completed: progress?.completed ?? false,
                        totalSeconds: book.runtimeMinutes ? book.runtimeMinutes * 60 : undefined,
                      }}
                    />
                    <div className="mt-3">
                      <AddToLibraryButton
                        bookId={book.id}
                        seriesId={book.series[0]?.id}
                        showSeriesOption={book.series.length > 0}
                        size="small"
                      />
                    </div>
                  </>
                );
              }}
            />
          </SeriesModeSection>
        )}
      </main>
    </div>
  );
}
