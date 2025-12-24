import type { Meta, StoryObj } from '@storybook/nextjs';
import BookCard from './BookCard';
import {
  mockBookDefault,
  mockBookLongTitle,
  mockBookShortRuntime,
  mockBookNoCover,
  mockBookInSeries,
  mockBookMinimalData,
  mockBookMultipleAuthors,
} from '@/.storybook/mocks/books';

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
    book: mockBookDefault,
  },
};

export const LongTitle: Story = {
  args: {
    book: mockBookLongTitle,
  },
};

export const InSeries: Story = {
  args: {
    book: mockBookInSeries,
  },
};

export const MultipleAuthors: Story = {
  args: {
    book: mockBookMultipleAuthors,
  },
};

export const NoCover: Story = {
  args: {
    book: mockBookNoCover,
  },
};

export const ShortRuntime: Story = {
  args: {
    book: mockBookShortRuntime,
  },
};

export const MinimalData: Story = {
  args: {
    book: mockBookMinimalData,
  },
};
