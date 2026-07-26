import type { Meta, StoryObj } from '@storybook/nextjs';
import ViewModeToggle from './ViewModeToggle';

const meta: Meta<typeof ViewModeToggle> = {
  title: 'Components/ViewModeToggle',
  component: ViewModeToggle,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof ViewModeToggle>;

export const BooksActive: Story = {
  args: {
    mode: 'books',
  },
};

export const SeriesActive: Story = {
  args: {
    mode: 'series',
  },
};
