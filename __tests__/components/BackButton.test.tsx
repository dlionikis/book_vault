import { render, screen, fireEvent } from '@testing-library/react';
import { useRouter } from 'next/navigation';
import BackButton from '@/components/BackButton';

// Mock next/navigation
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
}));

describe('BackButton', () => {
  const mockBack = jest.fn();
  const mockUseRouter = useRouter as jest.MockedFunction<typeof useRouter>;

  beforeEach(() => {
    mockBack.mockClear();
    mockUseRouter.mockReturnValue({
      back: mockBack,
    } as any);
  });

  it('renders back button', () => {
    render(<BackButton />);
    expect(screen.getByText('Back')).toBeInTheDocument();
  });

  it('calls router.back() when clicked', () => {
    render(<BackButton />);
    const button = screen.getByText('Back');
    fireEvent.click(button);
    expect(mockBack).toHaveBeenCalledTimes(1);
  });

  it('has correct styling classes', () => {
    render(<BackButton />);
    const button = screen.getByText('Back');
    expect(button).toHaveClass('text-blue-600');
    expect(button).toHaveClass('hover:text-blue-800');
  });
});
