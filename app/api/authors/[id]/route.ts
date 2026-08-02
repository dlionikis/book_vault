import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.author,
    entityKind: 'author',
    entityName: 'Author',
    getResponseFields: (author: any) => ({
      id: author.id,
      name: author.name,
      asin: author.asin,
    }),
  });
}
