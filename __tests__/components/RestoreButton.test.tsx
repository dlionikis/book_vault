import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import RestoreButton from '@/components/RestoreButton';

const mockRefresh = jest.fn();
jest.mock('next/navigation', () => ({
  useRouter: () => ({ refresh: mockRefresh }),
}));

const mockFetch = jest.fn();
beforeEach(() => {
  jest.clearAllMocks();
  (global as unknown as { fetch: jest.Mock }).fetch = mockFetch;
});

describe('RestoreButton', () => {
  it('POSTs the restore endpoint and refreshes on success', async () => {
    mockFetch.mockResolvedValue({ ok: true });
    render(<RestoreButton bookId="b1" />);

    await userEvent.click(screen.getByRole('button', { name: /request restore/i }));

    await waitFor(() =>
      expect(mockFetch).toHaveBeenCalledWith('/api/books/b1/restore', { method: 'POST' })
    );
    await waitFor(() => expect(mockRefresh).toHaveBeenCalled());
  });

  it('shows an error and does not refresh on failure', async () => {
    mockFetch.mockResolvedValue({ ok: false });
    render(<RestoreButton bookId="b1" />);

    await userEvent.click(screen.getByRole('button', { name: /request restore/i }));

    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument());
    expect(mockRefresh).not.toHaveBeenCalled();
  });
});
