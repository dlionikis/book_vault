import type { Meta, StoryObj } from '@storybook/nextjs';
import ChapterList from './ChapterList';
import { mockChapters } from '@/.storybook/mocks/chapters';

const meta: Meta<typeof ChapterList> = {
  title: 'Components/ChapterList',
  component: ChapterList,
  parameters: {
    layout: 'padded',
  },
  decorators: [
    (Story, context) => {
      // Mock fetch for each story
      const originalFetch = global.fetch;

      global.fetch = async (): Promise<Response> => {
        const bookId = context.args.bookId;

        // Determine which mock data to return based on bookId
        let chapters = mockChapters.default;
        if (bookId === 'book-few') {
          chapters = mockChapters.few;
        } else if (bookId === 'book-many') {
          chapters = mockChapters.many;
        } else if (bookId === 'book-none') {
          chapters = mockChapters.empty;
        }

        return Promise.resolve({
          ok: true,
          status: 200,
          json: async () => ({ chapters }),
        } as Response);
      };

      const cleanup = () => {
        global.fetch = originalFetch;
      };

      // Render story with cleanup
      return (
        <>
          <Story />
          {typeof window !== 'undefined' && setTimeout(cleanup, 0)}
        </>
      );
    },
  ],
  tags: ['autodocs'],
  args: {
    onChapterClick: () => {
      // Action handler - Storybook will log this automatically
    },
  },
};

export default meta;
type Story = StoryObj<typeof ChapterList>;

// Story 1: Default - Standard audiobook with typical chapter structure (10 chapters)
export const Default: Story = {
  args: {
    bookId: 'book-1',
    currentTime: 0,
  },
};

// Story 2: WithProgress - Active playback showing current chapter highlighted
export const WithProgress: Story = {
  args: {
    bookId: 'book-1',
    currentTime: 6000, // In chapter 6 (middle of book)
  },
};

// Story 3: FewChapters - Short audiobook with only 3 chapters
export const FewChapters: Story = {
  args: {
    bookId: 'book-few',
    currentTime: 500, // In chapter 2
  },
};

// Story 4: ManyChapters - Long audiobook with 50 chapters (tests scrolling)
export const ManyChapters: Story = {
  args: {
    bookId: 'book-many',
    currentTime: 15000, // In chapter 26
  },
};

// Story 5: NoChapters - Audiobook without chapter information (empty state)
export const NoChapters: Story = {
  args: {
    bookId: 'book-none',
    currentTime: 0,
  },
};
