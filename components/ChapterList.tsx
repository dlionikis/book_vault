'use client';

import { useEffect, useState } from 'react';
import { formatTime } from '@/lib/utils/formatTime';

interface Chapter {
  id: string;
  chapterNumber: number;
  title: string;
  startTime: number;
  endTime: number;
  duration: number;
}

interface ChapterListProps {
  bookId: string;
  currentTime?: number;
  onChapterClick: (startTime: number) => void;
}

export default function ChapterList({ bookId, currentTime = 0, onChapterClick }: ChapterListProps) {
  const [chapters, setChapters] = useState<Chapter[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchChapters() {
      try {
        const res = await fetch(`/api/books/${bookId}/chapters`);
        if (!res.ok) {
          throw new Error('Failed to fetch chapters');
        }
        const data = await res.json();
        setChapters(data.chapters || []);
      } catch (err) {
        console.error('Error fetching chapters:', err);
        setError(err instanceof Error ? err.message : 'Failed to load chapters');
      } finally {
        setLoading(false);
      }
    }

    fetchChapters();
  }, [bookId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-8 text-center text-gray-500">
        <p>{error}</p>
      </div>
    );
  }

  if (chapters.length === 0) {
    return (
      <div className="p-8 text-center text-gray-500">
        <svg
          className="w-16 h-16 mx-auto mb-4 text-gray-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
          />
        </svg>
        <p className="text-lg font-medium mb-2">No Chapters</p>
        <p className="text-sm">This audiobook doesn&apos;t have chapter information</p>
      </div>
    );
  }

  // Determine current chapter based on currentTime
  const currentChapterIndex = chapters.findIndex(
    (ch) => currentTime >= ch.startTime && currentTime < ch.endTime
  );

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">Chapters ({chapters.length})</h3>
      </div>

      <div className="space-y-1 max-h-[600px] overflow-y-auto">
        {chapters.map((chapter, index) => {
          const isCurrentChapter = index === currentChapterIndex;

          return (
            <button
              key={chapter.id}
              onClick={() => onChapterClick(chapter.startTime)}
              className={`w-full text-left p-3 rounded-lg transition-colors ${
                isCurrentChapter
                  ? 'bg-blue-50 border-2 border-blue-500'
                  : 'bg-gray-50 hover:bg-gray-100 border-2 border-transparent'
              }`}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span
                      className={`text-xs font-medium px-2 py-0.5 rounded ${
                        isCurrentChapter ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700'
                      }`}
                    >
                      {chapter.chapterNumber}
                    </span>
                    {isCurrentChapter && (
                      <span className="flex items-center gap-1 text-xs text-blue-600 font-medium">
                        <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                          <path
                            fillRule="evenodd"
                            d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                            clipRule="evenodd"
                          />
                        </svg>
                        Playing
                      </span>
                    )}
                  </div>
                  <p
                    className={`text-sm font-medium truncate ${
                      isCurrentChapter ? 'text-blue-900' : 'text-gray-900'
                    }`}
                  >
                    {chapter.title}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-1 flex-shrink-0">
                  <span className="text-xs text-gray-500">{formatTime(chapter.startTime)}</span>
                  <span className="text-xs text-gray-400">{formatTime(chapter.duration)}</span>
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
