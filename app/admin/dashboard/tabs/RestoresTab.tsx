'use client';

import { useState, useEffect, useCallback } from 'react';

interface RestoreRequestRow {
  id: string;
  bookId: string;
  bookTitle: string;
  status: 'in_progress' | 'completed' | 'failed';
  requestedByUsername: string | null;
  errorMessage: string | null;
  requestedAt: string;
  lastCheckedAt: string | null;
  completedAt: string | null;
}

interface RestoresData {
  summary: {
    inProgress: number;
    completedLast7d: number;
    failedLast7d: number;
    stuck: number;
    lastPolledAt: string | null;
  };
  requests: RestoreRequestRow[];
  push: {
    configured: boolean;
    activeTokens: number;
    inactiveTokens: number;
  };
  generatedAt: string;
}

const STATUS_BADGE: Record<RestoreRequestRow['status'], string> = {
  in_progress: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300',
  completed: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300',
  failed: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300',
};

function fmt(ts: string | null): string {
  return ts ? new Date(ts).toLocaleString() : '—';
}

export default function RestoresTab() {
  const [data, setData] = useState<RestoresData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(() => {
    setLoading(true);
    setError(null);
    fetch('/api/admin/restores')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load restore data');
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    // Initial load + 60s auto-refresh; setState resolves async, not on mount.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    fetchData();
    const interval = setInterval(fetchData, 60 * 1000);
    return () => clearInterval(interval);
  }, [fetchData]);

  if (loading && !data) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-20 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
          ))}
        </div>
        <div className="h-64 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
      </div>
    );
  }

  if (error) {
    return <div className="text-red-600 dark:text-red-400 text-sm">{error}</div>;
  }

  if (!data) return null;

  return (
    <div className="space-y-6">
      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <SummaryCard label="In progress" value={data.summary.inProgress} />
        <SummaryCard label="Completed (7d)" value={data.summary.completedLast7d} />
        <SummaryCard
          label="Failed (7d)"
          value={data.summary.failedLast7d}
          alert={data.summary.failedLast7d > 0}
        />
        <SummaryCard
          label="Stuck (>6h)"
          value={data.summary.stuck}
          alert={data.summary.stuck > 0}
        />
      </div>

      {/* Poller + push health line */}
      <div className="flex flex-wrap gap-x-8 gap-y-2 text-sm text-gray-600 dark:text-gray-400">
        <span>
          Last poll:{' '}
          <span className="text-gray-800 dark:text-gray-200">{fmt(data.summary.lastPolledAt)}</span>
        </span>
        <span>
          Push:{' '}
          <span className="text-gray-800 dark:text-gray-200">
            {data.push.configured ? 'configured' : 'not configured'} · {data.push.activeTokens}{' '}
            active token{data.push.activeTokens === 1 ? '' : 's'}
            {data.push.inactiveTokens > 0 ? ` · ${data.push.inactiveTokens} inactive` : ''}
          </span>
        </span>
      </div>

      {/* Requests table */}
      {data.requests.length === 0 ? (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-8 text-center text-gray-500 dark:text-gray-400 text-sm">
          No restore requests in the last 7 days
        </div>
      ) : (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 dark:bg-gray-700">
                  {['Book', 'Status', 'Requested', 'Last Checked', 'Completed', 'By'].map((h) => (
                    <th
                      key={h}
                      className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium whitespace-nowrap"
                    >
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {data.requests.map((r) => (
                  <tr
                    key={r.id}
                    className="border-t border-gray-100 dark:border-gray-700 align-top"
                  >
                    <td className="px-4 py-2 text-gray-800 dark:text-gray-200 max-w-xs">
                      <div className="truncate" title={r.bookTitle}>
                        {r.bookTitle}
                      </div>
                      {r.errorMessage && (
                        <div
                          className="text-xs text-red-600 dark:text-red-400 truncate"
                          title={r.errorMessage}
                        >
                          {r.errorMessage}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2 whitespace-nowrap">
                      <span
                        className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_BADGE[r.status]}`}
                      >
                        {r.status}
                      </span>
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                      {fmt(r.requestedAt)}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                      {fmt(r.lastCheckedAt)}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                      {fmt(r.completedAt)}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                      {r.requestedByUsername || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="text-xs text-gray-400">
        Updated {new Date(data.generatedAt).toLocaleTimeString()}
      </div>
    </div>
  );
}

function SummaryCard({ label, value, alert }: { label: string; value: number; alert?: boolean }) {
  return (
    <div
      className={`bg-white dark:bg-gray-800 rounded-lg border p-4 ${
        alert ? 'border-amber-300 dark:border-amber-900' : 'border-gray-200 dark:border-gray-700'
      }`}
    >
      <div
        className={`text-2xl font-bold ${
          alert ? 'text-amber-600 dark:text-amber-400' : 'text-gray-900 dark:text-white'
        }`}
      >
        {value}
      </div>
      <div className="text-xs text-gray-500 dark:text-gray-400 mt-1">{label}</div>
    </div>
  );
}
