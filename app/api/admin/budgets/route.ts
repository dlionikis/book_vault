import { NextRequest, NextResponse } from 'next/server';
import { BudgetsClient, DescribeBudgetsCommand } from '@aws-sdk/client-budgets';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_1H } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';

const client = new BudgetsClient({ region: process.env.AWS_REGION || 'us-east-1' });

interface BudgetInfo {
  name: string;
  limit: number;
  actualSpend: number;
  forecastedSpend: number;
  percentUsed: number;
}

interface BudgetsResponse {
  budgets: BudgetInfo[];
}

export const GET = withLogging(async (request: NextRequest) => {
  const { user, error } = await requireAdmin(request);
  if (error) return error;

  const cacheKey = 'admin:budgets';
  const cached = getCached<BudgetsResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  const accountId = process.env.AWS_ACCOUNT_ID;
  if (!accountId) {
    return NextResponse.json({ error: 'AWS_ACCOUNT_ID not configured' }, { status: 500 });
  }

  try {
    const command = new DescribeBudgetsCommand({ AccountId: accountId });
    const result = await client.send(command);

    const budgets: BudgetInfo[] = (result.Budgets || []).map((budget) => {
      const limit = parseFloat(budget.BudgetLimit?.Amount || '0');
      const actualSpend = parseFloat(budget.CalculatedSpend?.ActualSpend?.Amount || '0');
      const forecastedSpend = parseFloat(budget.CalculatedSpend?.ForecastedSpend?.Amount || '0');
      const percentUsed = limit > 0 ? Math.round((actualSpend / limit) * 100) : 0;

      return {
        name: budget.BudgetName || 'Unknown',
        limit: Math.round(limit * 100) / 100,
        actualSpend: Math.round(actualSpend * 100) / 100,
        forecastedSpend: Math.round(forecastedSpend * 100) / 100,
        percentUsed,
      };
    });

    const response: BudgetsResponse = { budgets };
    setCache(cacheKey, response, CACHE_1H);
    return NextResponse.json(response);
  } catch (err) {
    console.error('Failed to fetch budgets:', err);
    return NextResponse.json({ error: 'Failed to fetch budget data' }, { status: 500 });
  }
});
