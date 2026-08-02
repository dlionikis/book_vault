import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';
import { getCategoryTreeNode } from '@/lib/queries/browse-entities';

export async function GET(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.category,
    entityKind: 'category',
    entityName: 'Category',
    getResponseFields: (category: any) => ({
      id: category.id,
      name: category.name,
      level: category.level,
    }),
    // Categories are a hierarchy (Audible ships genres as ladders), so the detail
    // response carries the breadcrumb and the children to drill into alongside the
    // books tagged directly on this node. `books`/`pagination` cover the latter;
    // `totalBookCount` is the subtree rollup the child cards advertise.
    getExtraFields: async (categoryId) => {
      const node = await getCategoryTreeNode(categoryId);
      if (!node) return {};

      return {
        ancestors: node.ancestors,
        subcategories: node.children.map((child) => ({
          id: child.id,
          name: child.name,
          bookCount: child.bookCount,
          totalBookCount: child.totalBookCount,
          hasChildren: child.children.length > 0,
        })),
        totalBookCount: node.totalBookCount,
      };
    },
  });
}
