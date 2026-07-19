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

  // Don't render player until we've loaded progress and resolved the stream URL
  if (isLoadingProgress || !resolvedUrl) {
    return (
      <div className="bg-white rounded-lg shadow-lg p-8">
        <div className="flex items-center justify-center h-32">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="bg-white rounded-lg shadow-lg p-8">
        <h2 className="text-xl font-bold text-gray-900 mb-6">Chapters</h2>
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
