import type { Book, Author, Narrator, SeriesInfo } from '@/lib/types';

// Mock Authors
export const mockAuthors: Author[] = [
  {
    id: 'author-1',
    name: 'Brandon Sanderson',
    asin: 'B001TEST1',
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'author-2',
    name: 'Andy Weir',
    asin: 'B001TEST2',
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'author-3',
    name: 'J.R.R. Tolkien',
    asin: 'B001TEST3',
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'author-4',
    name: 'Multiple Authors Collaboration',
    asin: 'B001TEST4',
    createdAt: '2025-01-01T00:00:00Z',
  },
];

// Mock Narrators
export const mockNarrators: Narrator[] = [
  {
    id: 'narrator-1',
    name: 'Michael Kramer',
    asin: 'B002TEST1',
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'narrator-2',
    name: 'R.C. Bray',
    asin: 'B002TEST2',
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'narrator-3',
    name: 'Andy Serkis',
    asin: 'B002TEST3',
    createdAt: '2025-01-01T00:00:00Z',
  },
];

// Mock Series
export const mockSeriesInfo: SeriesInfo[] = [
  {
    id: 'series-1',
    title: 'The Stormlight Archive',
    asin: 'B003TEST1',
    sequence: '1',
  },
  {
    id: 'series-2',
    title: 'The Stormlight Archive',
    asin: 'B003TEST1',
    sequence: '2',
  },
  {
    id: 'series-3',
    title: 'The Lord of the Rings',
    asin: 'B003TEST3',
    sequence: '1',
  },
];

// Mock Books - Variety of use cases
export const mockBooks: Book[] = [
  // Standard book with all fields
  {
    id: 'book-1',
    asin: 'B00TEST001',
    title: 'The Way of Kings',
    publisherSummary:
      '<p>The first book in the epic Stormlight Archive series. Follow Kaladin, a former soldier turned slave, as he discovers his destiny in a world of magic and political intrigue.</p>',
    runtimeMinutes: 2760, // 46 hours
    releaseDate: '2010-08-31T00:00:00Z',
    publisher: 'Tor Books',
    coverUrl: 'https://via.placeholder.com/300x450/4A90E2/FFFFFF?text=The+Way+of+Kings',
    audioUrl: '/api/audio/the-way-of-kings.mp3',
    authors: [mockAuthors[0]],
    narrators: [mockNarrators[0]],
    series: [mockSeriesInfo[0]],
    createdAt: '2025-01-01T00:00:00Z',
  },

  // Book with very long title (test text wrapping)
  {
    id: 'book-2',
    asin: 'B00TEST002',
    title:
      'A Very Long Audiobook Title That Tests Text Wrapping Behavior in Various Component States and Layouts',
    publisherSummary: '<p>A book with an exceptionally long title to test UI edge cases.</p>',
    runtimeMinutes: 420, // 7 hours
    releaseDate: '2023-06-15T00:00:00Z',
    publisher: 'Test Publishing',
    coverUrl: 'https://via.placeholder.com/300x450/E24A90/FFFFFF?text=Long+Title',
    audioUrl: '/api/audio/long-title.mp3',
    authors: [mockAuthors[3]],
    narrators: [mockNarrators[1]],
    series: [],
    createdAt: '2025-01-02T00:00:00Z',
  },

  // Short runtime book
  {
    id: 'book-3',
    asin: 'B00TEST003',
    title: 'The Martian',
    publisherSummary:
      "<p>Six days ago, astronaut Mark Watney became one of the first people to walk on Mars. Now, he's sure he'll be the first person to die there.</p>",
    runtimeMinutes: 90, // 1.5 hours
    releaseDate: '2014-02-11T00:00:00Z',
    publisher: 'Crown Publishing',
    coverUrl: 'https://via.placeholder.com/300x450/90E24A/FFFFFF?text=The+Martian',
    audioUrl: '/api/audio/the-martian.mp3',
    authors: [mockAuthors[1]],
    narrators: [mockNarrators[1]],
    series: [],
    createdAt: '2025-01-03T00:00:00Z',
  },

  // Book with missing cover image
  {
    id: 'book-4',
    asin: 'B00TEST004',
    title: 'Book Without Cover',
    publisherSummary: '<p>This book has no cover image to test fallback behavior.</p>',
    runtimeMinutes: 540, // 9 hours
    releaseDate: '2020-01-01T00:00:00Z',
    publisher: 'Unknown Publisher',
    coverUrl: null,
    audioUrl: '/api/audio/no-cover.mp3',
    authors: [mockAuthors[2]],
    narrators: [mockNarrators[2]],
    series: [],
    createdAt: '2025-01-04T00:00:00Z',
  },

  // Book in series (middle of series)
  {
    id: 'book-5',
    asin: 'B00TEST005',
    title: 'Words of Radiance',
    publisherSummary:
      '<p>The second book in the epic Stormlight Archive series continues the story.</p>',
    runtimeMinutes: 2880, // 48 hours
    releaseDate: '2014-03-04T00:00:00Z',
    publisher: 'Tor Books',
    coverUrl: 'https://via.placeholder.com/300x450/4AE290/FFFFFF?text=Words+of+Radiance',
    audioUrl: '/api/audio/words-of-radiance.mp3',
    authors: [mockAuthors[0]],
    narrators: [mockNarrators[0]],
    series: [mockSeriesInfo[1]],
    createdAt: '2025-01-05T00:00:00Z',
  },

  // Book with minimal data (no runtime, no publisher summary)
  {
    id: 'book-6',
    asin: 'B00TEST006',
    title: 'Minimal Data Book',
    publisherSummary: null,
    runtimeMinutes: null,
    releaseDate: null,
    publisher: null,
    coverUrl: 'https://via.placeholder.com/300x450/999999/FFFFFF?text=Minimal+Data',
    audioUrl: '/api/audio/minimal.mp3',
    authors: [],
    narrators: [],
    series: [],
    createdAt: '2025-01-06T00:00:00Z',
  },

  // Book with multiple authors
  {
    id: 'book-7',
    asin: 'B00TEST007',
    title: 'Collaborative Masterpiece',
    publisherSummary: '<p>A book written by multiple authors in collaboration.</p>',
    runtimeMinutes: 720, // 12 hours
    releaseDate: '2023-09-15T00:00:00Z',
    publisher: 'Collaborative Press',
    coverUrl: 'https://via.placeholder.com/300x450/E2904A/FFFFFF?text=Multi+Author',
    audioUrl: '/api/audio/collaborative.mp3',
    authors: [mockAuthors[0], mockAuthors[1], mockAuthors[2]],
    narrators: [mockNarrators[0], mockNarrators[1]],
    series: [],
    createdAt: '2025-01-07T00:00:00Z',
  },

  // Very long runtime book
  {
    id: 'book-8',
    asin: 'B00TEST008',
    title: 'The Fellowship of the Ring',
    publisherSummary:
      '<p>The first volume in The Lord of the Rings trilogy follows Frodo Baggins as he begins his quest to destroy the One Ring.</p>',
    runtimeMinutes: 1140, // 19 hours
    releaseDate: '1954-07-29T00:00:00Z',
    publisher: 'George Allen & Unwin',
    coverUrl: 'https://via.placeholder.com/300x450/4A4AE2/FFFFFF?text=Fellowship',
    audioUrl: '/api/audio/fellowship.mp3',
    authors: [mockAuthors[2]],
    narrators: [mockNarrators[2]],
    series: [mockSeriesInfo[2]],
    createdAt: '2025-01-08T00:00:00Z',
  },
];

// Export individual books for specific story use cases
export const mockBookDefault = mockBooks[0];
export const mockBookLongTitle = mockBooks[1];
export const mockBookShortRuntime = mockBooks[2];
export const mockBookNoCover = mockBooks[3];
export const mockBookInSeries = mockBooks[4];
export const mockBookMinimalData = mockBooks[5];
export const mockBookMultipleAuthors = mockBooks[6];
export const mockBookLongRuntime = mockBooks[7];

// Helper function to generate a custom mock book
export function createMockBook(overrides: Partial<Book> = {}): Book {
  return {
    id: 'mock-book-custom',
    asin: 'B00CUSTOM',
    title: 'Custom Mock Book',
    publisherSummary: '<p>A customizable mock book for testing.</p>',
    runtimeMinutes: 600,
    releaseDate: '2025-01-01T00:00:00Z',
    publisher: 'Mock Publisher',
    coverUrl: 'https://via.placeholder.com/300x450/CCCCCC/FFFFFF?text=Custom+Book',
    audioUrl: '/api/audio/custom.mp3',
    authors: [mockAuthors[0]],
    narrators: [mockNarrators[0]],
    series: [],
    createdAt: '2025-01-01T00:00:00Z',
    ...overrides,
  };
}
