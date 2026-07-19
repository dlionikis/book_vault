import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.narrator,
    joinTableModel: prisma.bookNarrator,
    idFieldName: 'narratorId',
    entityName: 'Narrator',
    getResponseFields: (narrator: any) => ({
      id: narrator.id,
      name: narrator.name,
      asin: narrator.asin,
    }),
  });
}
