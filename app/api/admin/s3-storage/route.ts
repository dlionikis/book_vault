import { NextRequest, NextResponse } from 'next/server';
import { CloudWatchClient, GetMetricDataCommand } from '@aws-sdk/client-cloudwatch';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_1H } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';

const client = new CloudWatchClient({ region: process.env.AWS_REGION || 'us-east-1' });
const BUCKET = process.env.AWS_S3_BUCKET || 'book-vault-media';

const STORAGE_TYPES = [
  { id: 'standard', type: 'StandardStorage', label: 'Standard' },
  { id: 'it_fa', type: 'IntelligentTieringFAStorage', label: 'IT Frequent Access' },
  { id: 'it_ia', type: 'IntelligentTieringIAStorage', label: 'IT Infrequent Access' },
  { id: 'it_aa', type: 'IntelligentTieringAAStorage', label: 'IT Archive Access' },
] as const;

interface StorageTrend {
  timestamps: string[];
  values: number[];
}

interface S3StorageResponse {
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

export const GET = withLogging(async (request: NextRequest) => {
  const { user, error } = await requireAdmin(request);
  if (error) return error;

  const cacheKey = 'admin:s3-storage';
  const cached = getCached<S3StorageResponse>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  try {
    const now = new Date();
    const startTime = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);

    const queries: {
      Id: string;
      MetricStat: {
        Metric: {
          Namespace: string;
          MetricName: string;
          Dimensions: { Name: string; Value: string }[];
        };
        Period: number;
        Stat: string;
      };
    }[] = STORAGE_TYPES.map((st) => ({
      Id: st.id as string,
      MetricStat: {
        Metric: {
          Namespace: 'AWS/S3',
          MetricName: 'BucketSizeBytes',
          Dimensions: [
            { Name: 'BucketName', Value: BUCKET },
            { Name: 'StorageType', Value: st.type },
          ],
        },
        Period: 86400,
        Stat: 'Average',
      },
    }));

    queries.push({
      Id: 'objects',
      MetricStat: {
        Metric: {
          Namespace: 'AWS/S3',
          MetricName: 'NumberOfObjects',
          Dimensions: [
            { Name: 'BucketName', Value: BUCKET },
            { Name: 'StorageType', Value: 'AllStorageTypes' },
          ],
        },
        Period: 86400,
        Stat: 'Average',
      },
    });

    const result = await client.send(
      new GetMetricDataCommand({
        StartTime: startTime,
        EndTime: now,
        MetricDataQueries: queries,
      })
    );

    const getMetric = (id: string) => result.MetricDataResults?.find((m) => m.Id === id);

    const bytesToGB = (bytes: number) => Math.round((bytes / 1073741824) * 100) / 100;

    const standardData = getMetric('standard');
    const itFaData = getMetric('it_fa');
    const itIaData = getMetric('it_ia');
    const itAaData = getMetric('it_aa');
    const objectsData = getMetric('objects');

    const latestVal = (data: typeof standardData) => (data?.Values?.length ? data.Values[0] : 0);

    const standardGB = bytesToGB(latestVal(standardData));
    const itFrequentGB = bytesToGB(latestVal(itFaData));
    const itInfrequentGB = bytesToGB(latestVal(itIaData));
    const itArchiveGB = bytesToGB(latestVal(itAaData));
    const objectCount = Math.round(latestVal(objectsData));

    const buildTrend = (data: typeof standardData): StorageTrend => ({
      timestamps: (data?.Timestamps || []).map((t) => t.toISOString()),
      values: data?.Values || [],
    });

    // Compute total size trend by summing all storage types at each timestamp
    const totalTimestamps = standardData?.Timestamps || [];
    const totalValues = totalTimestamps.map((_, i) => {
      const sum =
        (standardData?.Values?.[i] || 0) +
        (itFaData?.Values?.[i] || 0) +
        (itIaData?.Values?.[i] || 0) +
        (itAaData?.Values?.[i] || 0);
      return bytesToGB(sum);
    });

    const archiveValues = totalTimestamps.map((_, i) => {
      const sum = (itIaData?.Values?.[i] || 0) + (itAaData?.Values?.[i] || 0);
      return bytesToGB(sum);
    });

    const response: S3StorageResponse = {
      current: {
        totalSizeGB: standardGB + itFrequentGB + itInfrequentGB + itArchiveGB,
        standardGB,
        itFrequentGB,
        itInfrequentGB,
        itArchiveGB,
        objectCount,
      },
      trends: {
        totalSize: {
          timestamps: totalTimestamps.map((t) => t.toISOString()),
          values: totalValues,
        },
        archiveSize: {
          timestamps: totalTimestamps.map((t) => t.toISOString()),
          values: archiveValues,
        },
        objectCount: buildTrend(objectsData),
      },
    };

    setCache(cacheKey, response, CACHE_1H);
    return NextResponse.json(response);
  } catch (err) {
    console.error('Failed to fetch S3 storage data:', err);
    return NextResponse.json({ error: 'Failed to fetch S3 storage data' }, { status: 500 });
  }
});
