import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Book } from '@/lib/types';
import BookGrid from '@/components/BookGrid';
import BackButton from '@/components/BackButton';
import CategoryCard, { CategoryCardCategory } from '@/components/CategoryCard';
import Pagination from '@/components/Pagination';
import { getCategoryTreeNode } from '@/lib/queries/browse-entities';
import { getEntityBooksPage } from '@/lib/queries/entity-books';

interface CategoryWithBooks {
  id: string;
  name: string;
  level: number;
  /** Root-to-immediate-parent, for the breadcrumb. Empty at a root. */
  ancestors: Array<{ id: string; name: string }>;
  /** Immediate children with visible books, to drill into. */
  subcategories: CategoryCardCategory[];
  /** Distinct visible books here or anywhere below. */
  totalBookCount: number;
  books: Book[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

async function getCategory(id: string, page?: string): Promise<CategoryWithBooks | null> {
  try {
    const pageNum = parseInt(page || '1');
    const limit = 20;
    const skip = (pageNum - 1) * limit;

    // Shared with /api/categories/[id] — the hierarchy and the book page are
    // resolved the same way for both surfaces.
    const [node, { books, total }] = await Promise.all([
      getCategoryTreeNode(id),
      getEntityBooksPage('category', id, { skip, limit }),
    ]);

    if (!node) {
      return null;
    }

    return {
      id: node.id,
      name: node.name,
      level: node.level,
      ancestors: node.ancestors,
      subcategories: node.children.map((child) => ({
        id: child.id,
        name: child.name,
        bookCount: child.bookCount,
        totalBookCount: child.totalBookCount,
        hasChildren: child.children.length > 0,
      })),
      totalBookCount: node.totalBookCount,
      books,
      pagination: {
        page: pageNum,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    };
  } catch (error) {
    console.error('Error fetching category:', error);
    return null;
  }
}

export default async function CategoryPage(props: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const params = await props.params;
  const sp = await props.searchParams;
  const category = await getCategory(params.id, sp.page);

  if (!category) {
    notFound();
  }

  const { pagination, subcategories, totalBookCount } = category;
  // A container category holds books only in its children; saying "0 books" up top
  // while a subcategory strip advertises hundreds would read as broken.
  const directLabel = `${pagination.total} ${pagination.total === 1 ? 'book' : 'books'}`;
  const headerCount =
    totalBookCount > pagination.total
      ? `${totalBookCount} ${totalBookCount === 1 ? 'book' : 'books'} in total · ${directLabel} tagged directly`
      : directLabel;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back Navigation */}
        <BackButton />

        {/* Category Header */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-8 mb-8">
          {/* Breadcrumb — each ancestor is navigable, so you can climb back up the
              ladder without relying on browser history. */}
          {category.ancestors.length > 0 && (
            <nav aria-label="Category breadcrumb" className="mb-2">
              <ol className="flex flex-wrap items-center gap-x-2 text-sm text-gray-600 dark:text-gray-400">
                <li>
                  <Link
                    href="/browse/categories"
                    className="hover:text-blue-600 dark:hover:text-blue-400"
                  >
                    Categories
                  </Link>
                </li>
                {category.ancestors.map((ancestor) => (
                  <li key={ancestor.id} className="flex items-center gap-x-2">
                    <span aria-hidden="true" className="text-gray-400 dark:text-gray-600">
                      ›
                    </span>
                    <Link
                      href={`/categories/${ancestor.id}`}
                      className="hover:text-blue-600 dark:hover:text-blue-400"
                    >
                      {ancestor.name}
                    </Link>
                  </li>
                ))}
              </ol>
            </nav>
          )}

          <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-2">{category.name}</h1>

          <div className="text-gray-600 dark:text-gray-400 text-lg">{headerCount}</div>
        </div>

        {/* Subcategories — the drill-down. Rendered above the books because at a
            container category the children are the only thing to act on. */}
        {subcategories.length > 0 && (
          <div className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 dark:text-white mb-4">
              Subcategories
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {subcategories.map((subcategory) => (
                <CategoryCard key={subcategory.id} category={subcategory} />
              ))}
            </div>
          </div>
        )}

        {/* Books tagged with this category directly. Suppressed entirely at a pure
            container, where an empty grid would just be noise under the children. */}
        {(pagination.total > 0 || subcategories.length === 0) && (
          <div className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 dark:text-white mb-4">
              Books in {category.name}
            </h2>
            {category.books.length > 0 ? (
              <>
                <BookGrid books={category.books} />
                <Pagination
                  currentPage={pagination.page}
                  totalPages={pagination.pages}
                  total={pagination.total}
                  itemName="books"
                />
              </>
            ) : (
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-8 text-center text-gray-500 dark:text-gray-400">
                No books found in this category
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
