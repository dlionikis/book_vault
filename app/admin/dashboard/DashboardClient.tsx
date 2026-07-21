'use client';

import { useState, useEffect } from 'react';
import BudgetBar from './components/BudgetBar';
import HealthTab from './tabs/HealthTab';
import CostsTab from './tabs/CostsTab';
import EcsHealthTab from './tabs/EcsHealthTab';
import S3StorageTab from './tabs/S3StorageTab';
import RestoresTab from './tabs/RestoresTab';

const TABS = ['Health', 'Costs', 'ECS Health', 'S3 Storage', 'Restores'] as const;
type Tab = (typeof TABS)[number];

interface BudgetInfo {
  name: string;
  limit: number;
  actualSpend: number;
  forecastedSpend: number;
  percentUsed: number;
}

export default function DashboardClient() {
  const [activeTab, setActiveTab] = useState<Tab>('Health');
  const [budgets, setBudgets] = useState<BudgetInfo[]>([]);
  const [budgetLoading, setBudgetLoading] = useState(true);
  const [budgetError, setBudgetError] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/admin/budgets')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load budgets');
        return res.json();
      })
      .then((data) => setBudgets(data.budgets))
      .catch((err) => setBudgetError(err.message))
      .finally(() => setBudgetLoading(false));
  }, []);

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">Admin Dashboard</h1>

      {/* Budget Overview */}
      <div className="mb-8">
        <h2 className="text-lg font-semibold text-gray-700 dark:text-gray-300 mb-3">
          Budget Status
        </h2>
        {budgetLoading ? (
          <div className="h-16 bg-gray-100 dark:bg-gray-800 rounded animate-pulse" />
        ) : budgetError ? (
          <div className="text-red-600 dark:text-red-400 text-sm">{budgetError}</div>
        ) : budgets.length === 0 ? (
          <div className="text-gray-500 dark:text-gray-400 text-sm">No budgets configured</div>
        ) : (
          <div className="space-y-3">
            {budgets.map((b) => (
              <BudgetBar key={b.name} budget={b} />
            ))}
          </div>
        )}
      </div>

      {/* Tab Navigation */}
      <div className="border-b border-gray-200 dark:border-gray-700 mb-6">
        <nav className="flex space-x-8">
          {TABS.map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`py-2 px-1 border-b-2 text-sm font-medium transition-colors ${
                activeTab === tab
                  ? 'border-blue-500 text-blue-600 dark:text-blue-400'
                  : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 hover:border-gray-300'
              }`}
            >
              {tab}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      {activeTab === 'Health' && <HealthTab />}
      {activeTab === 'Costs' && <CostsTab />}
      {activeTab === 'ECS Health' && <EcsHealthTab />}
      {activeTab === 'S3 Storage' && <S3StorageTab />}
      {activeTab === 'Restores' && <RestoresTab />}
    </div>
  );
}
