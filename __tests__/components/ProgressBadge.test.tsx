import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ProgressBadge from '@/components/ProgressBadge';

// Mock fetch
global.fetch = jest.fn();

describe('ProgressBadge', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({ positionSeconds: 0, completed: false }),
    });
  });

  describe('Status Display', () => {
    it('should display "Not Started" when position is 0 and not completed', () => {
      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
        />
      );

      expect(screen.getByText('Not Started')).toBeInTheDocument();
    });

    it('should display "Finished" when completed', () => {
      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: true,
          }}
        />
      );

      expect(screen.getByText('Finished')).toBeInTheDocument();
    });

    it('should display progress percentage when in progress', () => {
      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 1800, // 30 minutes
            completed: false,
            totalSeconds: 3600, // 60 minutes total
          }}
        />
      );

      expect(screen.getByText('50% Complete')).toBeInTheDocument();
    });

    it('should display progress bar when in progress', () => {
      const { container } = render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 900, // 15 minutes
            completed: false,
            totalSeconds: 3600, // 60 minutes total
          }}
        />
      );

      const progressBar = container.querySelector('.bg-blue-600');
      expect(progressBar).toBeInTheDocument();
      expect(progressBar).toHaveStyle({ width: '25%' });
    });

    it('should not display progress bar when not started', () => {
      const { container } = render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
            totalSeconds: 3600,
          }}
        />
      );

      const progressBar = container.querySelector('.bg-blue-600');
      expect(progressBar).not.toBeInTheDocument();
    });

    it('should not display progress bar when completed', () => {
      const { container } = render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 3600,
            completed: true,
            totalSeconds: 3600,
          }}
        />
      );

      const progressBar = container.querySelector('.bg-blue-600');
      expect(progressBar).not.toBeInTheDocument();
    });

    it('should cap percentage at 100%', () => {
      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 4000, // More than total
            completed: false,
            totalSeconds: 3600,
          }}
        />
      );

      expect(screen.getByText('100% Complete')).toBeInTheDocument();
    });
  });

  describe('Manual Status Controls', () => {
    it('should show "Mark as Finished" option when not completed', () => {
      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
        />
      );

      expect(screen.getByText('Mark as Finished')).toBeInTheDocument();
    });

    it('should show "Reset to Not Started" option when in progress or completed', () => {
      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 1000,
            completed: false,
          }}
        />
      );

      expect(screen.getByText('Reset to Not Started')).toBeInTheDocument();
    });

    it('should call API and update status when marking as finished', async () => {
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: async () => ({ positionSeconds: 0, completed: true }),
      });

      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
        />
      );

      const markFinishedButton = screen.getByText('Mark as Finished');
      fireEvent.click(markFinishedButton);

      await waitFor(() => {
        expect(global.fetch).toHaveBeenCalledWith(
          '/api/progress',
          expect.objectContaining({
            method: 'PUT',
            body: JSON.stringify({ bookId: 'book-1', status: 'completed' }),
          })
        );
      });

      await waitFor(() => {
        expect(screen.getByText('Finished')).toBeInTheDocument();
      });
    });

    it('should call API and update status when resetting to not started', async () => {
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: async () => ({ positionSeconds: 0, completed: false }),
      });

      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 1000,
            completed: false,
          }}
        />
      );

      const resetButton = screen.getByText('Reset to Not Started');
      fireEvent.click(resetButton);

      await waitFor(() => {
        expect(global.fetch).toHaveBeenCalledWith(
          '/api/progress',
          expect.objectContaining({
            method: 'PUT',
            body: JSON.stringify({ bookId: 'book-1', status: 'not-started' }),
          })
        );
      });

      await waitFor(() => {
        expect(screen.getByText('Not Started')).toBeInTheDocument();
      });
    });

    it('should call onProgressUpdate callback after update', async () => {
      const mockCallback = jest.fn();
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: async () => ({ positionSeconds: 0, completed: true }),
      });

      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
          onProgressUpdate={mockCallback}
        />
      );

      const markFinishedButton = screen.getByText('Mark as Finished');
      fireEvent.click(markFinishedButton);

      await waitFor(() => {
        expect(mockCallback).toHaveBeenCalled();
      });
    });

    it('should handle API errors gracefully', async () => {
      const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation();
      (global.fetch as jest.Mock).mockRejectedValueOnce(new Error('API Error'));

      render(
        <ProgressBadge
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
        />
      );

      const markFinishedButton = screen.getByText('Mark as Finished');
      fireEvent.click(markFinishedButton);

      await waitFor(() => {
        expect(consoleErrorSpy).toHaveBeenCalled();
      });

      // Status should remain unchanged
      expect(screen.getByText('Not Started')).toBeInTheDocument();

      consoleErrorSpy.mockRestore();
    });
  });
});
