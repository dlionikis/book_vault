'use client';

import { useState } from 'react';

interface ProgressBadgeProps {
  bookId: string;
  initialProgress: {
    positionSeconds: number;
    completed: boolean;
    totalSeconds?: number;
  };
  onProgressUpdate?: () => void;
}

export default function ProgressBadge({
  bookId,
  initialProgress,
  onProgressUpdate,
}: ProgressBadgeProps) {
  const [progress, setProgress] = useState(initialProgress);
  const [isUpdating, setIsUpdating] = useState(false);

  const getProgressStatus = () => {
    if (progress.completed) return 'completed';
    if (progress.positionSeconds > 0) return 'in-progress';
    return 'not-started';
  };

  const getProgressPercentage = () => {
    if (!progress.totalSeconds || progress.totalSeconds === 0) return 0;
    return Math.min(100, Math.round((progress.positionSeconds / progress.totalSeconds) * 100));
  };

  const handleMarkAs = async (status: 'completed' | 'not-started') => {
    setIsUpdating(true);
    try {
      const res = await fetch('/api/progress', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bookId, status }),
      });

      if (res.ok) {
        const data = await res.json();
        setProgress({
          positionSeconds: data.positionSeconds,
          completed: data.completed,
          totalSeconds: progress.totalSeconds,
        });
        onProgressUpdate?.();
      }
    } catch (error) {
      console.error('Error updating progress:', error);
    } finally {
      setIsUpdating(false);
    }
  };

  const status = getProgressStatus();
  const percentage = getProgressPercentage();

  return (
    <div className="space-y-2">
      {/* Progress Badge */}
      <div className="flex items-center gap-2">
        {status === 'completed' && (
          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
            <svg className="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path
                fillRule="evenodd"
                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                clipRule="evenodd"
              />
            </svg>
            Finished
          </span>
        )}
        {status === 'in-progress' && (
          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
            <svg className="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path
                fillRule="evenodd"
                d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                clipRule="evenodd"
              />
            </svg>
            {percentage}% Complete
          </span>
        )}
        {status === 'not-started' && (
          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300">
            Not Started
          </span>
        )}

        {/* Dropdown Menu */}
        <div className="relative group">
          <button
            className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            disabled={isUpdating}
          >
            <svg
              className="w-4 h-4 text-gray-500 dark:text-gray-400"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
            </svg>
          </button>

          {/* Dropdown Menu */}
          <div className="absolute right-0 mt-1 w-48 bg-white dark:bg-gray-800 rounded-md shadow-lg border border-gray-200 dark:border-gray-700 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-10">
            <div className="py-1">
              {status !== 'completed' && (
                <button
                  onClick={() => handleMarkAs('completed')}
                  disabled={isUpdating}
                  className="block w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 disabled:opacity-50"
                >
                  <svg className="w-4 h-4 inline mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fillRule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clipRule="evenodd"
                    />
                  </svg>
                  Mark as Finished
                </button>
              )}
              {status !== 'not-started' && (
                <button
                  onClick={() => handleMarkAs('not-started')}
                  disabled={isUpdating}
                  className="block w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 disabled:opacity-50"
                >
                  <svg className="w-4 h-4 inline mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fillRule="evenodd"
                      d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z"
                      clipRule="evenodd"
                    />
                  </svg>
                  Reset to Not Started
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Progress Bar (only for in-progress) */}
      {status === 'in-progress' && progress.totalSeconds && (
        <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
          <div
            className="bg-blue-600 h-1.5 rounded-full transition-all"
            style={{ width: `${percentage}%` }}
          />
        </div>
      )}
    </div>
  );
}
