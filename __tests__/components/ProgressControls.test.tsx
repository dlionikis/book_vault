import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ProgressControls from '@/components/ProgressControls';

// Mock fetch
global.fetch = jest.fn();

describe('ProgressControls', () => {
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
        <ProgressControls
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
        <ProgressControls
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
        <ProgressControls
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
  });

  describe('Manual Control Buttons', () => {
    it('should show "Mark as Finished" button when not completed', () => {
      render(
        <ProgressControls
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
        />
      );

      expect(screen.getByText('Mark as Finished')).toBeInTheDocument();
    });

    it('should show "Reset to Not Started" button when in progress or completed', () => {
      render(
        <ProgressControls
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
        <ProgressControls
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
        <ProgressControls
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
        <ProgressControls
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
        <ProgressControls
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

    it('should disable buttons while updating', async () => {
      (global.fetch as jest.Mock).mockImplementation(
        () =>
          new Promise((resolve) =>
            setTimeout(
              () =>
                resolve({ ok: true, json: async () => ({ positionSeconds: 0, completed: true }) }),
              100
            )
          )
      );

      render(
        <ProgressControls
          bookId="book-1"
          initialProgress={{
            positionSeconds: 0,
            completed: false,
          }}
        />
      );

      const markFinishedButton = screen.getByText('Mark as Finished');
      fireEvent.click(markFinishedButton);

      // Button should be disabled during API call
      expect(markFinishedButton).toBeDisabled();

      await waitFor(() => {
        expect(screen.getByText('Finished')).toBeInTheDocument();
      });
    });
  });
});
