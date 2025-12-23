import Link from 'next/link';
import Image from 'next/image';
import { PrismaClient } from '@prisma/client';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';

const prisma = new PrismaClient();

async function getMostRecentBook(userId: string) {
  try {
    const progress = await prisma.userProgress.findFirst({
      where: {
        userId,
        positionSeconds: {
          gt: 0,
        },
        completed: false,
      },
      orderBy: {
        lastPlayed: 'desc',
      },
      include: {
        book: {
          include: {
            authors: {
              include: {
                author: true,
              },
            },
          },
        },
      },
    });

    if (!progress) return null;

    const totalSeconds = progress.book.runtimeMinutes ? progress.book.runtimeMinutes * 60 : 0;
    const percentage =
      totalSeconds > 0 ? Math.round((progress.positionSeconds / totalSeconds) * 100) : 0;

    return {
      id: progress.book.id,
      title: progress.book.title,
      coverUrl: progress.book.coverUrl,
      authors: progress.book.authors.map((ba) => ba.author.name),
      percentage,
    };
  } catch (error) {
    console.error('Error fetching most recent book:', error);
    return null;
  }
}

export default async function ContinueListeningButton() {
  const session = await getServerSession(authOptions);

  if (!session?.user?.id) {
    return null;
  }

  const book = await getMostRecentBook(session.user.id);

  if (!book) {
    return null;
  }

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-6">
      <Link
        href={`/books/${book.id}/play`}
        className="block bg-gradient-to-r from-blue-600 to-blue-700 dark:from-blue-700 dark:to-blue-800 hover:from-blue-700 hover:to-blue-800 dark:hover:from-blue-800 dark:hover:to-blue-900 rounded-xl shadow-lg hover:shadow-xl transition-all duration-200 overflow-hidden group"
      >
        <div className="flex items-center p-6 gap-6">
          {/* Book Cover */}
          <div className="flex-shrink-0">
            <div className="relative w-20 h-28 rounded-lg overflow-hidden shadow-md">
              {book.coverUrl ? (
                <Image
                  src={`/api/images/${book.coverUrl}`}
                  alt={`Cover of ${book.title}`}
                  fill
                  className="object-cover group-hover:scale-105 transition-transform duration-200"
                />
              ) : (
                <div className="w-full h-full bg-gray-300 dark:bg-gray-600 flex items-center justify-center">
                  <svg
                    className="w-8 h-8 text-gray-400"
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
          </div>

          {/* Book Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-2">
              <svg
                className="w-5 h-5 text-white flex-shrink-0"
                fill="currentColor"
                viewBox="0 0 20 20"
              >
                <path
                  fillRule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                  clipRule="evenodd"
                />
              </svg>
              <span className="text-sm font-medium text-blue-100 uppercase tracking-wide">
                Continue Listening
              </span>
            </div>
            <h3 className="text-xl font-bold text-white mb-1 truncate group-hover:text-blue-50 transition-colors">
              {book.title}
            </h3>
            {book.authors.length > 0 && (
              <p className="text-sm text-blue-100 mb-3 truncate">{book.authors.join(', ')}</p>
            )}

            {/* Progress Bar */}
            <div className="flex items-center gap-3">
              <div className="flex-1 bg-blue-900/50 rounded-full h-2">
                <div
                  className="bg-white rounded-full h-2 transition-all"
                  style={{ width: `${book.percentage}%` }}
                />
              </div>
              <span className="text-sm font-semibold text-white">{book.percentage}%</span>
            </div>
          </div>

          {/* Play Icon */}
          <div className="flex-shrink-0">
            <div className="w-14 h-14 bg-white rounded-full flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform">
              <svg className="w-7 h-7 text-blue-600 ml-1" fill="currentColor" viewBox="0 0 20 20">
                <path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
              </svg>
            </div>
          </div>
        </div>
      </Link>
    </div>
  );
}
