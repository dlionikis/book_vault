import type { Meta, StoryObj } from '@storybook/nextjs';
import AudioPlayer from './AudioPlayer';
import { mockAudioUrl } from '@/.storybook/mocks/audio';

const meta: Meta<typeof AudioPlayer> = {
  title: 'Components/AudioPlayer',
  component: AudioPlayer,
  parameters: {
    layout: 'fullscreen',
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof AudioPlayer>;

// Story 1: Default - Playing state at beginning
export const Default: Story = {
  args: {
    audioUrl: mockAudioUrl,
    title: 'The Way of Kings',
    author: 'Brandon Sanderson',
    bookId: 'book-1',
    coverUrl: 'https://via.placeholder.com/300x450/4A90E2/FFFFFF?text=The+Way+of+Kings',
    initialPosition: 0,
  },
};

// Story 2: Paused - Audio player in paused state mid-playback
export const Paused: Story = {
  args: {
    audioUrl: mockAudioUrl,
    title: 'The Way of Kings',
    author: 'Brandon Sanderson',
    bookId: 'book-1',
    coverUrl: 'https://via.placeholder.com/300x450/4A90E2/FFFFFF?text=The+Way+of+Kings',
    initialPosition: 1800, // 30 minutes in
  },
};

// Story 3: Loading - Player at initial state (0 position)
export const Loading: Story = {
  args: {
    audioUrl: mockAudioUrl,
    title: 'Loading Audiobook...',
    author: 'Please wait',
    bookId: 'book-loading',
    coverUrl: undefined,
    initialPosition: 0,
  },
};

// Story 4: WithChapters - Simulates a book with chapter navigation
export const WithChapters: Story = {
  args: {
    audioUrl: mockAudioUrl,
    title: 'The Way of Kings',
    author: 'Brandon Sanderson',
    bookId: 'book-1',
    coverUrl: 'https://via.placeholder.com/300x450/4A90E2/FFFFFF?text=The+Way+of+Kings',
    initialPosition: 600, // Start of Chapter 2
  },
};

// Story 5: WithoutChapters - Book with no chapter data
export const WithoutChapters: Story = {
  args: {
    audioUrl: mockAudioUrl,
    title: 'Book Without Chapters',
    author: 'Unknown Author',
    bookId: 'book-no-chapters',
    coverUrl: null,
    initialPosition: 0,
  },
};

// Story 6: NearEnd - Audio near completion
export const NearEnd: Story = {
  args: {
    audioUrl: mockAudioUrl,
    title: 'The Martian',
    author: 'Andy Weir',
    bookId: 'book-3',
    coverUrl: 'https://via.placeholder.com/300x450/90E24A/FFFFFF?text=The+Martian',
    initialPosition: 5100, // Near end (85 minutes into 90-minute book)
  },
};

// Story 7: Error - Simulates error state with missing/invalid audio
export const Error: Story = {
  args: {
    audioUrl: '/api/audio/non-existent-file.mp3',
    title: 'Error Loading Audio',
    author: 'Test Author',
    bookId: 'book-error',
    coverUrl: 'https://via.placeholder.com/300x450/E24A90/FFFFFF?text=Error',
    initialPosition: 0,
  },
};
