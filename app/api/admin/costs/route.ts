import { NextRequest, NextResponse } from 'next/server';
import { CostExplorerClient, GetCostAndUsageCommand } from '@aws-sdk/client-cost-explorer';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_24H } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';

const client = new CostExplorerClient({ region: process.env.AWS_REGION || 'us-east-1' });

interface ServiceCost {
  service: string;
  cost: number;
}

interface MonthCost {
  month: string;
  services: ServiceCost[];
  total: number;
}

interface CostsResponse {
  months: MonthCost[];
  currency: string;
}

const ALLOWED_MONTHS = [1, 2, 3, 6, 12, 24];

export const GET = withLogging(async (request: NextRequest) => {
  const { error } = await requireAdmin(request);
  if (error) return error;

  const rawMonths = parseInt(request.nextUrl.searchParams.get('months') || '6');
  const months = ALLOWED_MONTHS.includes(rawMonths) ? rawMonths : 6;
  const cacheKey = `admin:costs:${months}`;

  const cached = getCached<CostsResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  try {
    const end = new Date();
    const start = new Date();
    start.setDate(1); // Avoid month rollover (e.g., Mar 31 - 1 month = Mar 3)
    start.setMonth(start.getMonth() - months);

    const command = new GetCostAndUsageCommand({
      TimePeriod: {
        Start: start.toISOString().slice(0, 10),
        End: end.toISOString().slice(0, 10),
      },
      Granularity: 'MONTHLY',
      Metrics: ['UnblendedCost'],
      GroupBy: [{ Type: 'DIMENSION', Key: 'SERVICE' }],
    });

    const result = await client.send(command);

    const monthsData: MonthCost[] = (result.ResultsByTime || []).map((period) => {
      const services: ServiceCost[] = (period.Groups || []).map((group) => ({
        service: group.Keys?.[0] || 'Unknown',
        cost: parseFloat(group.Metrics?.UnblendedCost?.Amount || '0'),
      }));

      const total = services.reduce((sum, s) => sum + s.cost, 0);

      return {
        month: period.TimePeriod?.Start || '',
        services: services.sort((a, b) => b.cost - a.cost),
        total: Math.round(total * 100) / 100,
      };
    });

    const response: CostsResponse = {
      months: monthsData,
      currency: result.ResultsByTime?.[0]?.Groups?.[0]?.Metrics?.UnblendedCost?.Unit || 'USD',
    };

    setCache(cacheKey, response, CACHE_24H);
    return NextResponse.json(response);
  } catch (err) {
    console.error('Failed to fetch AWS costs:', err);
    return NextResponse.json({ error: 'Failed to fetch cost data' }, { status: 500 });
  }
});
