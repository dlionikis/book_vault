import { NextRequest } from 'next/server';
import { handleEntityDetailWithBooks } from '@/lib/api-helpers';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  return handleEntityDetailWithBooks(request, params, {
    entityModel: prisma.series,
    entityKind: 'series',
    entityName: 'Series',
    getResponseFields: (series: any) => ({
      id: series.id,
      title: series.title,
      asin: series.asin,
    }),
  });
}
