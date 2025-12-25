import type { Meta, StoryObj } from '@storybook/nextjs';
import BookGrid from './BookGrid';
import {
  mockBooks,
  mockBookDefault,
  mockBookLongTitle,
  mockBookShortRuntime,
  mockBookNoCover,
} from '@/.storybook/mocks/books';

const meta: Meta<typeof BookGrid> = {
  title: 'Components/BookGrid',
  component: BookGrid,
  parameters: {
    layout: 'padded',
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof BookGrid>;

export const Grid: Story = {
  args: {
    books: mockBooks,
  },
};

export const SingleRow: Story = {
  args: {
    books: [mockBookDefault, mockBookLongTitle, mockBookShortRuntime, mockBookNoCover],
  },
};

export const LargeGrid: Story = {
  args: {
    books: [...mockBooks, ...mockBooks, ...mockBooks],
  },
};

export const Empty: Story = {
  args: {
    books: [],
  },
};

export const Loading: Story = {
  args: {
    books: [],
    loading: true,
  },
};
