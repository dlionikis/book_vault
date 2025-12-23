'use client';

import { useRef, useState } from 'react';
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
  const audioRef = useRef<HTMLAudioElement | null>(null);

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
        onTimeUpdate={handleTimeUpdate}
        onAudioRef={handleAudioRef}
      />
    </>
  );
}
