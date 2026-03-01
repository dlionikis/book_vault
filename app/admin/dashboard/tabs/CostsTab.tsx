'use client';

import { useState, useEffect } from 'react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';

interface ServiceCost {
  service: string;
  cost: number;
}

interface MonthCost {
  month: string;
  services: ServiceCost[];
  total: number;
}

interface CostsData {
  months: MonthCost[];
  currency: string;
}

export default function CostsTab() {
  const [data, setData] = useState<CostsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/admin/costs?months=6')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load cost data');
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <div className="h-64 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
        <div className="h-48 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
      </div>
    );
  }

  if (error) {
    return <div className="text-red-600 dark:text-red-400">{error}</div>;
  }

  if (!data || data.months.length === 0) {
    return <div className="text-gray-500 dark:text-gray-400">No cost data available</div>;
  }

  const chartData = data.months.map((m) => ({
    month: m.month.slice(0, 7),
    total: m.total,
  }));

  // Build service comparison between this month and last month
  const thisMonth = data.months[data.months.length - 1];
  const lastMonth = data.months.length >= 2 ? data.months[data.months.length - 2] : null;

  const lastMonthMap = new Map(lastMonth?.services.map((s) => [s.service, s.cost]) || []);

  const serviceRows = thisMonth.services.map((s) => {
    const prev = lastMonthMap.get(s.service) || 0;
    const change = prev > 0 ? ((s.cost - prev) / prev) * 100 : null;
    return { service: s.service, current: s.cost, previous: prev, change };
  });

  return (
    <div className="space-y-6">
      {/* Cost Trend Chart */}
      <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-4">
          Monthly Cost Trend
        </h3>
        <ResponsiveContainer width="100%" height={280}>
          <AreaChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
            <XAxis dataKey="month" tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
            <Tooltip formatter={(value) => [`$${Number(value).toFixed(2)}`, 'Total']} />
            <Area
              type="monotone"
              dataKey="total"
              stroke="#3b82f6"
              fill="#3b82f6"
              fillOpacity={0.1}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Service Breakdown Table */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 dark:bg-gray-750">
              <th className="text-left px-4 py-3 text-gray-600 dark:text-gray-400 font-medium">
                Service
              </th>
              <th className="text-right px-4 py-3 text-gray-600 dark:text-gray-400 font-medium">
                This Month
              </th>
              <th className="text-right px-4 py-3 text-gray-600 dark:text-gray-400 font-medium">
                Last Month
              </th>
              <th className="text-right px-4 py-3 text-gray-600 dark:text-gray-400 font-medium">
                Change
              </th>
            </tr>
          </thead>
          <tbody>
            {serviceRows.map((row) => (
              <tr key={row.service} className="border-t border-gray-100 dark:border-gray-700">
                <td className="px-4 py-3 text-gray-800 dark:text-gray-200">{row.service}</td>
                <td className="px-4 py-3 text-right text-gray-800 dark:text-gray-200">
                  ${row.current.toFixed(2)}
                </td>
                <td className="px-4 py-3 text-right text-gray-500 dark:text-gray-400">
                  ${row.previous.toFixed(2)}
                </td>
                <td className="px-4 py-3 text-right">
                  {row.change !== null ? (
                    <span
                      className={
                        row.change > 0
                          ? 'text-red-600 dark:text-red-400'
                          : row.change < 0
                            ? 'text-green-600 dark:text-green-400'
                            : 'text-gray-500 dark:text-gray-400'
                      }
                    >
                      {row.change > 0 ? '+' : ''}
                      {row.change.toFixed(1)}%
                    </span>
                  ) : (
                    <span className="text-gray-400">—</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
