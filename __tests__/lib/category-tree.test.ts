/**
 * Unit tests for the category tree built in lib/queries/browse-entities.ts.
 *
 * Audible ships each book's genre as a full ladder, so categories form a real
 * hierarchy that the browse UI navigates. The pieces worth pinning here are the
 * ones that are easy to get subtly wrong and invisible in a happy-path render:
 * rollups that must de-duplicate rather than sum, pruning of the ladder's
 * bookless intermediate nodes, and termination on malformed parent links.
 */

import { prisma } from '@/lib/db';
import { getCategoryTree, getCategoryTreeNode } from '@/lib/queries/browse-entities';

jest.mock('@/lib/db', () => ({
  prisma: {
    category: { findMany: jest.fn() },
    bookCategory: { findMany: jest.fn() },
  },
}));

const mockPrisma = prisma as unknown as {
  category: { findMany: jest.Mock };
  bookCategory: { findMany: jest.Mock };
};

interface Cat {
  id: string;
  name: string;
  level: number;
  parentId: string | null;
}

/**
 * @param links [categoryId, bookId] pairs, standing in for the visible rows of
 *   book_categories (the query filters hidden books out in SQL).
 */
function setup(categories: Cat[], links: Array<[string, string]>) {
  mockPrisma.category.findMany.mockResolvedValue(categories);
  mockPrisma.bookCategory.findMany.mockResolvedValue(
    links.map(([categoryId, bookId]) => ({ categoryId, bookId }))
  );
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('getCategoryTree', () => {
  it('nests descendants under their root', async () => {
    setup(
      [
        { id: 'sff', name: 'Science Fiction & Fantasy', level: 0, parentId: null },
        { id: 'fantasy', name: 'Fantasy', level: 1, parentId: 'sff' },
        { id: 'epic', name: 'Epic', level: 2, parentId: 'fantasy' },
      ],
      [['epic', 'b1']]
    );

    const tree = await getCategoryTree();

    expect(tree).toHaveLength(1);
    expect(tree[0].name).toBe('Science Fiction & Fantasy');
    expect(tree[0].children[0].name).toBe('Fantasy');
    expect(tree[0].children[0].children[0].name).toBe('Epic');
  });

  it('counts a book once per subtree even when tagged at several depths', async () => {
    // A book tagged both "Fantasy" and "Fantasy > Epic" must not count twice in
    // Fantasy's rollup — summing child counts would report 2 books for 1 book.
    setup(
      [
        { id: 'fantasy', name: 'Fantasy', level: 0, parentId: null },
        { id: 'epic', name: 'Epic', level: 1, parentId: 'fantasy' },
      ],
      [
        ['fantasy', 'b1'],
        ['epic', 'b1'],
      ]
    );

    const [fantasy] = await getCategoryTree();

    expect(fantasy.totalBookCount).toBe(1);
    expect(fantasy.bookCount).toBe(1);
    expect(fantasy.children[0].totalBookCount).toBe(1);
  });

  it('reports direct and subtree counts separately', async () => {
    // The distinction the cards rely on: a container root advertises its subtree
    // while its own page would list only what is tagged directly on it.
    setup(
      [
        { id: 'root', name: 'Root', level: 0, parentId: null },
        { id: 'kid', name: 'Kid', level: 1, parentId: 'root' },
      ],
      [
        ['root', 'b1'],
        ['kid', 'b2'],
        ['kid', 'b3'],
      ]
    );

    const [root] = await getCategoryTree();

    expect(root.bookCount).toBe(1);
    expect(root.totalBookCount).toBe(3);
  });

  it('keeps a bookless container that has books beneath it', async () => {
    // 15 of 16 production roots look like this — pure ladder containers.
    setup(
      [
        { id: 'root', name: 'Root', level: 0, parentId: null },
        { id: 'leaf', name: 'Leaf', level: 1, parentId: 'root' },
      ],
      [['leaf', 'b1']]
    );

    const [root] = await getCategoryTree();

    expect(root.bookCount).toBe(0);
    expect(root.totalBookCount).toBe(1);
    expect(root.children).toHaveLength(1);
  });

  it('prunes branches with no visible books anywhere', async () => {
    setup(
      [
        { id: 'keep', name: 'Keep', level: 0, parentId: null },
        { id: 'keep-kid', name: 'Keep Kid', level: 1, parentId: 'keep' },
        { id: 'drop', name: 'Drop', level: 0, parentId: null },
        { id: 'drop-kid', name: 'Drop Kid', level: 1, parentId: 'drop' },
      ],
      [['keep-kid', 'b1']]
    );

    const tree = await getCategoryTree();

    expect(tree.map((n) => n.name)).toEqual(['Keep']);
  });

  it('treats a category whose parent no longer exists as a root', async () => {
    // Otherwise a dangling parent_id would silently hide the whole subtree.
    setup([{ id: 'orphan', name: 'Orphan', level: 2, parentId: 'missing' }], [['orphan', 'b1']]);

    const tree = await getCategoryTree();

    expect(tree.map((n) => n.name)).toEqual(['Orphan']);
  });

  it('terminates on a parent_id cycle instead of overflowing the stack', async () => {
    setup(
      [
        { id: 'a', name: 'A', level: 0, parentId: null },
        { id: 'b', name: 'B', level: 1, parentId: 'a' },
        { id: 'c', name: 'C', level: 2, parentId: 'b' },
      ],
      [['c', 'b1']]
    );
    // Close the loop: c becomes b's parent as well as its child.
    mockPrisma.category.findMany.mockResolvedValue([
      { id: 'a', name: 'A', level: 0, parentId: null },
      { id: 'b', name: 'B', level: 1, parentId: 'a' },
      { id: 'c', name: 'C', level: 2, parentId: 'b' },
      { id: 'b2', name: 'B2', level: 3, parentId: 'c' },
      { id: 'c2', name: 'C2', level: 4, parentId: 'b2' },
    ]);
    mockPrisma.bookCategory.findMany.mockResolvedValue([{ categoryId: 'c', bookId: 'b1' }]);

    const tree = await getCategoryTree();

    expect(tree).toHaveLength(1);
  });

  it('sorts roots and nested siblings by name regardless of row order', async () => {
    // The query's `orderBy` only orders the flat row set; sibling order after
    // grouping is the tree builder's job, at every depth.
    setup(
      [
        { id: 'z', name: 'Zoology', level: 0, parentId: null },
        { id: 'a', name: 'Art', level: 0, parentId: null },
        { id: 'a-y', name: 'Yarn', level: 1, parentId: 'a' },
        { id: 'a-b', name: 'Bronze', level: 1, parentId: 'a' },
      ],
      [
        ['z', 'b1'],
        ['a-y', 'b2'],
        ['a-b', 'b3'],
      ]
    );

    const tree = await getCategoryTree();

    expect(tree.map((n) => n.name)).toEqual(['Art', 'Zoology']);
    expect(tree[0].children.map((n) => n.name)).toEqual(['Bronze', 'Yarn']);
  });

  it('excludes hidden books from rollups via the query filter', async () => {
    setup([{ id: 'root', name: 'Root', level: 0, parentId: null }], [['root', 'b1']]);

    await getCategoryTree();

    // Visibility must be enforced in SQL — filtering in memory here would mean
    // hidden books still inflated the counts.
    expect(mockPrisma.bookCategory.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { book: { hiddenAt: null } } })
    );
  });
});

describe('getCategoryTreeNode', () => {
  const CATS: Cat[] = [
    { id: 'sff', name: 'Science Fiction & Fantasy', level: 0, parentId: null },
    { id: 'fantasy', name: 'Fantasy', level: 1, parentId: 'sff' },
    { id: 'epic', name: 'Epic', level: 2, parentId: 'fantasy' },
    { id: 'aa', name: 'Action & Adventure', level: 2, parentId: 'fantasy' },
  ];

  it('returns the ancestor breadcrumb root-first, excluding itself', async () => {
    setup(CATS, [['epic', 'b1']]);

    const node = await getCategoryTreeNode('epic');

    expect(node?.ancestors).toEqual([
      { id: 'sff', name: 'Science Fiction & Fantasy' },
      { id: 'fantasy', name: 'Fantasy' },
    ]);
  });

  it('returns immediate children with their own rollups', async () => {
    setup(CATS, [
      ['fantasy', 'b1'],
      ['epic', 'b2'],
      ['aa', 'b3'],
    ]);

    const node = await getCategoryTreeNode('fantasy');

    expect(node?.bookCount).toBe(1);
    expect(node?.totalBookCount).toBe(3);
    expect(node?.children.map((c) => [c.name, c.totalBookCount])).toEqual([
      ['Action & Adventure', 1],
      ['Epic', 1],
    ]);
  });

  it('has no ancestors at the root', async () => {
    setup(CATS, [['epic', 'b1']]);

    const node = await getCategoryTreeNode('sff');

    expect(node?.ancestors).toEqual([]);
  });

  it('returns the node with an empty state rather than null when it has no visible books', async () => {
    // The category row is real, so its page should render empty, not 404.
    setup(CATS, []);

    const node = await getCategoryTreeNode('fantasy');

    expect(node).not.toBeNull();
    expect(node?.totalBookCount).toBe(0);
    expect(node?.children).toEqual([]);
  });

  it('returns null for a category that does not exist', async () => {
    setup(CATS, [['epic', 'b1']]);

    expect(await getCategoryTreeNode('nope')).toBeNull();
  });
});
