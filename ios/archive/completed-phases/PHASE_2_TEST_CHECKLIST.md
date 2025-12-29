# Phase 2: Audio Playback - Test Checklist

## Pre-Testing Setup

- [ ] Backend server running (`npm run dev` in main project)
- [ ] iOS app built and running on simulator
- [ ] Logged in with test credentials (test@example.com / password123)
- [ ] At least one book available in library

## Test Scenarios

### 1. Basic Playback Controls

- [ ] **Start Playback**: Tap book → See audio controls
- [ ] **Play Button**: Tap play → Audio starts, button changes to pause
- [ ] **Pause Button**: Tap pause → Audio stops, button changes to play
- [ ] **Skip Forward**: Tap forward button → Audio jumps 30 seconds ahead
- [ ] **Skip Backward**: Tap backward button → Audio jumps 30 seconds back

### 2. Seek Controls

- [ ] **Progress Bar**: Drag slider → Audio position updates immediately
- [ ] **Time Labels**: Current time and duration display correctly
- [ ] **Seek Accuracy**: Drag to middle → Time matches slider position

### 3. Speed Control

- [ ] **Speed Button Visible**: No scrolling needed to see speedometer button
- [ ] **Open Speed Picker**: Tap speed button → Modal appears with speed options
- [ ] **Change Speed to 1.5x**: Select 1.5x → Audio plays faster
- [ ] **Change Speed to 0.75x**: Select 0.75x → Audio plays slower
- [ ] **Speed Display**: Button shows current speed (e.g., "1.5x", "0.75x")
- [ ] **Speed Persists**: Speed setting maintained during pause/resume

### 4. Volume Control

- [ ] **Volume Visible**: No scrolling needed to see volume slider
- [ ] **Volume Icon**: Icon matches volume level (muted, low, medium, high)
- [ ] **Increase Volume**: Drag slider right → Audio gets louder
- [ ] **Decrease Volume**: Drag slider left → Audio gets quieter
- [ ] **Mute**: Set volume to 0 → Speaker icon shows muted state

### 5. UI Layout (No Scrolling Required)

- [ ] **Cover Art**: Visible at top of screen
- [ ] **Book Title & Author**: Visible below cover
- [ ] **Progress Bar**: Visible without scrolling
- [ ] **Playback Controls**: Visible without scrolling
- [ ] **Volume & Speed Controls**: On same row, both visible without scrolling
- [ ] **Bottom Spacing**: Adequate space at bottom (matches top spacing)
- [ ] **Close Button**: X button in top-right corner works

### 6. Streaming & Performance

- [ ] **Audio Starts Quickly**: Playback begins within 1-2 seconds
- [ ] **No Buffering**: Audio streams smoothly without interruptions
- [ ] **Progress Updates**: Current time updates every 0.5 seconds
- [ ] **No Lag**: UI remains responsive during playback

### 7. Debug Logging (Check Xcode Console)

- [ ] **Playback Start**: Debug logs show authentication and URL setup
- [ ] **Resource Loading**: Debug logs show streaming requests
- [ ] **Status Updates**: Debug logs show AVPlayerItem status changes
- [ ] **No Production Logs**: Logs only appear in DEBUG builds

## Phase 2 Acceptance Criteria

✅ User can start playback from book detail

- [ ] User can control playback (play/pause/seek)
- [ ] User can adjust playback speed
- [ ] Audio streams without buffering
- [ ] Playback position updates in real-time

## Issues Found

_Document any bugs or issues here:_

---

## Testing Notes

- Test on multiple books (different formats: .mp3, .m4b)
- Test with different network conditions (if applicable)
- Check for memory leaks during long playback sessions
- Verify audio continues when app is backgrounded (Phase 3 feature)
