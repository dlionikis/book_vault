// Mock audio URLs and chapter data for AudioPlayer stories

export const mockAudioUrl = '/api/audio/sample-audiobook.mp3';

export const mockChapters = [
  {
    id: 'chapter-1',
    bookId: 'book-1',
    chapterNumber: 1,
    title: 'Chapter 1: The Beginning',
    startTime: 0,
    endTime: 600, // 10 minutes
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'chapter-2',
    bookId: 'book-1',
    chapterNumber: 2,
    title: 'Chapter 2: The Journey Starts',
    startTime: 600,
    endTime: 1500, // 15 minutes more
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'chapter-3',
    bookId: 'book-1',
    chapterNumber: 3,
    title: 'Chapter 3: Unexpected Encounters',
    startTime: 1500,
    endTime: 2400, // 15 minutes more
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'chapter-4',
    bookId: 'book-1',
    chapterNumber: 4,
    title: 'Chapter 4: Rising Action',
    startTime: 2400,
    endTime: 3300, // 15 minutes more
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'chapter-5',
    bookId: 'book-1',
    chapterNumber: 5,
    title: 'Chapter 5: The Climax',
    startTime: 3300,
    endTime: 4200, // 15 minutes more (70 minutes total)
    createdAt: '2025-01-01T00:00:00Z',
  },
];

export const mockChaptersShort = [
  {
    id: 'chapter-1',
    bookId: 'book-3',
    chapterNumber: 1,
    title: 'Introduction',
    startTime: 0,
    endTime: 300, // 5 minutes
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'chapter-2',
    bookId: 'book-3',
    chapterNumber: 2,
    title: 'Main Content',
    startTime: 300,
    endTime: 900, // 10 minutes more (15 minutes total)
    createdAt: '2025-01-01T00:00:00Z',
  },
];
