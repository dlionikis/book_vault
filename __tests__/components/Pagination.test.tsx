import { render, screen, fireEvent } from '@testing-library/react';
import { useRouter, useSearchParams } from 'next/navigation';
import Pagination from '@/components/Pagination';

// Mock Next.js navigation hooks
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
}));

describe('Pagination', () => {
  const mockPush = jest.fn();
  const mockSearchParams = new URLSearchParams();

  beforeEach(() => {
    jest.clearAllMocks();
    (useRouter as jest.Mock).mockReturnValue({
      push: mockPush,
    });
    (useSearchParams as jest.Mock).mockReturnValue(mockSearchParams);
  });

  it('renders pagination info correctly', () => {
    render(<Pagination currentPage={1} totalPages={5} total={100} />);

    expect(screen.getByText(/Showing page 1 of 5 \(100 items\)/)).toBeInTheDocument();
  });

  it('renders with custom item name', () => {
    render(<Pagination currentPage={2} totalPages={10} total={200} itemName="books" />);

    expect(screen.getByText(/200 books/)).toBeInTheDocument();
  });

  it('disables previous button on first page', () => {
    render(<Pagination currentPage={1} totalPages={5} total={100} />);

    const prevButton = screen.getByLabelText('Previous page');
    expect(prevButton).toBeDisabled();
    expect(prevButton).toHaveClass('cursor-not-allowed');
  });

  it('disables next button on last page', () => {
    render(<Pagination currentPage={5} totalPages={5} total={100} />);

    const nextButton = screen.getByLabelText('Next page');
    expect(nextButton).toBeDisabled();
    expect(nextButton).toHaveClass('cursor-not-allowed');
  });

  it('enables both buttons on middle page', () => {
    render(<Pagination currentPage={3} totalPages={5} total={100} />);

    const prevButton = screen.getByLabelText('Previous page');
    const nextButton = screen.getByLabelText('Next page');

    expect(prevButton).not.toBeDisabled();
    expect(nextButton).not.toBeDisabled();
  });

  it('navigates to previous page when clicking previous button', () => {
    render(<Pagination currentPage={3} totalPages={5} total={100} />);

    const prevButton = screen.getByLabelText('Previous page');
    fireEvent.click(prevButton);

    expect(mockPush).toHaveBeenCalledWith('?page=2');
  });

  it('navigates to next page when clicking next button', () => {
    render(<Pagination currentPage={3} totalPages={5} total={100} />);

    const nextButton = screen.getByLabelText('Next page');
    fireEvent.click(nextButton);

    expect(mockPush).toHaveBeenCalledWith('?page=4');
  });

  it('navigates to specific page when clicking page number', () => {
    render(<Pagination currentPage={1} totalPages={5} total={100} />);

    const page3Button = screen.getByText('3');
    fireEvent.click(page3Button);

    expect(mockPush).toHaveBeenCalledWith('?page=3');
  });

  it('preserves existing query parameters when navigating', () => {
    const searchParamsWithQuery = new URLSearchParams('sort=author&filter=fiction');
    (useSearchParams as jest.Mock).mockReturnValue(searchParamsWithQuery);

    render(<Pagination currentPage={1} totalPages={5} total={100} />);

    const nextButton = screen.getByLabelText('Next page');
    fireEvent.click(nextButton);

    expect(mockPush).toHaveBeenCalledWith('?sort=author&filter=fiction&page=2');
  });

  it('highlights current page button', () => {
    render(<Pagination currentPage={3} totalPages={5} total={100} />);

    const currentPageButton = screen.getByLabelText('Go to page 3');
    expect(currentPageButton).toHaveClass('bg-blue-600', 'text-white');
    expect(currentPageButton).toHaveAttribute('aria-current', 'page');
  });

  it('does not render when only one page', () => {
    const { container } = render(<Pagination currentPage={1} totalPages={1} total={20} />);

    expect(container.firstChild).toBeNull();
  });

  it('does not render when totalPages is 0', () => {
    const { container } = render(<Pagination currentPage={1} totalPages={0} total={0} />);

    expect(container.firstChild).toBeNull();
  });

  describe('page number display logic', () => {
    it('shows all page numbers when 7 or fewer pages', () => {
      render(<Pagination currentPage={3} totalPages={7} total={140} />);

      // Check within the desktop pagination area only
      const desktopPagination = screen.getByLabelText('Go to page 1').closest('.hidden.sm\\:flex');
      expect(desktopPagination).toBeInTheDocument();

      // Verify all page buttons exist
      for (let i = 1; i <= 7; i++) {
        expect(screen.getByLabelText(`Go to page ${i}`)).toBeInTheDocument();
      }
      expect(screen.queryByText('...')).not.toBeInTheDocument();
    });

    it('shows ellipsis when more than 7 pages and current page is at start', () => {
      render(<Pagination currentPage={2} totalPages={20} total={400} />);

      expect(screen.getByLabelText('Go to page 1')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 2')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 3')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 4')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 5')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 20')).toBeInTheDocument();
      expect(screen.getByText('...')).toBeInTheDocument();
    });

    it('shows ellipsis when more than 7 pages and current page is at end', () => {
      render(<Pagination currentPage={19} totalPages={20} total={400} />);

      expect(screen.getByLabelText('Go to page 1')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 16')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 17')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 18')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 19')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 20')).toBeInTheDocument();
      expect(screen.getByText('...')).toBeInTheDocument();
    });

    it('shows ellipsis on both sides when current page is in middle', () => {
      render(<Pagination currentPage={10} totalPages={20} total={400} />);

      expect(screen.getByLabelText('Go to page 1')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 9')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 10')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 11')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 20')).toBeInTheDocument();
      expect(screen.getAllByText('...')).toHaveLength(2);
    });
  });

  describe('accessibility', () => {
    it('has proper ARIA labels for navigation buttons', () => {
      render(<Pagination currentPage={2} totalPages={5} total={100} />);

      expect(screen.getByLabelText('Previous page')).toBeInTheDocument();
      expect(screen.getByLabelText('Next page')).toBeInTheDocument();
    });

    it('has proper ARIA labels for page buttons', () => {
      render(<Pagination currentPage={2} totalPages={5} total={100} />);

      expect(screen.getByLabelText('Go to page 1')).toBeInTheDocument();
      expect(screen.getByLabelText('Go to page 3')).toBeInTheDocument();
    });

    it('marks current page with aria-current', () => {
      render(<Pagination currentPage={3} totalPages={5} total={100} />);

      const currentPageButton = screen.getByLabelText('Go to page 3');
      expect(currentPageButton).toHaveAttribute('aria-current', 'page');
    });
  });

  describe('mobile view', () => {
    it('shows simplified page indicator on mobile', () => {
      render(<Pagination currentPage={5} totalPages={10} total={200} />);

      // Mobile page indicator should show current page number with sm:hidden class
      const mobileIndicators = screen.getAllByText('5');
      const mobileIndicator = mobileIndicators.find((el) => el.classList.contains('sm:hidden'));
      expect(mobileIndicator).toBeDefined();
      expect(mobileIndicator).toHaveClass('sm:hidden');
    });
  });

  describe('number formatting', () => {
    it('formats large numbers with commas', () => {
      render(<Pagination currentPage={1} totalPages={100} total={10000} />);

      expect(screen.getByText(/10,000 items/)).toBeInTheDocument();
    });
  });
});
