import Link from 'next/link';
import Image from 'next/image';
import { PrismaClient } from '@prisma/client';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';

const prisma = new PrismaClient();

interface InProgressBook {
  id: string;
  title: string;
  coverUrl: string | null;
  runtimeMinutes: number | null;
  authors: string[];
  positionSeconds: number;
  lastPlayed: Date;
}

async function getInProgressBooks(userId: string): Promise<InProgressBook[]> {
  try {
    const progressRecords = await prisma.userProgress.findMany({
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
      take: 10,
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

    return progressRecords.map((progress) => ({
      id: progress.book.id,
      title: progress.book.title,
      coverUrl: progress.book.coverUrl,
      runtimeMinutes: progress.book.runtimeMinutes,
      authors: progress.book.authors.map((ba) => ba.author.name),
      positionSeconds: progress.positionSeconds,
      lastPlayed: progress.lastPlayed,
    }));
  } catch (error) {
    console.error('Error fetching in-progress books:', error);
    return [];
  }
}

function getProgressPercentage(positionSeconds: number, runtimeMinutes: number | null): number {
  if (!runtimeMinutes) return 0;
  const totalSeconds = runtimeMinutes * 60;
  return Math.min(100, Math.round((positionSeconds / totalSeconds) * 100));
}

function formatLastPlayed(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 60) {
    return diffMins === 1 ? '1 minute ago' : `${diffMins} minutes ago`;
  }
  if (diffHours < 24) {
    return diffHours === 1 ? '1 hour ago' : `${diffHours} hours ago`;
  }
  if (diffDays < 7) {
    return diffDays === 1 ? '1 day ago' : `${diffDays} days ago`;
  }
  return date.toLocaleDateString();
}

export default async function ContinueListening() {
  const session = await getServerSession(authOptions);

  if (!session?.user?.id) {
    return null;
  }

  const books = await getInProgressBooks(session.user.id);

  if (books.length === 0) {
    return null;
  }

  return (
    <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-12">
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white flex items-center gap-2">
          <svg
            className="w-6 h-6 text-blue-600 dark:text-blue-400"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fillRule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
              clipRule="evenodd"
            />
          </svg>
          Continue Listening
        </h2>
        <Link
          href="/library"
          className="text-sm text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 font-medium"
        >
          View Library →
        </Link>
      </div>

      <div className="relative">
        <div className="flex gap-4 overflow-x-auto pb-4 snap-x snap-mandatory scrollbar-thin scrollbar-thumb-gray-300 dark:scrollbar-thumb-gray-700 scrollbar-track-transparent">
          {books.map((book) => {
            const percentage = getProgressPercentage(book.positionSeconds, book.runtimeMinutes);
            return (
              <Link
                key={book.id}
                href={`/books/${book.id}/play`}
                className="flex-none w-48 snap-start group"
              >
                <div className="bg-white dark:bg-gray-800 rounded-lg shadow hover:shadow-lg transition-shadow overflow-hidden">
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
                          className="w-12 h-12"
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

                    {/* Progress Overlay */}
                    <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent p-2">
                      <div className="text-white text-xs font-medium mb-1">
                        {percentage}% Complete
                      </div>
                      <div className="w-full bg-white/30 rounded-full h-1">
                        <div
                          className="bg-blue-500 h-1 rounded-full transition-all"
                          style={{ width: `${percentage}%` }}
                        />
                      </div>
                    </div>
                  </div>

                  {/* Book Info */}
                  <div className="p-3">
                    <h3 className="font-semibold text-gray-900 dark:text-white text-sm mb-1 line-clamp-2 group-hover:text-blue-600 dark:group-hover:text-blue-400">
                      {book.title}
                    </h3>
                    {book.authors.length > 0 && (
                      <p className="text-xs text-gray-600 dark:text-gray-400 mb-1 line-clamp-1">
                        {book.authors.join(', ')}
                      </p>
                    )}
                    <p className="text-xs text-gray-500 dark:text-gray-500">
                      {formatLastPlayed(book.lastPlayed)}
                    </p>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      </div>
    </section>
  );
}
