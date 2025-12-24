import type { Meta, StoryObj } from '@storybook/nextjs';
import BookCard from './BookCard';

const meta: Meta<typeof BookCard> = {
  title: 'Components/BookCard',
  component: BookCard,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
  decorators: [
    (Story) => (
      <div className="w-80">
        <Story />
      </div>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof BookCard>;

export const Default: Story = {
  args: {
    book: {
      id: '1',
      asin: 'B001',
      title: 'The Name of the Wind',
      coverUrl: 'https://via.placeholder.com/300x450/4A5568/FFFFFF?text=Book+Cover',
      audioUrl: '/api/audio/sample.mp3',
      authors: [{ id: '1', name: 'Patrick Rothfuss' }],
      narrators: [{ id: '1', name: 'Nick Podehl' }],
      series: [],
      runtimeMinutes: 990,
      createdAt: '2024-01-01',
    },
  },
};

export const LongTitle: Story = {
  args: {
    book: {
      id: '2',
      asin: 'B002',
      title:
        'A Very Long Audiobook Title That Tests Text Wrapping Behavior And Line Clamping With Multiple Lines',
      coverUrl: 'https://via.placeholder.com/300x450/6366F1/FFFFFF?text=Long+Title',
      audioUrl: '/api/audio/sample.mp3',
      authors: [{ id: '1', name: 'Author Name' }],
      narrators: [{ id: '1', name: 'Narrator Name' }],
      series: [],
      runtimeMinutes: 120,
      createdAt: '2024-01-01',
    },
  },
};

export const WithSeries: Story = {
  args: {
    book: {
      id: '3',
      asin: 'B003',
      title: "The Wise Man's Fear",
      coverUrl: 'https://via.placeholder.com/300x450/10B981/FFFFFF?text=Series+Book',
      audioUrl: '/api/audio/sample.mp3',
      authors: [{ id: '1', name: 'Patrick Rothfuss' }],
      narrators: [{ id: '1', name: 'Nick Podehl' }],
      series: [
        {
          id: 's1',
          title: 'The Kingkiller Chronicle',
          sequence: '2',
        },
      ],
      runtimeMinutes: 1230,
      createdAt: '2024-01-01',
    },
  },
};

export const MultipleAuthorsAndNarrators: Story = {
  args: {
    book: {
      id: '4',
      asin: 'B004',
      title: 'Good Omens',
      coverUrl: 'https://via.placeholder.com/300x450/F59E0B/FFFFFF?text=Multiple+Authors',
      audioUrl: '/api/audio/sample.mp3',
      authors: [
        { id: '1', name: 'Terry Pratchett' },
        { id: '2', name: 'Neil Gaiman' },
      ],
      narrators: [
        { id: '1', name: 'Martin Jarvis' },
        { id: '2', name: 'Stephen Briggs' },
      ],
      series: [],
      runtimeMinutes: 720,
      createdAt: '2024-01-01',
    },
  },
};

export const NoCover: Story = {
  args: {
    book: {
      id: '5',
      asin: 'B005',
      title: 'Audiobook Without Cover',
      coverUrl: null,
      audioUrl: '/api/audio/sample.mp3',
      authors: [{ id: '1', name: 'Unknown Author' }],
      narrators: [{ id: '1', name: 'Unknown Narrator' }],
      series: [],
      runtimeMinutes: 300,
      createdAt: '2024-01-01',
    },
  },
};

export const ShortRuntime: Story = {
  args: {
    book: {
      id: '6',
      asin: 'B006',
      title: 'Short Story Collection',
      coverUrl: 'https://via.placeholder.com/300x450/EF4444/FFFFFF?text=Short',
      audioUrl: '/api/audio/sample.mp3',
      authors: [{ id: '1', name: 'Various Authors' }],
      narrators: [{ id: '1', name: 'Various Narrators' }],
      series: [],
      runtimeMinutes: 45,
      createdAt: '2024-01-01',
    },
  },
};
