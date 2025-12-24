import type { Meta, StoryObj } from '@storybook/nextjs';
import Pagination from './Pagination';

const meta: Meta<typeof Pagination> = {
  title: 'Components/Pagination',
  component: Pagination,
  parameters: {
    layout: 'padded',
    nextjs: {
      appDirectory: true,
    },
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof Pagination>;

export const FirstPage: Story = {
  args: {
    currentPage: 1,
    totalPages: 10,
    total: 250,
    itemName: 'books',
  },
};

export const MiddlePage: Story = {
  args: {
    currentPage: 5,
    totalPages: 10,
    total: 250,
    itemName: 'books',
  },
};

export const LastPage: Story = {
  args: {
    currentPage: 10,
    totalPages: 10,
    total: 250,
    itemName: 'books',
  },
};

export const FewPages: Story = {
  args: {
    currentPage: 2,
    totalPages: 5,
    total: 125,
    itemName: 'books',
  },
};

export const ManyPages: Story = {
  args: {
    currentPage: 42,
    totalPages: 100,
    total: 2500,
    itemName: 'audiobooks',
  },
};

export const LargeDataset: Story = {
  args: {
    currentPage: 150,
    totalPages: 500,
    total: 12500,
    itemName: 'items',
  },
};

export const NearBeginning: Story = {
  args: {
    currentPage: 2,
    totalPages: 50,
    total: 1250,
    itemName: 'books',
  },
};

export const NearEnd: Story = {
  args: {
    currentPage: 49,
    totalPages: 50,
    total: 1250,
    itemName: 'books',
  },
};
