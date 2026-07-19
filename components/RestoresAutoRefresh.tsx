'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

/**
 * Refreshes the (server-rendered) restores page every 60s while any restore is
 * still in progress, so completed restores move to "Recently restored" without
 * a manual reload. Renders nothing.
 */
export default function RestoresAutoRefresh({ activeCount }: { activeCount: number }) {
  const router = useRouter();

  useEffect(() => {
    if (activeCount === 0) return;
    const interval = setInterval(() => router.refresh(), 60_000);
    return () => clearInterval(interval);
  }, [activeCount, router]);

  return null;
}
