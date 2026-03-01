'use client';

interface BudgetInfo {
  name: string;
  limit: number;
  actualSpend: number;
  forecastedSpend: number;
  percentUsed: number;
}

export default function BudgetBar({ budget }: { budget: BudgetInfo }) {
  const { name, limit, actualSpend, percentUsed } = budget;

  const barColor =
    percentUsed > 100 ? 'bg-red-500' : percentUsed >= 80 ? 'bg-yellow-500' : 'bg-green-500';

  const textColor =
    percentUsed > 100
      ? 'text-red-600 dark:text-red-400'
      : percentUsed >= 80
        ? 'text-yellow-600 dark:text-yellow-400'
        : 'text-green-600 dark:text-green-400';

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
      <div className="flex justify-between items-center mb-2">
        <span className="text-sm font-medium text-gray-700 dark:text-gray-300">{name}</span>
        <span className={`text-sm font-semibold ${textColor}`}>
          ${actualSpend.toFixed(2)} / ${limit.toFixed(2)} ({percentUsed}%)
        </span>
      </div>
      <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2.5">
        <div
          className={`${barColor} h-2.5 rounded-full transition-all`}
          style={{ width: `${Math.min(percentUsed, 100)}%` }}
        />
      </div>
    </div>
  );
}
