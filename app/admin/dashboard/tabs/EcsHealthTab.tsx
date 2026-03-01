'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';

interface TaskInfo {
  taskId: string;
  service: string;
  stoppedAt: string | null;
  durationMinutes: number | null;
  stopCode: string | null;
  stoppedReason: string | null;
}

interface ServiceStatus {
  name: string;
  running: number;
  desired: number;
  pending: number;
}

interface EcsHealthData {
  cluster: string;
  services: ServiceStatus[];
  tasks: {
    running: number;
    desired: number;
    pending: number;
    recentlyStopped: TaskInfo[];
  };
  metrics: {
    cpu: number[];
    memory: number[];
    timestamps: string[];
  };
  summary: {
    spotInterruptions: number;
    crashes: number;
    deploymentStops: number;
  };
}

const HOUR_OPTIONS = [
  { label: '24h', value: 24 },
  { label: '48h', value: 48 },
  { label: '7d', value: 168 },
];

export default function EcsHealthTab() {
  const [data, setData] = useState<EcsHealthData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [hours, setHours] = useState(24);

  const fetchData = useCallback(() => {
    setLoading(true);
    setError(null);
    fetch(`/api/admin/ecs-health?hours=${hours}`)
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load ECS health data');
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [hours]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [fetchData]);

  if (loading && !data) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-24 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
          ))}
        </div>
        <div className="h-64 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
      </div>
    );
  }

  if (error && !data) {
    return <div className="text-red-600 dark:text-red-400">{error}</div>;
  }

  if (!data) return null;

  const chartData = data.metrics.timestamps.map((ts, i) => ({
    time: new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    CPU: data.metrics.cpu[i],
    Memory: data.metrics.memory[i],
  }));

  return (
    <div className="space-y-6">
      {/* Controls */}
      <div className="flex items-center gap-4">
        <select
          value={hours}
          onChange={(e) => setHours(Number(e.target.value))}
          className="px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-800 dark:text-gray-200"
        >
          {HOUR_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
        <button
          onClick={fetchData}
          disabled={loading}
          className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? 'Refreshing...' : 'Refresh'}
        </button>
      </div>

      {/* Per-Service Status */}
      {data.services.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">Services</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {data.services.map((svc) => (
              <div
                key={svc.name}
                className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700"
              >
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-gray-800 dark:text-gray-200">
                    {svc.name}
                  </span>
                  <span
                    className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                      svc.running > 0
                        ? 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300'
                        : svc.desired === 0
                          ? 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
                          : 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300'
                    }`}
                  >
                    {svc.running > 0 ? 'Running' : svc.desired === 0 ? 'Dormant' : 'Down'}
                  </span>
                </div>
                <div className="flex gap-4 text-sm">
                  <span className="text-gray-500 dark:text-gray-400">
                    Running: <span className="text-gray-800 dark:text-gray-200">{svc.running}</span>
                  </span>
                  <span className="text-gray-500 dark:text-gray-400">
                    Desired: <span className="text-gray-800 dark:text-gray-200">{svc.desired}</span>
                  </span>
                  {svc.pending > 0 && (
                    <span className="text-yellow-600 dark:text-yellow-400">
                      Pending: {svc.pending}
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Aggregate Status + Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
        <StatusCard label="Total Running" value={data.tasks.running} color="green" />
        <StatusCard label="Total Desired" value={data.tasks.desired} color="blue" />
        <StatusCard label="Total Pending" value={data.tasks.pending} color="yellow" />
        <StatusCard label="Spot Interruptions" value={data.summary.spotInterruptions} color="red" />
        <StatusCard label="Crashes" value={data.summary.crashes} color="red" />
        <StatusCard label="Deployment Stops" value={data.summary.deploymentStops} color="gray" />
      </div>

      {/* CPU/Memory Chart */}
      {chartData.length > 0 && (
        <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-4">
            CPU & Memory Utilization
          </h3>
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
              <XAxis dataKey="time" tick={{ fontSize: 12 }} />
              <YAxis tick={{ fontSize: 12 }} tickFormatter={(v) => `${v}%`} domain={[0, 100]} />
              <Tooltip formatter={(value) => `${Number(value).toFixed(1)}%`} />
              <Legend />
              <Line type="monotone" dataKey="CPU" stroke="#3b82f6" dot={false} />
              <Line type="monotone" dataKey="Memory" stroke="#8b5cf6" dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Stopped Tasks Table */}
      {data.tasks.recentlyStopped.length > 0 && (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 px-4 py-3 border-b border-gray-200 dark:border-gray-700">
            Recently Stopped Tasks
          </h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 dark:bg-gray-700">
                  <th className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                    Task ID
                  </th>
                  <th className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                    Service
                  </th>
                  <th className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                    Stopped At
                  </th>
                  <th className="text-right px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                    Duration
                  </th>
                  <th className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                    Stop Code
                  </th>
                  <th className="text-left px-4 py-2 text-gray-600 dark:text-gray-400 font-medium">
                    Reason
                  </th>
                </tr>
              </thead>
              <tbody>
                {data.tasks.recentlyStopped.map((task) => (
                  <tr key={task.taskId} className="border-t border-gray-100 dark:border-gray-700">
                    <td className="px-4 py-2 text-gray-800 dark:text-gray-200 font-mono text-xs">
                      {task.taskId.slice(0, 8)}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400 text-xs">
                      {task.service}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400">
                      {task.stoppedAt ? new Date(task.stoppedAt).toLocaleString() : '—'}
                    </td>
                    <td className="px-4 py-2 text-right text-gray-600 dark:text-gray-400">
                      {task.durationMinutes !== null ? `${task.durationMinutes}m` : '—'}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400">
                      {task.stopCode || '—'}
                    </td>
                    <td className="px-4 py-2 text-gray-600 dark:text-gray-400 max-w-xs truncate">
                      {task.stoppedReason || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function StatusCard({
  label,
  value,
  color,
}: {
  label: string;
  value: number;
  color: 'green' | 'blue' | 'yellow' | 'red' | 'gray';
}) {
  const colorMap = {
    green: 'text-green-600 dark:text-green-400',
    blue: 'text-blue-600 dark:text-blue-400',
    yellow: 'text-yellow-600 dark:text-yellow-400',
    red: 'text-red-600 dark:text-red-400',
    gray: 'text-gray-600 dark:text-gray-400',
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
      <div className="text-xs text-gray-500 dark:text-gray-400 mb-1">{label}</div>
      <div className={`text-2xl font-bold ${colorMap[color]}`}>{value}</div>
    </div>
  );
}
