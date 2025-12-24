// Mock user data for Storybook stories
// Note: These are client-safe mock objects without password hashes

export interface MockUser {
  id: string;
  email: string;
  name?: string | null;
  createdAt: string;
}

export interface MockUserProgress {
  id: string;
  userId: string;
  bookId: string;
  positionSeconds: number;
  completed: boolean;
  lastPlayed: string;
}

export interface MockUserList {
  id: string;
  userId: string;
  name: string;
  description?: string | null;
  bookIds: string[];
  createdAt: string;
}

// Mock Users
export const mockUsers: MockUser[] = [
  {
    id: 'user-1',
    email: 'test@example.com',
    name: 'Test User',
    createdAt: '2025-01-01T00:00:00Z',
  },
  {
    id: 'user-2',
    email: 'listener@example.com',
    name: 'Avid Listener',
    createdAt: '2025-01-05T00:00:00Z',
  },
  {
    id: 'user-3',
    email: 'newuser@example.com',
    name: null,
    createdAt: '2025-12-20T00:00:00Z',
  },
];

// Mock User Progress (for testing progress indicators)
export const mockUserProgress: MockUserProgress[] = [
  // Just started listening
  {
    id: 'progress-1',
    userId: 'user-1',
    bookId: 'book-1',
    positionSeconds: 300, // 5 minutes in
    completed: false,
    lastPlayed: '2025-12-24T10:00:00Z',
  },
  // Halfway through
  {
    id: 'progress-2',
    userId: 'user-1',
    bookId: 'book-2',
    positionSeconds: 12600, // 3.5 hours (50% of 7 hour book)
    completed: false,
    lastPlayed: '2025-12-23T15:30:00Z',
  },
  // Nearly complete
  {
    id: 'progress-3',
    userId: 'user-1',
    bookId: 'book-3',
    positionSeconds: 5100, // 85 minutes (95% of 90 minute book)
    completed: false,
    lastPlayed: '2025-12-22T08:45:00Z',
  },
  // Completed
  {
    id: 'progress-4',
    userId: 'user-1',
    bookId: 'book-5',
    positionSeconds: 172800, // Full 48 hours
    completed: true,
    lastPlayed: '2025-12-20T22:15:00Z',
  },
  // Just completed (edge case: position at end, marked complete)
  {
    id: 'progress-5',
    userId: 'user-1',
    bookId: 'book-8',
    positionSeconds: 68400, // Full 19 hours
    completed: true,
    lastPlayed: '2025-12-24T12:00:00Z',
  },
  // Multiple users on same book (different progress)
  {
    id: 'progress-6',
    userId: 'user-2',
    bookId: 'book-1',
    positionSeconds: 50000, // Much further along than user-1
    completed: false,
    lastPlayed: '2025-12-23T20:00:00Z',
  },
];

// Mock User Lists (for future library/list features)
export const mockUserLists: MockUserList[] = [
  {
    id: 'list-1',
    userId: 'user-1',
    name: 'Currently Reading',
    description: 'Books I am actively listening to',
    bookIds: ['book-1', 'book-2', 'book-3'],
    createdAt: '2025-01-10T00:00:00Z',
  },
  {
    id: 'list-2',
    userId: 'user-1',
    name: 'Want to Read',
    description: 'Books on my wishlist',
    bookIds: ['book-6', 'book-7'],
    createdAt: '2025-02-01T00:00:00Z',
  },
  {
    id: 'list-3',
    userId: 'user-1',
    name: 'Favorites',
    description: null,
    bookIds: ['book-5', 'book-8'],
    createdAt: '2025-03-15T00:00:00Z',
  },
  {
    id: 'list-4',
    userId: 'user-2',
    name: 'Fantasy Collection',
    description: 'All my favorite fantasy audiobooks',
    bookIds: ['book-1', 'book-5', 'book-8'],
    createdAt: '2025-01-20T00:00:00Z',
  },
];

// Export default user for most stories
export const mockUserDefault = mockUsers[0];

// Helper function to get progress for a specific user/book combination
export function getMockProgress(userId: string, bookId: string): MockUserProgress | undefined {
  return mockUserProgress.find((p) => p.userId === userId && p.bookId === bookId);
}

// Helper function to calculate progress percentage
export function calculateProgressPercentage(positionSeconds: number, totalSeconds: number): number {
  if (totalSeconds === 0) return 0;
  return Math.min(100, Math.round((positionSeconds / totalSeconds) * 100));
}

// Helper function to get user's lists
export function getUserLists(userId: string): MockUserList[] {
  return mockUserLists.filter((list) => list.userId === userId);
}

// Helper function to check if book is in user's list
export function isBookInList(listId: string, bookId: string): boolean {
  const list = mockUserLists.find((l) => l.id === listId);
  return list?.bookIds.includes(bookId) ?? false;
}
