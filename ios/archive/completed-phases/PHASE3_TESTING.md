# Phase 3: Background Audio & Lock Screen Controls - Testing Guide

**Status**: Implementation Complete - Ready for Testing
**Date**: December 27, 2025

## What Was Implemented

Phase 3 adds background audio playback and lock screen controls to the BookVault iOS app.

### Features Added

1. **Background Audio Capability**
   - Configured `UIBackgroundModes: audio` in Info.plist
   - Audio continues playing when app is minimized
   - Audio continues when device screen is locked

2. **Enhanced AVAudioSession**
   - Configured for background playback with `.playback` category
   - Set mode to `.spokenAudio` (optimized for audiobooks)
   - Enabled Bluetooth and AirPlay support
   - Added interruption handling (phone calls, alarms)
   - Added route change handling (headphones disconnect)

3. **Lock Screen Metadata (MPNowPlayingInfoCenter)**
   - Displays book title
   - Displays authors
   - Displays series name (if available)
   - Displays cover artwork
   - Shows current playback position
   - Shows total duration
   - Updates playback rate in metadata

4. **Lock Screen Controls (MPRemoteCommandCenter)**
   - Play/Pause toggle
   - Skip forward (30 seconds)
   - Skip backward (30 seconds)
   - Scrubbing/seeking on lock screen
   - All controls work from lock screen, Control Center, and headphones

5. **Interruption Handling**
   - Pauses playback when phone call comes in
   - Pauses playback when alarm goes off
   - Automatically resumes after interruption (if appropriate)

6. **Route Change Handling**
   - Pauses playback when headphones are disconnected
   - Handles Bluetooth device disconnection gracefully

## Files Changed

1. **ios/project.yml**
   - Added `INFOPLIST_KEY_UIBackgroundModes: 'audio'`

2. **ios/BookVault/Services/AudioPlayerManager.swift**
   - Added `import MediaPlayer`
   - Enhanced `setupAudioSession()` with background playback options
   - Added `setupRemoteCommandCenter()` for lock screen controls
   - Added `updateNowPlayingInfo()` for lock screen metadata
   - Added `loadCoverImage()` for cover artwork on lock screen
   - Added `setupInterruptionObserver()` for interruption handling
   - Added `setupRouteChangeObserver()` for route change handling
   - Added `handleInterruption()` notification handler
   - Added `handleRouteChange()` notification handler
   - Updated `resume()`, `pause()`, `seek()`, `setPlaybackRate()` to update lock screen info

## Testing Checklist

### Prerequisites

- Real iOS device (iPhone or iPad running iOS 17+)
- Xcode 15+ installed
- BookVault backend running and accessible from device
- Test account credentials

### Setup

1. Open the Xcode project: `ios/BookVault.xcodeproj`
2. Select your iOS device as the target
3. Build and run the app (⌘R)
4. Log in with test credentials
5. Select an audiobook and start playback

### Test Cases

#### ✅ Background Audio Playback

- [ ] **Test 1: Home button press**
  1. Start audiobook playback
  2. Press the Home button (or swipe up on Face ID devices)
  3. Verify audio continues playing
  4. Expected: Audio should continue playing in background

- [ ] **Test 2: Lock screen**
  1. Start audiobook playback
  2. Press the power button to lock the device
  3. Verify audio continues playing
  4. Expected: Audio should continue playing with screen locked

- [ ] **Test 3: Switch to another app**
  1. Start audiobook playback
  2. Open another app (Safari, Settings, etc.)
  3. Verify audio continues playing
  4. Expected: Audio should continue playing while using other apps

#### ✅ Lock Screen Metadata Display

- [ ] **Test 4: Lock screen shows metadata**
  1. Start audiobook playback
  2. Lock the device (press power button)
  3. Wake the screen (without unlocking)
  4. Verify the lock screen shows:
     - Book cover artwork
     - Book title
     - Author name(s)
     - Series name (if applicable)
     - Current playback position
     - Total duration
  5. Expected: All metadata should be visible and correct

- [ ] **Test 5: Metadata updates during playback**
  1. With audio playing and screen locked
  2. Wait 30 seconds
  3. Wake the screen
  4. Verify the playback position has updated
  5. Expected: Time should advance as audio plays

#### ✅ Lock Screen Controls

- [ ] **Test 6: Play/Pause from lock screen**
  1. Start playback and lock device
  2. Wake screen (don't unlock)
  3. Tap the pause button on lock screen
  4. Verify audio pauses
  5. Tap the play button
  6. Verify audio resumes
  7. Expected: Play/pause should work from lock screen

- [ ] **Test 7: Skip forward from lock screen**
  1. Start playback and lock device
  2. Wake screen
  3. Tap the "skip forward" button (should skip 30 seconds)
  4. Note the current time
  5. Verify time advances by ~30 seconds
  6. Expected: Should skip forward 30 seconds

- [ ] **Test 8: Skip backward from lock screen**
  1. Play for at least 1 minute
  2. Lock device and wake screen
  3. Tap the "skip backward" button (should skip back 30 seconds)
  4. Note the current time
  5. Verify time goes back by ~30 seconds
  6. Expected: Should skip backward 30 seconds

- [ ] **Test 9: Scrubbing on lock screen**
  1. Start playback and lock device
  2. Wake screen
  3. Drag the playback position slider
  4. Verify audio seeks to new position
  5. Expected: Scrubbing should work from lock screen

#### ✅ Control Center

- [ ] **Test 10: Control Center controls**
  1. Start playback
  2. Open Control Center (swipe down from top-right on Face ID, swipe up on Home button devices)
  3. Verify BookVault appears in Now Playing widget
  4. Test play/pause, skip forward/backward from Control Center
  5. Expected: All controls should work from Control Center

#### ✅ Interruption Handling

- [ ] **Test 11: Phone call interruption**
  1. Start audiobook playback
  2. Have someone call your device (or use another phone to call yourself)
  3. Verify audio pauses when call comes in
  4. Answer the call briefly and hang up
  5. Verify audio resumes after call ends
  6. Expected: Audio should pause during call and resume after

- [ ] **Test 12: Alarm interruption**
  1. Set an alarm for 1 minute from now
  2. Start audiobook playback
  3. Wait for alarm to go off
  4. Verify audio pauses when alarm sounds
  5. Dismiss the alarm
  6. Verify audio resumes
  7. Expected: Audio should pause for alarm and resume after dismissing

- [ ] **Test 13: Siri interruption**
  1. Start audiobook playback
  2. Activate Siri (press and hold side button or say "Hey Siri")
  3. Verify audio pauses
  4. Dismiss Siri
  5. Verify audio resumes
  6. Expected: Audio should pause for Siri and resume after

#### ✅ Route Change Handling

- [ ] **Test 14: Headphones disconnect**
  1. Connect wired headphones or Bluetooth headphones
  2. Start audiobook playback
  3. Disconnect the headphones
  4. Verify audio pauses
  5. Expected: Audio should pause when headphones are removed

- [ ] **Test 15: Bluetooth device connection**
  1. Start audiobook playback (using device speakers)
  2. Connect Bluetooth headphones or speaker
  3. Verify audio switches to Bluetooth device
  4. Expected: Audio should continue playing on new device

- [ ] **Test 16: CarPlay (if available)**
  1. Connect device to CarPlay
  2. Start audiobook playback
  3. Verify audio plays through car speakers
  4. Verify controls work in CarPlay interface
  5. Expected: Full audio playback and control in CarPlay

#### ✅ Playback Rate & Lock Screen

- [ ] **Test 17: Playback rate on lock screen**
  1. Start playback
  2. Change playback speed to 1.5x
  3. Lock device and wake screen
  4. Verify lock screen shows playback rate as 1.5x
  5. Expected: Playback rate should be reflected in metadata

### Known Limitations

- SwiftUI Previews may not work for audio playback (requires real device)
- Simulator may not fully support background audio (use real device)
- Lock screen artwork may take a moment to load (fetched asynchronously)

## Debug Logging

The implementation includes extensive debug logging with the 🎵 emoji prefix. To view logs:

1. In Xcode, open the Console (View → Debug Area → Activate Console)
2. Filter for "🎵" or "AudioPlayerManager"
3. You'll see logs for:
   - Audio session setup
   - Remote command center configuration
   - Lock screen metadata updates
   - Interruption events
   - Route change events
   - Playback state changes

Example logs:

```
🎵 Audio session configured for background playback
🎵 Remote command center configured
🎵 AudioPlayerManager: Starting playback for [Book Title]
🎵 Updated Now Playing info: [Book Title]
🎵 Audio interruption began - pausing playback
🎵 Audio interruption ended - resuming playback
🎵 Audio route changed - device unavailable, pausing playback
```

## Troubleshooting

### Audio stops when app backgrounds

- **Solution**: Verify `UIBackgroundModes: audio` is set in project.yml
- **Solution**: Regenerate Xcode project: `cd ios && xcodegen generate`

### Lock screen doesn't show metadata

- **Solution**: Check that `updateNowPlayingInfo()` is being called
- **Solution**: Verify MPNowPlayingInfoCenter is receiving data (check debug logs)

### Lock screen controls don't work

- **Solution**: Verify `setupRemoteCommandCenter()` is called in `init()`
- **Solution**: Check that command handlers return `.success`

### Audio doesn't resume after interruption

- **Solution**: Check interruption handler logs
- **Solution**: Verify AVAudioSession is properly configured

### Cover artwork not showing

- **Solution**: Check that cover URL is valid and accessible
- **Solution**: Verify authentication token is being passed in image request
- **Solution**: May take a moment to load (fetched asynchronously)

## Next Steps

After completing Phase 3 testing:

1. **Phase 4: Progress Sync**
   - Implement automatic progress saving to backend
   - Load saved position on playback start
   - Sync progress between web and mobile

2. **Phase 5: Chapter Navigation**
   - Fetch chapters from API
   - Display chapter list in Now Playing screen
   - Skip to chapter functionality

## Acceptance Criteria (from docs/mobile/implementation-phases.md)

Phase 3 is complete when ALL of the following are verified:

- ✅ Audio continues when screen locks
- ✅ Lock screen shows cover art, title, author
- ✅ Lock screen controls work (play, pause, skip)
- ✅ Audio pauses on interruption, resumes after
- ✅ Audio handles headphone disconnect properly

## Notes for Reviewers

- All code changes follow existing patterns in AudioPlayerManager
- MediaPlayer framework imported for lock screen support
- Debug logging added throughout for troubleshooting
- No breaking changes to existing Phase 2 functionality
- All new features are iOS-native (AVFoundation, MediaPlayer)

---

**Ready for Testing**: Yes ✅
**Requires Real Device**: Yes (Simulator has limited background audio support)
**Requires Backend Running**: Yes (for authentication and audio streaming)
