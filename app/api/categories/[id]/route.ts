import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.category,
    entityKind: 'category',
    entityName: 'Category',
    getResponseFields: (category: any) => ({
      id: category.id,
      name: category.name,
    }),
    // Categories include parent for breadcrumbs (though not currently exposed in response)
    entityInclude: { parent: true },
  });
}
