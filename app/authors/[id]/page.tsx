import { notFound } from 'next/navigation';
import { Book, Author } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import Pagination from '@/components/Pagination';
import { prisma } from '@/lib/db';
import { BOOK_INCLUDE, transformBook } from '@/lib/book-transformer';

interface AuthorWithBooks extends Author {
  books: Book[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

async function getAuthor(id: string, page?: string): Promise<AuthorWithBooks | null> {
  try {
    const pageNum = parseInt(page || '1');
    const limit = 20;
    const skip = (pageNum - 1) * limit;

    const author = await prisma.author.findUnique({
      where: { id },
    });

    if (!author) {
      return null;
    }

    const [bookAuthorEntries, total] = await Promise.all([
      prisma.bookAuthor.findMany({
        where: { authorId: id },
        skip,
        take: limit,
        include: {
          book: {
            include: BOOK_INCLUDE,
          },
        },
        orderBy: {
          book: {
            title: 'asc',
          },
        },
      }),
      prisma.bookAuthor.count({
        where: { authorId: id },
      }),
    ]);

    // Transform books using centralized transformer
    const books = await Promise.all(bookAuthorEntries.map((entry) => transformBook(entry.book)));

    return {
      ...author,
      books,
      pagination: {
        page: pageNum,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    };
  } catch (error) {
    console.error('Error fetching author:', error);
    return null;
  }
}

export default async function AuthorPage(props: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const params = await props.params;
  const sp = await props.searchParams;
  const author = await getAuthor(params.id, sp.page);

  if (!author) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Author Header */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-8 mb-8">
          <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-2">{author.name}</h1>

          <div className="text-gray-600 dark:text-gray-400 text-lg">
            {author.books.length} {author.books.length === 1 ? 'book' : 'books'}
          </div>
        </div>

        {/* Books by Author */}
        <div className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 dark:text-white mb-4">
            Books by {author.name}
          </h2>
          {author.books.length > 0 ? (
            <>
              <BookGrid books={author.books} />
              <Pagination
                currentPage={author.pagination.page}
                totalPages={author.pagination.pages}
                total={author.pagination.total}
                itemName="books"
              />
            </>
          ) : (
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-8 text-center text-gray-500 dark:text-gray-400">
              No books found for this author
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
