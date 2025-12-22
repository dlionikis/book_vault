import { render, screen, fireEvent } from '@testing-library/react';
import { useRouter, useSearchParams } from 'next/navigation';
import SortDropdown from '@/components/SortDropdown';

// Mock next/navigation
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
}));

describe('SortDropdown', () => {
  const mockPush = jest.fn();
  const mockGet = jest.fn();
  const mockUseRouter = useRouter as jest.MockedFunction<typeof useRouter>;
  const mockUseSearchParams = useSearchParams as jest.MockedFunction<typeof useSearchParams>;

  beforeEach(() => {
    mockPush.mockClear();
    mockGet.mockClear();
    mockUseRouter.mockReturnValue({
      push: mockPush,
    } as any);
    mockUseSearchParams.mockReturnValue({
      get: mockGet,
    } as any);
  });

  it('renders sort dropdown', () => {
    mockGet.mockReturnValue(null);
    render(<SortDropdown />);
    expect(screen.getByLabelText('Sort by:')).toBeInTheDocument();
  });

  it('displays all sort options', () => {
    mockGet.mockReturnValue(null);
    render(<SortDropdown />);
    const select = screen.getByRole('combobox');
    expect(select).toBeInTheDocument();

    const options = screen.getAllByRole('option');
    expect(options).toHaveLength(4);
    expect(screen.getByText('Title')).toBeInTheDocument();
    expect(screen.getByText('Author')).toBeInTheDocument();
    expect(screen.getByText('Narrator')).toBeInTheDocument();
    expect(screen.getByText('Series')).toBeInTheDocument();
  });

  it('shows current sort selection', () => {
    mockGet.mockReturnValue('author');
    render(<SortDropdown />);
    const select = screen.getByRole('combobox') as HTMLSelectElement;
    expect(select.value).toBe('author');
  });

  it('navigates with sort parameter when changed', () => {
    mockGet.mockReturnValue(null);
    render(<SortDropdown />);
    const select = screen.getByRole('combobox');

    fireEvent.change(select, { target: { value: 'narrator' } });

    // The component uses URLSearchParams which includes existing params
    expect(mockPush).toHaveBeenCalledWith(expect.stringContaining('sort=narrator'));
  });

  it('defaults to title sort when no parameter', () => {
    mockGet.mockReturnValue(null);
    render(<SortDropdown />);
    const select = screen.getByRole('combobox') as HTMLSelectElement;
    expect(select.value).toBe('title');
  });
});
