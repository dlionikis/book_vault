// Mock chapter data for ChapterList and AudioPlayer stories

interface Chapter {
  id: string;
  chapterNumber: number;
  title: string;
  startTime: number;
  endTime: number;
  duration: number;
}

// Helper to calculate duration
function createChapter(
  id: string,
  chapterNumber: number,
  title: string,
  startTime: number,
  endTime: number
): Chapter {
  return {
    id,
    chapterNumber,
    title,
    startTime,
    endTime,
    duration: endTime - startTime,
  };
}

// Standard audiobook with typical chapter structure
export const mockChaptersDefault: Chapter[] = [
  createChapter('chapter-1', 1, 'Prologue: The Storm', 0, 720), // 12 min
  createChapter('chapter-2', 2, 'Cenn', 720, 1980), // 21 min
  createChapter('chapter-3', 3, 'Kaladin', 1980, 3540), // 26 min
  createChapter('chapter-4', 4, 'Shallan', 3540, 4980), // 24 min
  createChapter('chapter-5', 5, 'Szeth', 4980, 6300), // 22 min
  createChapter('chapter-6', 6, 'The Way of Kings', 6300, 8040), // 29 min
  createChapter('chapter-7', 7, 'Bridge Four', 8040, 9360), // 22 min
  createChapter('chapter-8', 8, 'Dunny', 9360, 10500), // 19 min
  createChapter('chapter-9', 9, 'Honor Is Dead', 10500, 12000), // 25 min
  createChapter('chapter-10', 10, 'Kaladin Stormblessed', 12000, 13620), // 27 min
];

// Few chapters (short audiobook or novella)
export const mockChaptersFew: Chapter[] = [
  createChapter('chapter-1', 1, 'Introduction', 0, 420), // 7 min
  createChapter('chapter-2', 2, 'The Discovery', 420, 1260), // 14 min
  createChapter('chapter-3', 3, 'The Resolution', 1260, 2100), // 14 min
];

// Many chapters (long audiobook with short chapters)
export const mockChaptersMany: Chapter[] = Array.from({ length: 50 }, (_, i) => {
  const chapterNumber = i + 1;
  const startTime = i * 600; // 10 minutes per chapter
  const endTime = startTime + 600;
  return createChapter(
    `chapter-${chapterNumber}`,
    chapterNumber,
    `Chapter ${chapterNumber}: Part ${Math.floor(i / 10) + 1}`,
    startTime,
    endTime
  );
});

// No chapters (for testing empty state)
export const mockChaptersEmpty: Chapter[] = [];

// Chapters with current progress at different points
export const mockChaptersWithProgress = {
  chapters: mockChaptersDefault,
  // Helper positions for different scenarios
  atBeginning: 0, // In chapter 1
  atMiddle: 6000, // In chapter 6 (middle of book)
  atEnd: 12000, // In chapter 10 (last chapter)
  betweenChapters: 720, // Exactly at chapter 2 start
};

// Chapters with varied titles (testing UI edge cases)
export const mockChaptersVariedTitles: Chapter[] = [
  createChapter('chapter-1', 1, 'A', 0, 300), // Single letter
  createChapter(
    'chapter-2',
    2,
    'This Is An Extremely Long Chapter Title That Tests Text Truncation and Wrapping Behavior in the UI',
    300,
    900
  ),
  createChapter('chapter-3', 3, 'Chapter with "Quotes" and Special Characters!', 900, 1500),
  createChapter('chapter-4', 4, 'Epilogue', 1500, 1800),
];

// Export all mock data
export const mockChapters = {
  default: mockChaptersDefault,
  few: mockChaptersFew,
  many: mockChaptersMany,
  empty: mockChaptersEmpty,
  withProgress: mockChaptersWithProgress,
  variedTitles: mockChaptersVariedTitles,
};
