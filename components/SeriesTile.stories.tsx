import type { Meta, StoryObj } from '@storybook/nextjs';
import SeriesTile from './SeriesTile';

const meta: Meta<typeof SeriesTile> = {
  title: 'Components/SeriesTile',
  component: SeriesTile,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof SeriesTile>;

export const Default: Story = {
  args: {
    series: {
      id: 'series-1',
      title: 'The Kingkiller Chronicle',
      asin: 'B002BMAYSQ',
      bookCount: 3,
      coverUrl: 'https://m.media-amazon.com/images/I/51ZQ5aQZqPL._SL500_.jpg',
    },
  },
};

export const NoCover: Story = {
  args: {
    series: {
      id: 'series-2',
      title: 'A Series With No Derived Cover Art',
      bookCount: 5,
      coverUrl: null,
    },
  },
};

export const SingleBook: Story = {
  args: {
    series: {
      id: 'series-3',
      title: 'A One-Book Series',
      bookCount: 1,
      coverUrl: null,
    },
  },
};

export const PartiallyOwned: Story = {
  args: {
    series: {
      id: 'series-4',
      title: 'The Expanse',
      bookCount: 9,
      ownedCount: 3,
      coverUrl: null,
    },
  },
};

export const FullyOwned: Story = {
  args: {
    series: {
      id: 'series-5',
      title: 'The Expanse',
      bookCount: 9,
      ownedCount: 9,
      coverUrl: null,
    },
  },
};

export const LongTitle: Story = {
  args: {
    series: {
      id: 'series-6',
      title:
        'An Extraordinarily Long Series Title That Should Be Clamped To Two Lines In The Tile Layout',
      bookCount: 12,
      coverUrl: null,
    },
  },
};
