'use client';

import { useState } from 'react';

interface ProgressStatusProps {
  bookId: string;
  initialProgress: {
    positionSeconds: number;
    completed: boolean;
    totalSeconds?: number;
  };
}

export default function ProgressStatus({ bookId, initialProgress }: ProgressStatusProps) {
  const [progress] = useState(initialProgress);

  const getProgressStatus = () => {
    if (progress.completed) return 'completed';
    if (progress.positionSeconds > 0) return 'in-progress';
    return 'not-started';
  };

  const getProgressPercentage = () => {
    if (!progress.totalSeconds || progress.totalSeconds === 0) return 0;
    return Math.min(100, Math.round((progress.positionSeconds / progress.totalSeconds) * 100));
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
