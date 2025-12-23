import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import ProgressStatus from '@/components/ProgressStatus';

describe('ProgressStatus', () => {
  describe('Status Display', () => {
    it('should display "Not Started" when position is 0 and not completed', () => {
      render(
        <ProgressStatus
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
        <ProgressStatus
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
        <ProgressStatus
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
        <ProgressStatus
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
        <ProgressStatus
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
        <ProgressStatus
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
        <ProgressStatus
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
});
