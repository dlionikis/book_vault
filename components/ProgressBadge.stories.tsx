import type { Meta, StoryObj } from '@storybook/nextjs';
import ProgressBadge from './ProgressBadge';

const meta: Meta<typeof ProgressBadge> = {
  title: 'Components/ProgressBadge',
  component: ProgressBadge,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof ProgressBadge>;

export const NotStarted: Story = {
  args: {
    bookId: '1',
    initialProgress: {
      positionSeconds: 0,
      completed: false,
      totalSeconds: 3600,
    },
  },
};

export const InProgress25Percent: Story = {
  args: {
    bookId: '2',
    initialProgress: {
      positionSeconds: 900,
      completed: false,
      totalSeconds: 3600,
    },
  },
};

export const InProgress50Percent: Story = {
  args: {
    bookId: '3',
    initialProgress: {
      positionSeconds: 1800,
      completed: false,
      totalSeconds: 3600,
    },
  },
};

export const InProgress75Percent: Story = {
  args: {
    bookId: '4',
    initialProgress: {
      positionSeconds: 2700,
      completed: false,
      totalSeconds: 3600,
    },
  },
};

export const Completed: Story = {
  args: {
    bookId: '5',
    initialProgress: {
      positionSeconds: 3600,
      completed: true,
      totalSeconds: 3600,
    },
  },
};

export const InProgressNoTotal: Story = {
  args: {
    bookId: '6',
    initialProgress: {
      positionSeconds: 1800,
      completed: false,
    },
  },
};

export const LongBook: Story = {
  args: {
    bookId: '7',
    initialProgress: {
      positionSeconds: 18000,
      completed: false,
      totalSeconds: 36000,
    },
  },
};

export const AlmostComplete: Story = {
  args: {
    bookId: '8',
    initialProgress: {
      positionSeconds: 3540,
      completed: false,
      totalSeconds: 3600,
    },
  },
};
