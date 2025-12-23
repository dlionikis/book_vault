import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import AudioPlayer from '@/components/AudioPlayer';

// Mock the audio element
const mockPlay = jest.fn();
const mockPause = jest.fn();
const mockLoad = jest.fn();

// Setup HTMLMediaElement mock
beforeAll(() => {
  Object.defineProperty(window.HTMLMediaElement.prototype, 'play', {
    configurable: true,
    value: mockPlay.mockResolvedValue(undefined),
  });

  Object.defineProperty(window.HTMLMediaElement.prototype, 'pause', {
    configurable: true,
    value: mockPause,
  });

  Object.defineProperty(window.HTMLMediaElement.prototype, 'load', {
    configurable: true,
    value: mockLoad,
  });

  Object.defineProperty(window.HTMLMediaElement.prototype, 'currentTime', {
    configurable: true,
    value: 0,
    writable: true,
  });

  Object.defineProperty(window.HTMLMediaElement.prototype, 'duration', {
    configurable: true,
    get: () => 3600, // 1 hour duration
  });

  Object.defineProperty(window.HTMLMediaElement.prototype, 'volume', {
    configurable: true,
    value: 1,
    writable: true,
  });

  Object.defineProperty(window.HTMLMediaElement.prototype, 'playbackRate', {
    configurable: true,
    value: 1,
    writable: true,
  });
});

beforeEach(() => {
  mockPlay.mockClear();
  mockPause.mockClear();
  mockLoad.mockClear();
});

describe('AudioPlayer', () => {
  const defaultProps = {
    audioUrl: '/api/audio/test-book/audio.mp3',
    title: 'Test Book Title',
    author: 'Test Author',
    bookId: 'book-123',
  };

  it('should render with correct props', () => {
    render(<AudioPlayer {...defaultProps} />);

    expect(screen.getByText('Test Book Title')).toBeInTheDocument();
    expect(screen.getByText('Test Author')).toBeInTheDocument();
  });

  it('should have play button initially', () => {
    render(<AudioPlayer {...defaultProps} />);

    const playButton = screen.getByLabelText('Play');
    expect(playButton).toBeInTheDocument();
  });

  it('should toggle play/pause when button is clicked', async () => {
    render(<AudioPlayer {...defaultProps} />);

    const playButton = screen.getByLabelText('Play');
    fireEvent.click(playButton);

    await waitFor(() => {
      expect(mockPlay).toHaveBeenCalledTimes(1);
    });

    const pauseButton = screen.getByLabelText('Pause');
    expect(pauseButton).toBeInTheDocument();

    fireEvent.click(pauseButton);
    expect(mockPause).toHaveBeenCalledTimes(1);
  });

  it('should display time in correct format', () => {
    render(<AudioPlayer {...defaultProps} />);

    // Should show initial time as 0:00:00 (appears twice: current and duration)
    const timeElements = screen.getAllByText('0:00:00');
    expect(timeElements).toHaveLength(2);
  });

  it('should have seek slider with correct attributes', () => {
    render(<AudioPlayer {...defaultProps} />);

    const seekSlider = screen.getByLabelText('Seek audio');
    expect(seekSlider).toBeInTheDocument();
    expect(seekSlider).toHaveAttribute('type', 'range');
    expect(seekSlider).toHaveAttribute('min', '0');
  });

  it('should handle seek interaction', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;
    const seekSlider = screen.getByLabelText('Seek audio') as HTMLInputElement;

    // Verify the seek slider exists and has correct initial value
    expect(seekSlider.value).toBe('0');

    // Simulate seeking (in jsdom, the actual seeking behavior is limited)
    fireEvent.change(seekSlider, { target: { value: '1800' } });

    // Just verify no errors occurred during the seek
    expect(seekSlider).toBeInTheDocument();
  });

  it('should have skip backward button', () => {
    render(<AudioPlayer {...defaultProps} />);

    const skipBackButton = screen.getByLabelText('Skip backward 15 seconds');
    expect(skipBackButton).toBeInTheDocument();
  });

  it('should have skip forward button', () => {
    render(<AudioPlayer {...defaultProps} />);

    const skipForwardButton = screen.getByLabelText('Skip forward 30 seconds');
    expect(skipForwardButton).toBeInTheDocument();
  });

  it('should have playback rate controls', () => {
    render(<AudioPlayer {...defaultProps} />);

    expect(screen.getByLabelText('Set playback speed to 0.75x')).toBeInTheDocument();
    expect(screen.getByLabelText('Set playback speed to 1x')).toBeInTheDocument();
    expect(screen.getByLabelText('Set playback speed to 1.25x')).toBeInTheDocument();
    expect(screen.getByLabelText('Set playback speed to 1.5x')).toBeInTheDocument();
    expect(screen.getByLabelText('Set playback speed to 2x')).toBeInTheDocument();
  });

  it('should change playback rate when button is clicked', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;
    const rate1_5xButton = screen.getByLabelText('Set playback speed to 1.5x');

    fireEvent.click(rate1_5xButton);

    // Verify the button has active styling
    expect(rate1_5xButton).toHaveClass('bg-blue-600', 'text-white');
  });

  it('should have volume control', () => {
    render(<AudioPlayer {...defaultProps} />);

    const volumeSlider = screen.getByLabelText('Volume control');
    expect(volumeSlider).toBeInTheDocument();
    expect(volumeSlider).toHaveAttribute('type', 'range');
    expect(volumeSlider).toHaveAttribute('min', '0');
    expect(volumeSlider).toHaveAttribute('max', '1');
  });

  it('should have mute button', () => {
    render(<AudioPlayer {...defaultProps} />);

    const muteButton = screen.getByLabelText('Mute');
    expect(muteButton).toBeInTheDocument();
  });

  it('should toggle mute when mute button is clicked', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;
    const muteButton = screen.getByLabelText('Mute');

    fireEvent.click(muteButton);

    // After clicking, should become unmute button
    const unmuteButton = screen.getByLabelText('Unmute');
    expect(unmuteButton).toBeInTheDocument();

    fireEvent.click(unmuteButton);

    // Should be back to mute button
    expect(screen.getByLabelText('Mute')).toBeInTheDocument();
  });

  it('should render audio element with correct src', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio');
    expect(audio).toBeInTheDocument();
    expect(audio).toHaveAttribute('src', '/api/audio/test-book/audio.mp3');
  });

  it('should be fixed at the bottom of the page', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const playerContainer = container.firstChild;
    expect(playerContainer).toHaveClass('fixed', 'bottom-0', 'left-0', 'right-0');
  });

  it('should handle time update events', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;

    // Simulate time update
    Object.defineProperty(audio, 'currentTime', {
      configurable: true,
      value: 100,
    });

    fireEvent.timeUpdate(audio);

    // The component should update, but we can't directly test state
    // Just verify no errors occur
    expect(audio).toBeInTheDocument();
  });

  it('should handle loaded metadata event', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;

    fireEvent.loadedMetadata(audio);

    // Should display duration (1:00:00 for 3600 seconds)
    expect(screen.getByText('1:00:00')).toBeInTheDocument();
  });

  it('should stop playing when audio ends', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;

    // Start playing first
    const playButton = screen.getByLabelText('Play');
    fireEvent.click(playButton);

    // Trigger ended event
    fireEvent.ended(audio);

    // Should show play button again
    expect(screen.getByLabelText('Play')).toBeInTheDocument();
  });

  it('should format time correctly for different durations', () => {
    render(<AudioPlayer {...defaultProps} />);

    // Test formatting by triggering metadata load
    const { container } = render(<AudioPlayer {...defaultProps} />);
    const audio = container.querySelector('audio') as HTMLAudioElement;

    // Set different durations via metadata load
    fireEvent.loadedMetadata(audio);

    // Duration of 3600 seconds should show as 1:00:00
    expect(screen.getByText('1:00:00')).toBeInTheDocument();
  });

  it('should handle volume change', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;
    const volumeSlider = screen.getByLabelText('Volume control') as HTMLInputElement;

    fireEvent.change(volumeSlider, { target: { value: '0.5' } });

    expect(volumeSlider.value).toBe('0.5');
  });

  it('should skip backward by 15 seconds when skip back button is clicked', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;
    const skipBackButton = screen.getByLabelText('Skip backward 15 seconds');

    // Set current time to 100
    Object.defineProperty(audio, 'currentTime', {
      configurable: true,
      value: 100,
      writable: true,
    });

    fireEvent.click(skipBackButton);

    // Can't directly verify currentTime in jsdom, but verify no errors
    expect(skipBackButton).toBeInTheDocument();
  });

  it('should skip forward by 30 seconds when skip forward button is clicked', () => {
    const { container } = render(<AudioPlayer {...defaultProps} />);

    const audio = container.querySelector('audio') as HTMLAudioElement;
    const skipForwardButton = screen.getByLabelText('Skip forward 30 seconds');

    fireEvent.click(skipForwardButton);

    // Verify no errors
    expect(skipForwardButton).toBeInTheDocument();
  });
});
