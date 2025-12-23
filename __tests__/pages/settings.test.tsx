import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { useSession } from 'next-auth/react';
import SettingsPage from '@/app/settings/page';

// Mock next-auth
jest.mock('next-auth/react', () => ({
  useSession: jest.fn(),
}));

// Mock next/navigation
jest.mock('next/navigation', () => ({
  useRouter: () => ({
    push: jest.fn(),
    refresh: jest.fn(),
  }),
}));

// Mock fetch
global.fetch = jest.fn();

describe('Settings Page', () => {
  const mockSession = {
    user: {
      id: 'user-1',
      email: 'test@example.com',
    },
  };

  beforeEach(() => {
    (useSession as jest.Mock).mockReturnValue({
      data: mockSession,
      status: 'authenticated',
    });
    jest.clearAllMocks();
  });

  it('renders settings page with user email', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Settings')).toBeInTheDocument();
    expect(screen.getByText('Account Information')).toBeInTheDocument();
    expect(screen.getByDisplayValue('test@example.com')).toBeInTheDocument();
  });

  it('displays password change form', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Change Password')).toBeInTheDocument();
    expect(screen.getByLabelText('Current Password')).toBeInTheDocument();
    expect(screen.getByLabelText('New Password')).toBeInTheDocument();
    expect(screen.getByLabelText('Confirm New Password')).toBeInTheDocument();
  });

  it('shows error when passwords do not match', async () => {
    render(<SettingsPage />);

    fireEvent.change(screen.getByLabelText('Current Password'), {
      target: { value: 'oldpassword' },
    });
    fireEvent.change(screen.getByLabelText('New Password'), {
      target: { value: 'newpassword123' },
    });
    fireEvent.change(screen.getByLabelText('Confirm New Password'), {
      target: { value: 'differentpassword' },
    });

    fireEvent.click(screen.getByText('Update Password'));

    await waitFor(() => {
      expect(screen.getByText('New passwords do not match')).toBeInTheDocument();
    });

    expect(fetch).not.toHaveBeenCalled();
  });

  it('shows error when new password is too short', async () => {
    render(<SettingsPage />);

    fireEvent.change(screen.getByLabelText('Current Password'), {
      target: { value: 'oldpassword' },
    });
    fireEvent.change(screen.getByLabelText('New Password'), {
      target: { value: 'short' },
    });
    fireEvent.change(screen.getByLabelText('Confirm New Password'), {
      target: { value: 'short' },
    });

    fireEvent.click(screen.getByText('Update Password'));

    await waitFor(() => {
      expect(screen.getByText('Password must be at least 8 characters long')).toBeInTheDocument();
    });

    expect(fetch).not.toHaveBeenCalled();
  });

  it('successfully updates password', async () => {
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: true,
      json: async () => ({ message: 'Password updated successfully' }),
    });

    render(<SettingsPage />);

    fireEvent.change(screen.getByLabelText('Current Password'), {
      target: { value: 'oldpassword123' },
    });
    fireEvent.change(screen.getByLabelText('New Password'), {
      target: { value: 'newpassword123' },
    });
    fireEvent.change(screen.getByLabelText('Confirm New Password'), {
      target: { value: 'newpassword123' },
    });

    fireEvent.click(screen.getByText('Update Password'));

    await waitFor(() => {
      expect(screen.getByText('Password updated successfully!')).toBeInTheDocument();
    });

    expect(fetch).toHaveBeenCalledWith('/api/user/password', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        currentPassword: 'oldpassword123',
        newPassword: 'newpassword123',
      }),
    });
  });

  it('displays error message from API', async () => {
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: false,
      json: async () => ({ error: 'Current password is incorrect' }),
    });

    render(<SettingsPage />);

    fireEvent.change(screen.getByLabelText('Current Password'), {
      target: { value: 'wrongpassword' },
    });
    fireEvent.change(screen.getByLabelText('New Password'), {
      target: { value: 'newpassword123' },
    });
    fireEvent.change(screen.getByLabelText('Confirm New Password'), {
      target: { value: 'newpassword123' },
    });

    fireEvent.click(screen.getByText('Update Password'));

    await waitFor(() => {
      expect(screen.getByText('Current password is incorrect')).toBeInTheDocument();
    });
  });

  it('clears form fields after successful password update', async () => {
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: true,
      json: async () => ({ message: 'Password updated successfully' }),
    });

    render(<SettingsPage />);

    const currentPasswordInput = screen.getByLabelText('Current Password') as HTMLInputElement;
    const newPasswordInput = screen.getByLabelText('New Password') as HTMLInputElement;
    const confirmPasswordInput = screen.getByLabelText('Confirm New Password') as HTMLInputElement;

    fireEvent.change(currentPasswordInput, { target: { value: 'oldpassword123' } });
    fireEvent.change(newPasswordInput, { target: { value: 'newpassword123' } });
    fireEvent.change(confirmPasswordInput, { target: { value: 'newpassword123' } });

    fireEvent.click(screen.getByText('Update Password'));

    await waitFor(() => {
      expect(currentPasswordInput.value).toBe('');
      expect(newPasswordInput.value).toBe('');
      expect(confirmPasswordInput.value).toBe('');
    });
  });

  it('disables submit button while loading', async () => {
    (global.fetch as jest.Mock).mockImplementation(
      () => new Promise((resolve) => setTimeout(resolve, 100))
    );

    render(<SettingsPage />);

    fireEvent.change(screen.getByLabelText('Current Password'), {
      target: { value: 'oldpassword123' },
    });
    fireEvent.change(screen.getByLabelText('New Password'), {
      target: { value: 'newpassword123' },
    });
    fireEvent.change(screen.getByLabelText('Confirm New Password'), {
      target: { value: 'newpassword123' },
    });

    const submitButton = screen.getByText('Update Password');
    fireEvent.click(submitButton);

    expect(screen.getByText('Updating...')).toBeInTheDocument();
    expect(submitButton).toBeDisabled();
  });

  it('displays email as disabled field', () => {
    render(<SettingsPage />);

    const emailInput = screen.getByDisplayValue('test@example.com') as HTMLInputElement;
    expect(emailInput).toBeDisabled();
    expect(screen.getByText('Email cannot be changed')).toBeInTheDocument();
  });

  it('has navigation sections for account and security', () => {
    render(<SettingsPage />);

    expect(screen.getByText('← Back to Library')).toBeInTheDocument();
    expect(screen.getByText('Account')).toBeInTheDocument();
    expect(screen.getByText('Security')).toBeInTheDocument();
  });
});
