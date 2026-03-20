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
  creditRefund: number;
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

  // Show the last 4 months, reversed so current month is first (left)
  const displayMonths = data.months.slice(-4).reverse();

  // Build cost maps for each display month
  const monthCostMaps = displayMonths.map(
    (m) => new Map(m.services.map((s) => [s.service, s.cost]))
  );

  // Collect all unique services across display months
  const allServices = new Set<string>();
  displayMonths.forEach((m) => m.services.forEach((s) => allServices.add(s.service)));

  const serviceRows = [...allServices]
    .map((service) => {
      const costs = monthCostMaps.map((m) => m.get(service) || 0);
      const current = costs[0]; // current month is first after reverse
      const prev = costs.length >= 2 ? costs[1] : 0;
      const change = prev > 0 ? ((current - prev) / prev) * 100 : null;
      return { service, costs, change };
    })
    .sort((a, b) => b.costs[0] - a.costs[0]);

  const monthLabels = displayMonths.map((m) => {
    const d = new Date(m.month + 'T00:00:00');
    return d.toLocaleDateString([], { month: 'short', year: '2-digit' });
  });

  const totalAccrued = displayMonths.map((m) => m.total);
  const totalCredits = displayMonths.map((m) => Math.abs(m.creditRefund || 0));
  const totalBilled = totalAccrued.map((accrued, i) => accrued - totalCredits[i]);

  const calculateMoM = (values: number[]) => {
    const current = values[0] ?? 0;
    const previous = values[1] ?? 0;
    return previous > 0 ? ((current - previous) / previous) * 100 : null;
  };

  const summaryRows = [
    { label: 'Total accrued', values: totalAccrued },
    { label: 'Total credits', values: totalCredits },
    { label: 'Total billed', values: totalBilled },
  ].map((row) => ({
    ...row,
    change: calculateMoM(row.values),
  }));

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
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 dark:bg-gray-700">
                <th className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                  Service
                </th>
                {monthLabels.map((label, i) => (
                  <th
                    key={label}
                    className={`text-right px-4 py-2 font-medium ${
                      i === 0
                        ? 'text-gray-800 dark:text-gray-200'
                        : 'text-gray-500 dark:text-gray-400'
                    }`}
                  >
                    {label}
                  </th>
                ))}
                <th className="text-right px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                  MoM
                </th>
              </tr>
            </thead>
            <tbody>
              {summaryRows.map((row) => (
                <tr
                  key={row.label}
                  className="border-t border-gray-100 dark:border-gray-700 bg-gray-50/50 dark:bg-gray-700/30"
                >
                  <td className="px-4 py-2 font-semibold text-gray-800 dark:text-gray-200">
                    {row.label}
                  </td>
                  {row.values.map((value, i) => (
                    <td
                      key={i}
                      className={`px-4 py-2 text-right font-semibold ${
                        i === 0
                          ? 'text-gray-800 dark:text-gray-200'
                          : 'text-gray-600 dark:text-gray-300'
                      }`}
                    >
                      ${value.toFixed(2)}
                    </td>
                  ))}
                  <td className="px-4 py-2 text-right">
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

              {serviceRows.map((row) => (
                <tr key={row.service} className="border-t border-gray-100 dark:border-gray-700">
                  <td className="px-4 py-2 text-gray-800 dark:text-gray-200">{row.service}</td>
                  {row.costs.map((cost, i) => (
                    <td
                      key={i}
                      className={`px-4 py-2 text-right ${
                        i === 0
                          ? 'text-gray-800 dark:text-gray-200'
                          : 'text-gray-500 dark:text-gray-400'
                      }`}
                    >
                      ${cost.toFixed(2)}
                    </td>
                  ))}
                  <td className="px-4 py-2 text-right">
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
    </div>
  );
}
