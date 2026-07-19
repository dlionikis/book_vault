import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useSession } from 'next-auth/react';
import AddToLibraryButton from '@/components/AddToLibraryButton';

jest.mock('next-auth/react', () => ({
  useSession: jest.fn(),
}));

const mockUseSession = useSession as jest.MockedFunction<typeof useSession>;

// jsdom has no fetch by default; stub per-test.
const mockFetch = jest.fn();
beforeEach(() => {
  jest.clearAllMocks();
  (global as unknown as { fetch: jest.Mock }).fetch = mockFetch;
});

const authenticated = {
  data: {
    user: { id: 'u1', email: 'testuser@example.com', username: 'testuser', isAdmin: false },
    expires: '',
  },
  status: 'authenticated' as const,
  update: jest.fn(),
} as unknown as ReturnType<typeof useSession>;
const loadingSession = {
  data: null,
  status: 'loading' as const,
  update: jest.fn(),
} as unknown as ReturnType<typeof useSession>;

describe('AddToLibraryButton', () => {
  it('is disabled while the session is still loading (prevents the pre-hydration login bounce)', () => {
    mockUseSession.mockReturnValue(loadingSession);
    render(<AddToLibraryButton bookId="b1" />);

    const button = screen.getByRole('button', { name: /add to library/i });
    expect(button).toBeDisabled();
  });

  it('becomes enabled and POSTs to /api/library once authenticated', async () => {
    mockUseSession.mockReturnValue(authenticated);
    // First call: the mount-time /api/library/check (not in library);
    // second: the POST /api/library add.
    mockFetch
      .mockResolvedValueOnce({ ok: true, json: async () => ({ inLibrary: false }) })
      .mockResolvedValueOnce({ ok: true, json: async () => ({}) });

    render(<AddToLibraryButton bookId="b1" />);
    const button = screen.getByRole('button', { name: /add to library/i });
    expect(button).toBeEnabled();

    await userEvent.click(button);

    // It hit the add endpoint (not a redirect), and flipped to "In Library".
    await waitFor(() =>
      expect(mockFetch).toHaveBeenCalledWith(
        '/api/library',
        expect.objectContaining({ method: 'POST' })
      )
    );
    await waitFor(() => expect(screen.getByRole('button', { name: /in library/i })).toBeVisible());
  });

  it('reflects existing membership from the initial library check', async () => {
    mockUseSession.mockReturnValue(authenticated);
    mockFetch.mockResolvedValueOnce({ ok: true, json: async () => ({ inLibrary: true }) });

    render(<AddToLibraryButton bookId="b1" />);

    await waitFor(() =>
      expect(screen.getByRole('button', { name: /in library/i })).toBeInTheDocument()
    );
  });
});
