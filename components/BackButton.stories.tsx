import type { Meta, StoryObj } from '@storybook/nextjs';
import BackButton from './BackButton';

const meta: Meta<typeof BackButton> = {
  title: 'Components/BackButton',
  component: BackButton,
  parameters: {
    layout: 'centered',
    nextjs: {
      appDirectory: true,
      navigation: {
        pathname: '/books/123',
      },
    },
  },
  tags: ['autodocs'],
  decorators: [
    (Story) => (
      <div className="w-80 p-4">
        <Story />
      </div>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof BackButton>;

export const Default: Story = {};

export const Dark: Story = {
  parameters: {
    backgrounds: { default: 'dark' },
  },
  decorators: [
    (Story) => (
      <div className="w-80 p-4 dark">
        <Story />
      </div>
    ),
  ],
};

export const Light: Story = {
  parameters: {
    backgrounds: { default: 'light' },
  },
};

export const InContext: Story = {
  decorators: [
    (Story) => (
      <div className="max-w-4xl mx-auto p-8">
        <Story />
        <div className="mt-4 p-6 bg-gray-100 rounded-lg">
          <h1 className="text-2xl font-bold mb-4">Page Content</h1>
          <p className="text-gray-700">
            This story shows the BackButton in a typical page context with surrounding content.
          </p>
        </div>
      </div>
    ),
  ],
};
