'use client';

import { useState, useEffect, useCallback } from 'react';

type HealthStatus = 'ok' | 'warn' | 'error';

interface HealthCheck {
  name: string;
  status: HealthStatus;
  detail: string;
  meta?: Record<string, unknown>;
}

interface HealthData {
  checks: HealthCheck[];
  generatedAt: string;
}

const STATUS_STYLES: Record<HealthStatus, { dot: string; label: string; ring: string }> = {
  ok: {
    dot: 'bg-green-500',
    label: 'text-green-700 dark:text-green-400',
    ring: 'border-green-200 dark:border-green-900',
  },
  warn: {
    dot: 'bg-amber-500',
    label: 'text-amber-700 dark:text-amber-400',
    ring: 'border-amber-200 dark:border-amber-900',
  },
  error: {
    dot: 'bg-red-500',
    label: 'text-red-700 dark:text-red-400',
    ring: 'border-red-300 dark:border-red-900',
  },
};

export default function HealthTab() {
  const [data, setData] = useState<HealthData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(() => {
    setLoading(true);
    setError(null);
    fetch('/api/admin/health')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load health data');
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    // Initial load + 60s auto-refresh. The setState inside fetchData runs when
    // the request resolves (and per-interval), not synchronously on mount — this
    // is the same fetch-on-mount pattern EcsHealthTab uses.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    fetchData();
    const interval = setInterval(fetchData, 60 * 1000);
    return () => clearInterval(interval);
  }, [fetchData]);

  if (loading && !data) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {[1, 2, 3, 4, 5, 6].map((i) => (
          <div key={i} className="h-24 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
        ))}
      </div>
    );
  }

  if (error) {
    return <div className="text-red-600 dark:text-red-400 text-sm">{error}</div>;
  }

  if (!data) return null;

  const worst: HealthStatus = data.checks.some((c) => c.status === 'error')
    ? 'error'
    : data.checks.some((c) => c.status === 'warn')
      ? 'warn'
      : 'ok';

  return (
    <div className="space-y-4">
      {/* Overall banner */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className={`h-3 w-3 rounded-full ${STATUS_STYLES[worst].dot}`} />
          <span className={`text-sm font-medium ${STATUS_STYLES[worst].label}`}>
            {worst === 'ok'
              ? 'All systems healthy'
              : worst === 'warn'
                ? 'Warnings present'
                : 'Problems detected'}
          </span>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs text-gray-400">
            Updated {new Date(data.generatedAt).toLocaleTimeString()}
          </span>
          <button
            onClick={fetchData}
            className="text-xs px-3 py-1 rounded border border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800"
          >
            Refresh
          </button>
        </div>
      </div>

      {/* Check cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {data.checks.map((check) => {
          const s = STATUS_STYLES[check.status];
          return (
            <div
              key={check.name}
              className={`bg-white dark:bg-gray-800 rounded-lg border p-4 ${s.ring}`}
            >
              <div className="flex items-center gap-2 mb-1">
                <span className={`h-2.5 w-2.5 rounded-full ${s.dot}`} />
                <span className="text-sm font-semibold text-gray-800 dark:text-gray-200">
                  {check.name}
                </span>
              </div>
              <p className={`text-sm ${s.label}`}>{check.detail}</p>
            </div>
          );
        })}
      </div>
    </div>
  );
}
