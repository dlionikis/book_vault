import type { Meta, StoryObj } from '@storybook/nextjs';
// Test @/ alias import
import type { Book } from '@/lib/types';

// Simple test component to verify alias works
function AliasTestComponent() {
  const testBook: Partial<Book> = {
    title: 'Test Book',
    id: 'test-1',
  };

  return (
    <div className="p-4 bg-white dark:bg-gray-800 rounded-lg">
      <h2 className="text-xl font-bold text-gray-900 dark:text-white">Alias Test Component</h2>
      <p className="text-gray-600 dark:text-gray-300">
        If you can see this, the @/ alias is working!
      </p>
      <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
        Test book title: {testBook.title}
      </p>
    </div>
  );
}

const meta: Meta<typeof AliasTestComponent> = {
  title: 'Test/AliasTest',
  component: AliasTestComponent,
  parameters: {
    layout: 'centered',
  },
};

export default meta;
type Story = StoryObj<typeof AliasTestComponent>;

export const Default: Story = {};
