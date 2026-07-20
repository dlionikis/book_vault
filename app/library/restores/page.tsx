import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { redirect } from 'next/navigation';
import Link from 'next/link';
import Image from 'next/image';
import BackButton from '@/components/BackButton';
import { prisma } from '@/lib/db';
import { getCoverUrl } from '@/lib/media';
import { estimatedCompletion } from '@/lib/restore';
import RestoresAutoRefresh from '@/components/RestoresAutoRefresh';

// DB-backed, per-user — never statically prerendered.
export const dynamic = 'force-dynamic';

interface RestoreRow {
  id: string;
  status: string;
  requestedAt: string;
  completedAt: string | null;
  estimatedCompletion: string | null;
  book: { id: string; title: string; coverUrl: string | null };
}

async function getRestores(userId: string): Promise<RestoreRow[]> {
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 3600_000);
  const requests = await prisma.mediaRestoreRequest.findMany({
    where: {
      requestedByUserId: userId,
      OR: [{ status: 'in_progress' }, { status: 'completed', completedAt: { gte: sevenDaysAgo } }],
    },
    include: { book: { select: { id: true, title: true, coverUrl: true } } },
    orderBy: { requestedAt: 'desc' },
  });

  return Promise.all(
    requests.map(async (r) => ({
      id: r.id,
      status: r.status,
      requestedAt: r.requestedAt.toISOString(),
      completedAt: r.completedAt?.toISOString() ?? null,
      estimatedCompletion: r.status === 'in_progress' ? estimatedCompletion(r.requestedAt) : null,
      book: { id: r.book.id, title: r.book.title, coverUrl: await getCoverUrl(r.book.coverUrl) },
    }))
  );
}

function RestoreCard({ row, subtitle }: { row: RestoreRow; subtitle: string }) {
  return (
    <Link
      href={`/books/${row.book.id}`}
      className="flex items-center gap-4 rounded-lg bg-white p-4 shadow-sm transition-shadow hover:shadow-md dark:bg-gray-800"
    >
      <div className="relative h-16 w-12 flex-shrink-0 overflow-hidden rounded bg-gray-200 dark:bg-gray-700">
        {row.book.coverUrl && (
          <Image src={row.book.coverUrl} alt={row.book.title} fill className="object-cover" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate font-medium text-gray-900 dark:text-white">{row.book.title}</div>
        <div className="text-sm text-gray-600 dark:text-gray-400">{subtitle}</div>
      </div>
      {row.status === 'in_progress' && (
        <svg className="h-5 w-5 animate-spin text-blue-600" fill="none" viewBox="0 0 24 24">
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="4"
          />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
      )}
    </Link>
  );
}

function formatEta(iso: string | null): string {
  if (!iso) return 'about 3–5 hours';
  return new Date(iso).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export default async function RestoresPage() {
  const session = await getServerSession(authOptions);
  if (!session?.user?.id) {
    redirect('/auth/signin');
  }

  const restores = await getRestores(session.user.id);
  const active = restores.filter((r) => r.status === 'in_progress');
  const recent = restores.filter((r) => r.status === 'completed');

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Refresh the server component while any restore is active */}
      <RestoresAutoRefresh activeCount={active.length} />

      <div className="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
        <BackButton />
        <h1 className="mb-6 mt-4 text-3xl font-bold text-gray-900 dark:text-white">Restores</h1>

        {restores.length === 0 ? (
          <p className="text-gray-600 dark:text-gray-400">
            No restores yet. When you request an archived audiobook, it&apos;ll show up here while
            it&apos;s being restored.
          </p>
        ) : (
          <div className="space-y-8">
            {active.length > 0 && (
              <section>
                <h2 className="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
                  Restoring ({active.length})
                </h2>
                <div className="space-y-3">
                  {active.map((r) => (
                    <RestoreCard
                      key={r.id}
                      row={r}
                      subtitle={`Ready around ${formatEta(r.estimatedCompletion)}`}
                    />
                  ))}
                </div>
              </section>
            )}

            {recent.length > 0 && (
              <section>
                <h2 className="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
                  Recently restored
                </h2>
                <div className="space-y-3">
                  {recent.map((r) => (
                    <RestoreCard key={r.id} row={r} subtitle="Ready to play" />
                  ))}
                </div>
              </section>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
