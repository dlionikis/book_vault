import Link from 'next/link';

export interface CategoryCardCategory {
  id: string;
  name: string;
  /** Books tagged with this category directly. */
  bookCount: number;
  /** Distinct visible books in this category or any descendant. */
  totalBookCount: number;
  /** Whether drilling in reveals further subcategories. */
  hasChildren: boolean;
}

/**
 * Builds the count line under a category name.
 *
 * Audible ships each book's genre as a full ladder, so most non-leaf categories
 * have no books of their own — 15 of 16 production roots have `bookCount: 0`.
 * Showing the direct count would print "0 books" on nearly every entry point, so
 * a parent advertises its subtree total and says how many ways in there are.
 * A leaf, where the two counts agree, just reads "N books".
 */
export function categoryCountLabel(category: CategoryCardCategory): string {
  const { bookCount, totalBookCount, hasChildren } = category;
  const books = `${totalBookCount} ${totalBookCount === 1 ? 'book' : 'books'}`;

  if (!hasChildren) {
    return books;
  }

  // Only worth mentioning the direct tagging when it differs from the rollup;
  // otherwise "12 books · 12 directly" is noise.
  if (bookCount > 0 && bookCount < totalBookCount) {
    return `${books} · ${bookCount} directly`;
  }

  return books;
}

/**
 * A category as a clickable card, used by the category browse grid and by the
 * subcategory strip on a category page.
 *
 * @example
 * <CategoryCard category={{ id, name: 'Fantasy', bookCount: 107, totalBookCount: 483, hasChildren: true }} />
 */
export default function CategoryCard({ category }: { category: CategoryCardCategory }) {
  return (
    <Link
      href={`/categories/${category.id}`}
      className="bg-white dark:bg-gray-800 rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow block"
    >
      <div className="flex items-start justify-between gap-2">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white hover:text-blue-600 dark:hover:text-blue-400">
          {category.name}
        </h3>
        {category.hasChildren && (
          <span aria-hidden="true" className="text-gray-400 dark:text-gray-500 shrink-0 leading-6">
            ›
          </span>
        )}
      </div>
      <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
        {categoryCountLabel(category)}
      </p>
    </Link>
  );
}
