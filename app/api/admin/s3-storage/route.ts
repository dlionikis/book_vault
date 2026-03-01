import { NextRequest, NextResponse } from 'next/server';
import { CloudWatchClient, GetMetricDataCommand } from '@aws-sdk/client-cloudwatch';
import { requireAdmin } from '@/lib/admin-auth';
import { getCached, setCache, CACHE_1H } from '@/lib/admin-cache';
import { withLogging } from '@/lib/logger';

const client = new CloudWatchClient({ region: process.env.AWS_REGION || 'us-east-1' });
const BUCKET = process.env.AWS_S3_BUCKET || 'book-vault-media';

const STORAGE_TYPES = [
  { id: 'standard', type: 'StandardStorage', label: 'S3 Standard' },
  { id: 'it_fa', type: 'IntelligentTieringFAStorage', label: 'Intelligent-Tiering (Frequent)' },
  { id: 'it_ia', type: 'IntelligentTieringIAStorage', label: 'Intelligent-Tiering (Infrequent)' },
  { id: 'it_aa', type: 'IntelligentTieringAAStorage', label: 'Intelligent-Tiering (Archive)' },
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
  const { error } = await requireAdmin(request);
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

    // Find the most recent value by timestamp (CloudWatch doesn't guarantee order)
    const latestVal = (data: typeof standardData) => {
      if (!data?.Values?.length || !data?.Timestamps?.length) return 0;
      let latestIdx = 0;
      for (let i = 1; i < data.Timestamps.length; i++) {
        if (data.Timestamps[i] > data.Timestamps[latestIdx]) latestIdx = i;
      }
      return data.Values[latestIdx];
    };

    const standardGB = bytesToGB(latestVal(standardData));
    const itFrequentGB = bytesToGB(latestVal(itFaData));
    const itInfrequentGB = bytesToGB(latestVal(itIaData));
    const itArchiveGB = bytesToGB(latestVal(itAaData));
    const objectCount = Math.round(latestVal(objectsData));

    const buildTrend = (data: typeof standardData): StorageTrend => ({
      timestamps: (data?.Timestamps || []).map((t) => t.toISOString()),
      values: data?.Values || [],
    });

    // Build timestamp-aligned maps for trend computation
    const buildTsMap = (data: typeof standardData) => {
      const map = new Map<string, number>();
      if (data?.Timestamps && data?.Values) {
        data.Timestamps.forEach((ts, i) => map.set(ts.toISOString(), data.Values![i]));
      }
      return map;
    };

    const standardMap = buildTsMap(standardData);
    const itFaMap = buildTsMap(itFaData);
    const itIaMap = buildTsMap(itIaData);
    const itAaMap = buildTsMap(itAaData);

    // Collect all unique timestamps across metrics, sorted chronologically
    const allTimestampSet = new Set<string>();
    [standardMap, itFaMap, itIaMap, itAaMap].forEach((m) =>
      m.forEach((_, key) => allTimestampSet.add(key))
    );
    const totalTimestamps = [...allTimestampSet].sort();

    const totalValues = totalTimestamps.map((ts) => {
      const sum =
        (standardMap.get(ts) || 0) +
        (itFaMap.get(ts) || 0) +
        (itIaMap.get(ts) || 0) +
        (itAaMap.get(ts) || 0);
      return bytesToGB(sum);
    });

    const archiveValues = totalTimestamps.map((ts) => {
      const sum = (itIaMap.get(ts) || 0) + (itAaMap.get(ts) || 0);
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
          timestamps: totalTimestamps,
          values: totalValues,
        },
        archiveSize: {
          timestamps: totalTimestamps,
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
