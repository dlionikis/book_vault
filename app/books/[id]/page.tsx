import Image from 'next/image';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Book } from '@/lib/types';
import BackButton from '@/components/BackButton';
import AddToLibraryButton from '@/components/AddToLibraryButton';
import { PrismaClient } from '@prisma/client';
import { getCoverUrl, getAudioUrl } from '@/lib/media';

const prisma = new PrismaClient();

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
      metadata: book.metadata as any,
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
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <BackButton />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg overflow-hidden">
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
                <div className="aspect-[2/3] w-full max-h-[600px] bg-gray-200 dark:bg-gray-700 flex items-center justify-center text-gray-400 dark:text-gray-500">
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
            </div>

            {/* Book Details */}
            <div className="p-8 md:flex-1">
              {/* Title */}
              <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-4">
                {book.title}
              </h1>

              {/* Series */}
              {book.series.length > 0 && (
                <div className="mb-4">
                  {book.series.map((s, idx) => (
                    <Link
                      key={idx}
                      href={`/series/${s.id}`}
                      className="block text-lg text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 font-medium hover:underline"
                    >
                      {s.title}
                      {s.sequence && ` #${s.sequence}`}
                    </Link>
                  ))}
                </div>
              )}

              {/* Authors */}
              {book.authors.length > 0 && (
                <div className="mb-4">
                  <span className="text-gray-600 dark:text-gray-400">By </span>
                  <span className="text-lg font-medium">
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
                <div className="mb-6">
                  <span className="text-gray-600 dark:text-gray-400">Narrated by </span>
                  <span>
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

              {/* Add to Library Button */}
              <div className="mb-6">
                <AddToLibraryButton
                  bookId={book.id}
                  seriesId={book.series[0]?.id}
                  showSeriesOption={book.series.length > 0}
                  size="large"
                />
              </div>

              {/* Metadata Grid */}
              <div className="grid grid-cols-2 gap-4 mb-6 pb-6 border-b dark:border-gray-700">
                {book.runtimeMinutes && (
                  <div>
                    <p className="text-sm text-gray-600">Length</p>
                    <p className="font-medium text-gray-900">
                      {formatRuntime(book.runtimeMinutes)}
                    </p>
                  </div>
                )}
                {book.releaseDate && (
                  <div>
                    <p className="text-sm text-gray-600">Release Date</p>
                    <p className="font-medium text-gray-900">{formatDate(book.releaseDate)}</p>
                  </div>
                )}
                {book.publisher && (
                  <div>
                    <p className="text-sm text-gray-600">Publisher</p>
                    <p className="font-medium text-gray-900">{book.publisher}</p>
                  </div>
                )}
                {book.asin && (
                  <div>
                    <p className="text-sm text-gray-600">ASIN</p>
                    <p className="font-medium text-gray-900">{book.asin}</p>
                  </div>
                )}
              </div>

              {/* Categories */}
              {book.categories && book.categories.length > 0 && (
                <div className="mb-6">
                  <h3 className="text-sm font-semibold text-gray-600 dark:text-gray-400 uppercase mb-2">
                    Categories
                  </h3>
                  <div className="flex flex-wrap gap-2">
                    {book.categories.map((cat) => (
                      <Link
                        key={cat.id}
                        href={`/categories/${cat.id}`}
                        className="px-3 py-1 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 text-sm rounded-full hover:bg-blue-100 dark:hover:bg-blue-900 hover:text-blue-700 dark:hover:text-blue-300 transition-colors"
                      >
                        {cat.name}
                      </Link>
                    ))}
                  </div>
                </div>
              )}

              {/* Publisher Summary */}
              {book.publisherSummary && (
                <div className="mb-6">
                  <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2">
                    About this audiobook
                  </h3>
                  <div
                    className="text-gray-700 dark:text-gray-300 leading-relaxed prose prose-sm max-w-none dark:prose-invert"
                    dangerouslySetInnerHTML={{ __html: book.publisherSummary }}
                  />
                </div>
              )}

              {/* Customer Reviews */}
              {book.metadata?.customer_reviews && book.metadata.customer_reviews.length > 0 && (
                <div className="mt-8">
                  <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
                    Customer Reviews ({book.metadata.customer_reviews.length})
                  </h3>
                  <div className="space-y-6">
                    {book.metadata.customer_reviews.map((review) => (
                      <div
                        key={review.id}
                        className="border-b border-gray-200 dark:border-gray-700 pb-6 last:border-b-0"
                      >
                        {/* Review Header */}
                        <div className="flex items-start justify-between mb-2">
                          <div>
                            <h4 className="font-semibold text-gray-900 dark:text-white">
                              {review.title}
                            </h4>
                            <div className="flex items-center gap-2 mt-1">
                              <span className="text-sm text-gray-600 dark:text-gray-400">
                                {review.author_name}
                              </span>
                              <span className="text-gray-400 dark:text-gray-600">•</span>
                              <span className="text-sm text-gray-500 dark:text-gray-500">
                                {new Date(review.submission_date).toLocaleDateString('en-US', {
                                  year: 'numeric',
                                  month: 'long',
                                  day: 'numeric',
                                })}
                              </span>
                            </div>
                          </div>
                        </div>

                        {/* Rating Stars */}
                        <div className="flex gap-4 mb-3 text-sm">
                          <div className="flex items-center gap-1">
                            <span className="text-gray-600 dark:text-gray-400">Overall:</span>
                            <div className="flex">
                              {[...Array(5)].map((_, i) => (
                                <svg
                                  key={i}
                                  className={`w-4 h-4 ${
                                    i < review.ratings.overall_rating
                                      ? 'text-yellow-400 fill-current'
                                      : 'text-gray-300'
                                  }`}
                                  viewBox="0 0 20 20"
                                >
                                  <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                                </svg>
                              ))}
                              <span className="ml-1 text-gray-700 dark:text-gray-300">
                                {review.ratings.overall_rating}
                              </span>
                            </div>
                          </div>
                          <div className="flex items-center gap-1">
                            <span className="text-gray-600 dark:text-gray-400">Story:</span>
                            <div className="flex">
                              {[...Array(5)].map((_, i) => (
                                <svg
                                  key={i}
                                  className={`w-4 h-4 ${
                                    i < review.ratings.story_rating
                                      ? 'text-yellow-400 fill-current'
                                      : 'text-gray-300'
                                  }`}
                                  viewBox="0 0 20 20"
                                >
                                  <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                                </svg>
                              ))}
                              <span className="ml-1 text-gray-700 dark:text-gray-300">
                                {review.ratings.story_rating}
                              </span>
                            </div>
                          </div>
                          <div className="flex items-center gap-1">
                            <span className="text-gray-600 dark:text-gray-400">Performance:</span>
                            <div className="flex">
                              {[...Array(5)].map((_, i) => (
                                <svg
                                  key={i}
                                  className={`w-4 h-4 ${
                                    i < review.ratings.performance_rating
                                      ? 'text-yellow-400 fill-current'
                                      : 'text-gray-300'
                                  }`}
                                  viewBox="0 0 20 20"
                                >
                                  <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                                </svg>
                              ))}
                              <span className="ml-1 text-gray-700 dark:text-gray-300">
                                {review.ratings.performance_rating}
                              </span>
                            </div>
                          </div>
                        </div>

                        {/* Review Body */}
                        <p className="text-gray-700 dark:text-gray-300 leading-relaxed">
                          {review.body}
                        </p>

                        {/* Helpful Votes */}
                        {(review.review_content_scores.num_helpful_votes > 0 ||
                          review.review_content_scores.num_unhelpful_votes > 0) && (
                          <div className="mt-3 text-sm text-gray-500 dark:text-gray-400">
                            {review.review_content_scores.num_helpful_votes} people found this
                            helpful
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </main>

      {/* Play Button - Fixed at bottom */}
      {book.audioUrl && (
        <div className="fixed bottom-0 left-0 right-0 bg-white dark:bg-gray-800 border-t dark:border-gray-700 shadow-lg z-50">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                <div className="hidden sm:block">
                  {book.coverUrl && (
                    <div className="relative w-12 h-12">
                      <Image
                        src={book.coverUrl}
                        alt={book.title}
                        fill
                        className="object-cover rounded"
                      />
                    </div>
                  )}
                </div>
                <div>
                  <div className="font-medium text-gray-900 dark:text-white">{book.title}</div>
                  <div className="text-sm text-gray-600 dark:text-gray-400">
                    {book.authors.map((a) => a.name).join(', ')}
                  </div>
                </div>
              </div>
              <Link
                href={`/books/${book.id}/play`}
                className="flex items-center gap-2 bg-blue-600 text-white px-6 py-3 rounded-full hover:bg-blue-700 transition-colors font-medium"
              >
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M8 5v14l11-7z" />
                </svg>
                Play Book
              </Link>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
