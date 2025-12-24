import type { Meta, StoryObj } from '@storybook/nextjs';
import { ThemeToggle } from './ThemeToggle';

const meta: Meta<typeof ThemeToggle> = {
  title: 'Components/ThemeToggle',
  component: ThemeToggle,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
};

export default meta;
type Story = StoryObj<typeof ThemeToggle>;

export const Default: Story = {};

export const InHeader: Story = {
  decorators: [
    (Story) => (
      <div className="flex items-center gap-4 p-4 bg-white dark:bg-gray-800 rounded-lg shadow-lg">
        <span className="text-gray-900 dark:text-white font-medium">App Settings</span>
        <Story />
      </div>
    ),
  ],
};

export const InNavigation: Story = {
  decorators: [
    (Story) => (
      <nav className="flex items-center justify-between p-4 bg-gray-100 dark:bg-gray-900">
        <div className="text-xl font-bold text-gray-900 dark:text-white">Book Vault</div>
        <div className="flex items-center gap-4">
          <button className="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400">
            Search
          </button>
          <button className="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400">
            Library
          </button>
          <Story />
        </div>
      </nav>
    ),
  ],
};
