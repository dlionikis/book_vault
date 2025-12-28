import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.author,
    joinTableModel: prisma.bookAuthor,
    idFieldName: 'authorId',
    entityName: 'Author',
    getResponseFields: (author) => ({
      id: author.id,
      name: author.name,
      asin: author.asin,
    }),
  });
}
