'use client';

import { useRef, useState, useEffect } from 'react';
import AudioPlayer from '@/components/AudioPlayer';
import ChapterList from '@/components/ChapterList';

interface PlaybackClientProps {
  /**
   * Optional fallback stream URL. Phase 0 fetches the URL on demand from
   * /api/books/{id}/stream; this prop is only used as a fallback if that fetch
   * fails, and will be dropped once list responses stop shipping audioUrl.
   */
  audioUrl?: string;
  title: string;
  author: string;
  bookId: string;
  coverUrl?: string;
}

export default function PlaybackClient({
  audioUrl,
  title,
  author,
  bookId,
  coverUrl,
}: PlaybackClientProps) {
  const [currentTime, setCurrentTime] = useState(0);
  const [initialPosition, setInitialPosition] = useState<number | undefined>(undefined);
  const [isLoadingProgress, setIsLoadingProgress] = useState(true);
  const [streamUrl, setStreamUrl] = useState<string | undefined>(undefined);
  const [streamError, setStreamError] = useState(false);
  // Race case: the book was available when the page rendered but got archived
  // (or a restore is already running) by the time the user hit Play. /stream
  // returns 202 and auto-initiates the restore; surface that instead of an error.
  const [restoring, setRestoring] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Fetch user's progress on mount
  useEffect(() => {
    const fetchProgress = async () => {
      try {
        const res = await fetch(`/api/progress?bookId=${bookId}`);
        if (res.ok) {
          const data = await res.json();
          setInitialPosition(data.positionSeconds);
        }
      } catch (error) {
        console.error('Error fetching progress:', error);
      } finally {
        setIsLoadingProgress(false);
      }
    };

    fetchProgress();
  }, [bookId]);

  // Fetch the on-demand stream URL (Phase 0). Falls back to the audioUrl prop
  // if the request fails, so playback keeps working during rollout.
  useEffect(() => {
    const fetchStreamUrl = async () => {
      try {
        const res = await fetch(`/api/books/${bookId}/stream`);
        if (res.status === 202) {
          // Archived → restore auto-initiated; show the restoring state.
          setRestoring(true);
          return;
        }
        if (res.ok) {
          const data = await res.json();
          if (data.status === 'available' && data.streamUrl) {
            setStreamUrl(data.streamUrl);
            return;
          }
        }
        setStreamError(true);
      } catch (error) {
        console.error('Error fetching stream URL:', error);
        setStreamError(true);
      }
    };

    fetchStreamUrl();
  }, [bookId]);

  const resolvedUrl = streamUrl ?? (streamError ? audioUrl : undefined);

  const handleChapterClick = (startTime: number) => {
    if (audioRef.current) {
      audioRef.current.currentTime = startTime;
      // If paused, start playing
      if (audioRef.current.paused) {
        audioRef.current.play();
      }
    }
  };

  const handleTimeUpdate = (time: number) => {
    setCurrentTime(time);
  };

  const handleAudioRef = (ref: HTMLAudioElement | null) => {
    audioRef.current = ref;
  };

  // Archived-since-page-load: /stream returned 202 and started a restore.
  if (restoring) {
    return (
      <div className="rounded-lg bg-white p-8 shadow-lg dark:bg-gray-800">
        <div className="flex flex-col items-center gap-3 text-center">
          <svg className="h-8 w-8 animate-spin text-blue-600" fill="none" viewBox="0 0 24 24">
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
            />
          </svg>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
            Restoring from archive…
          </h2>
          <p className="text-sm text-gray-600 dark:text-gray-400">
            This audiobook needs to be restored before it can play (about 3–5 hours). You&apos;ll
            get a notification when it&apos;s ready.
          </p>
        </div>
      </div>
    );
  }

  // Don't render player until we've loaded progress and resolved the stream URL
  if (isLoadingProgress || !resolvedUrl) {
    return (
      <div className="rounded-lg bg-white p-8 shadow-lg dark:bg-gray-800">
        <div className="flex items-center justify-center h-32">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-8">
        <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-6">Chapters</h2>
        <ChapterList
          bookId={bookId}
          currentTime={currentTime}
          onChapterClick={handleChapterClick}
        />
      </div>

      {/* Audio Player - Fixed at bottom */}
      <AudioPlayer
        audioUrl={resolvedUrl}
        title={title}
        author={author}
        bookId={bookId}
        coverUrl={coverUrl}
        initialPosition={initialPosition}
        onTimeUpdate={handleTimeUpdate}
        onAudioRef={handleAudioRef}
      />
    </>
  );
}
