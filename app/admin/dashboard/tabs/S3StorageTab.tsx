'use client';

import { useState, useEffect } from 'react';
import {
  PieChart,
  Pie,
  Cell,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';

interface StorageTrend {
  timestamps: string[];
  values: number[];
}

interface S3StorageData {
  current: {
    totalSizeGB: number;
    standardGB: number;
    itFrequentGB: number;
    itInfrequentGB: number;
    itArchiveGB: number;
    objectCount: number;
  };
  trends: {
    totalSize: StorageTrend;
    archiveSize: StorageTrend;
    objectCount: StorageTrend;
  };
}

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6'];

export default function S3StorageTab() {
  const [data, setData] = useState<S3StorageData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/admin/s3-storage')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load S3 storage data');
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div className="h-64 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
          <div className="h-64 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
        </div>
      </div>
    );
  }

  if (error) {
    return <div className="text-red-600 dark:text-red-400">{error}</div>;
  }

  if (!data) return null;

  const { current, trends } = data;

  const pieData = [
    { name: 'Standard', value: current.standardGB },
    { name: 'IT Frequent', value: current.itFrequentGB },
    { name: 'IT Infrequent', value: current.itInfrequentGB },
    { name: 'IT Archive', value: current.itArchiveGB },
  ].filter((d) => d.value > 0);

  const archivePercent =
    current.totalSizeGB > 0
      ? Math.round(((current.itInfrequentGB + current.itArchiveGB) / current.totalSizeGB) * 100)
      : 0;

  const trendData = trends.totalSize.timestamps.map((ts, i) => ({
    date: new Date(ts).toLocaleDateString([], { month: 'short', day: 'numeric' }),
    total: trends.totalSize.values[i],
    archive: trends.archiveSize.values[i] || 0,
  }));

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <SummaryCard label="Total Size" value={`${current.totalSizeGB.toFixed(2)} GB`} />
        <SummaryCard label="Objects" value={current.objectCount.toLocaleString()} />
        <SummaryCard label="Archive %" value={`${archivePercent}%`} />
        <SummaryCard label="Standard" value={`${current.standardGB.toFixed(2)} GB`} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Donut Chart */}
        <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-4">
            Storage Class Breakdown
          </h3>
          {pieData.length > 0 ? (
            <ResponsiveContainer width="100%" height={280}>
              <PieChart>
                <Pie
                  data={pieData}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={100}
                  paddingAngle={2}
                  dataKey="value"
                >
                  {pieData.map((_, index) => (
                    <Cell key={index} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip formatter={(value) => `${Number(value).toFixed(2)} GB`} />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <div className="h-[280px] flex items-center justify-center text-gray-500 dark:text-gray-400">
              No storage data
            </div>
          )}
        </div>

        {/* Size Trend */}
        <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-4">
            Size Trend (90 Days)
          </h3>
          {trendData.length > 0 ? (
            <ResponsiveContainer width="100%" height={280}>
              <AreaChart data={trendData}>
                <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 12 }} tickFormatter={(v) => `${v} GB`} />
                <Tooltip formatter={(value) => `${Number(value).toFixed(2)} GB`} />
                <Legend />
                <Area
                  type="monotone"
                  dataKey="total"
                  name="Total"
                  stroke="#3b82f6"
                  fill="#3b82f6"
                  fillOpacity={0.1}
                />
                <Area
                  type="monotone"
                  dataKey="archive"
                  name="Archive"
                  stroke="#8b5cf6"
                  fill="#8b5cf6"
                  fillOpacity={0.1}
                />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="h-[280px] flex items-center justify-center text-gray-500 dark:text-gray-400">
              No trend data
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
      <div className="text-xs text-gray-500 dark:text-gray-400 mb-1">{label}</div>
      <div className="text-xl font-bold text-gray-900 dark:text-white">{value}</div>
    </div>
  );
}
