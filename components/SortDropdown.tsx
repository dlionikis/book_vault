'use client';

import { useRouter, useSearchParams } from 'next/navigation';

export default function SortDropdown() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const currentSort = searchParams.get('sort') || 'title';

  const handleSortChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const sort = e.target.value;
    const params = new URLSearchParams(searchParams.toString());
    params.set('sort', sort);
    router.push(`/?${params.toString()}`);
  };

  return (
    <div className="flex items-center gap-2">
      <label htmlFor="sort" className="text-sm font-medium text-gray-700 dark:text-gray-300">
        Sort by:
      </label>
      <select
        id="sort"
        value={currentSort}
        onChange={handleSortChange}
        className="block rounded-md border border-gray-300 dark:border-gray-700 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm py-2 px-3 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
      >
        <option value="title">Title</option>
        <option value="author">Author</option>
        <option value="narrator">Narrator</option>
        <option value="series">Series</option>
      </select>
    </div>
  );
}
