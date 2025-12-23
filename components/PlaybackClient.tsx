'use client';

import { useRef, useState, useEffect } from 'react';
import AudioPlayer from '@/components/AudioPlayer';
import ChapterList from '@/components/ChapterList';

interface PlaybackClientProps {
  audioUrl: string;
  title: string;
  author: string;
  bookId: string;
}

export default function PlaybackClient({ audioUrl, title, author, bookId }: PlaybackClientProps) {
  const [currentTime, setCurrentTime] = useState(0);
  const [initialPosition, setInitialPosition] = useState<number | undefined>(undefined);
  const [isLoadingProgress, setIsLoadingProgress] = useState(true);
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

  // Don't render player until we've loaded progress
  if (isLoadingProgress) {
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
        audioUrl={audioUrl}
        title={title}
        author={author}
        bookId={bookId}
        initialPosition={initialPosition}
        onTimeUpdate={handleTimeUpdate}
        onAudioRef={handleAudioRef}
      />
    </>
  );
}
