# Phase 3.5: Mini Player UI

**Status**: Planning
**Priority**: High (UX Enhancement)
**Estimated Time**: 1-2 hours
**Last Updated**: December 27, 2025

> **TL;DR**: Add a persistent mini player bar that shows at the bottom of all screens when audio is playing, allowing users to see what's playing and control playback from anywhere in the app.

---

## Overview

Implement a "mini player" or "now playing bar" that appears at the bottom of the screen when audio is playing. This is a standard pattern used by Spotify, Apple Music, YouTube Music, and other audio apps.

**Why Now**: Phase 3 added background audio - having a mini player makes that feature much more usable by providing persistent controls.

---

## Design Specifications

### Visual Design

```
┌─────────────────────────────────────────────────────┐
│  [Cover]  Book Title                     [▶️/⏸️]     │
│  40x40pt  Author Name (truncated)         44x44pt   │
└─────────────────────────────────────────────────────┘
     16pt      Flexible                      16pt
            spacing                       spacing

Total Height: 72pt (60pt content + 12pt padding)
Background: Blur effect (Material.regular) or solid with shadow
```

### Components Layout

| Component       | Position              | Size     | Details                                             |
| --------------- | --------------------- | -------- | --------------------------------------------------- |
| **Cover Art**   | Left (16pt leading)   | 40x40pt  | Rounded corners (4pt), placeholder if loading fails |
| **Book Info**   | Center                | Flexible | VStack: title (bold) + author (secondary)           |
| **Play/Pause**  | Right (16pt trailing) | 44x44pt  | Standard iOS touch target size                      |
| **Tap Gesture** | Full width            | -        | Navigates to full playback screen                   |

### Color Scheme

**Light Mode:**

- Background: `.systemBackground` with 0.95 opacity
- Title: `.primary`
- Author: `.secondary`
- Shadow: 0.1 opacity

**Dark Mode:**

- Background: `.systemBackground` with 0.95 opacity
- Title: `.primary`
- Author: `.secondary`
- Shadow: 0.2 opacity

---

## Implementation Architecture

### Implementation Approach: Overlay with SafeAreaInset

We'll use SwiftUI's `.safeAreaInset()` modifier instead of `.overlay()` because:

- ✅ Automatically pushes content up (no manual padding needed)
- ✅ Respects safe areas (notch, home indicator)
- ✅ Better integration with ScrollView and List
- ✅ Cleaner code than manual padding calculations

### File Structure

```
ios/BookVault/
├── Components/
│   └── MiniPlayerView.swift          # 🆕 New file
├── Views/
│   └── ContentView.swift             # ✏️ Modified (add safeAreaInset)
└── Services/
    └── AudioPlayerManager.swift      # ✅ No changes needed
```

---

## Implementation Plan

### Step 1: Create MiniPlayerView Component

**File**: `ios/BookVault/Components/MiniPlayerView.swift`

**Requirements:**

- Observe `@StateObject var audioManager = AudioPlayerManager.shared`
- Display cover art, book title, author
- Play/pause button that calls `audioManager.togglePlayPause()`
- Full-width tap gesture to navigate to playback screen
- Handle loading states (cover art async loading)
- Proper safe area handling

**Key Features:**

```swift
// Published properties to observe:
- audioManager.currentBook
- audioManager.isPlaying
- audioManager.isLoading

// Actions:
- Tap anywhere → Navigate to PlaybackView
- Tap play/pause → Toggle playback (no navigation)

// Animations:
- Slide up when audio starts
- Slide down when audio stops
- Smooth transitions
```

### Step 2: Integrate into ContentView

**File**: `ios/BookVault/Views/ContentView.swift`

**Modification:**

```swift
TabView {
    // ... existing tabs
}
.safeAreaInset(edge: .bottom) {
    if AudioPlayerManager.shared.currentBook != nil {
        MiniPlayerView()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: AudioPlayerManager.shared.currentBook)
    }
}
```

**Why `.safeAreaInset()` instead of `.overlay()`:**

- Automatically adds padding to content
- ScrollViews and Lists scroll above mini player naturally
- No manual safe area calculations needed
- Respects TabView, NavigationStack, etc.

### Step 3: Handle Navigation

**Navigation Requirements:**

1. **Tap Mini Player → Show Full Player**
   - Use `NavigationLink` or programmatic navigation
   - Full player should push onto navigation stack
   - Mini player stays visible after returning

2. **Dismiss Full Player → Return to Previous Screen**
   - Standard back button or swipe gesture
   - Mini player remains visible

3. **Stop Playback → Hide Mini Player**
   - Animated slide-down transition
   - Triggered by `AudioPlayerManager.shared.stop()`

**Navigation Pattern:**

```swift
// Option A: NavigationLink (simpler)
NavigationLink(destination: PlaybackView(book: book)) {
    MiniPlayerContent()
}

// Option B: Programmatic (more control)
.onTapGesture {
    navigationPath.append(book)
}
```

### Step 4: Add Animations

**Entrance Animation:**

```swift
.transition(.move(edge: .bottom).combined(with: .opacity))
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentBook != nil)
```

**Exit Animation:**

```swift
// Same transition, SwiftUI handles direction automatically
```

**Play/Pause Button Animation:**

```swift
.scaleEffect(isPressed ? 0.9 : 1.0)
.animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
```

---

## Technical Implementation Details

### Cover Art Loading

**Requirements:**

- Async loading from URL
- Authentication header (JWT token)
- Placeholder while loading
- Error handling (show default icon if fails)
- Cache (URLCache handles this automatically)

**Implementation:**

```swift
AsyncImage(url: URL(string: book.coverUrl)) { phase in
    switch phase {
    case .success(let image):
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    case .failure, .empty:
        Image(systemName: "book.fill")
            .foregroundColor(.secondary)
    @unknown default:
        ProgressView()
    }
}
.frame(width: 40, height: 40)
.clipShape(RoundedRectangle(cornerRadius: 4))
```

**Note**: AsyncImage doesn't support custom headers. We'll need to use a custom loader or pre-fetch the image in AudioPlayerManager.

**Alternative (Better for Auth):**

```swift
// Add to AudioPlayerManager
@Published var currentBookCoverImage: UIImage?

// Update when currentBook changes
private func loadCoverImageForMiniPlayer() {
    Task {
        currentBookCoverImage = await loadCoverImage(from: currentBook?.coverUrl ?? "")
    }
}

// In MiniPlayerView
if let coverImage = audioManager.currentBookCoverImage {
    Image(uiImage: coverImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
} else {
    Image(systemName: "book.fill")
}
```

### Text Truncation

**Requirements:**

- Book title: 1 line, truncate tail
- Author: 1 line, truncate tail
- Responsive to screen width

**Implementation:**

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(book.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(1)
        .truncationMode(.tail)

    Text(book.authors.map { $0.name }.joined(separator: ", "))
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
}
```

### Accessibility

**Requirements:**

- VoiceOver support
- Dynamic Type support
- Haptic feedback on button press
- Accessibility labels

**Implementation:**

```swift
HStack {
    // Content
}
.accessibilityElement(children: .combine)
.accessibilityLabel("Now playing: \(book.title) by \(authors)")
.accessibilityHint("Tap to open full player")

Button(action: { audioManager.togglePlayPause() }) {
    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
}
.accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
```

---

## Edge Cases & Considerations

### Edge Cases to Handle

1. **No Current Book**
   - Mini player should not appear
   - Handled by `if currentBook != nil` check

2. **Loading State**
   - Show placeholder cover art
   - Disable play/pause button? No - AudioPlayerManager handles state

3. **Very Long Titles**
   - Truncate with ellipsis
   - Consider scrolling text (optional enhancement)

4. **iPad Split View**
   - Mini player should scale appropriately
   - Test on iPad Simulator

5. **Landscape Orientation**
   - Mini player should remain at bottom
   - May need to reduce height slightly

6. **Tab Switching**
   - Mini player should persist across all tabs
   - safeAreaInset on ContentView handles this

7. **Deep Navigation**
   - Mini player visible on all screens (Home → Author → Series → Book)
   - safeAreaInset applies to entire TabView

### Performance Considerations

**Optimization:**

- Use `@ObservedObject` instead of `@StateObject` for shared singleton
- Lazy image loading (already async)
- Minimal re-renders (SwiftUI handles this well)
- No need for manual caching (URLCache + AudioPlayerManager state)

**Memory:**

- Cover image cached in AudioPlayerManager
- No additional image caching needed
- Deallocate when audio stops (currentBook = nil)

---

## Testing Checklist

### Visual Testing

- [ ] Mini player appears when playback starts
- [ ] Mini player disappears when playback stops
- [ ] Cover art loads correctly with authentication
- [ ] Text truncates properly on small screens (iPhone SE)
- [ ] Layout looks good on large screens (iPhone 15 Pro Max)
- [ ] Layout adapts to iPad
- [ ] Dark mode styling correct
- [ ] Light mode styling correct

### Functional Testing

- [ ] Tapping mini player navigates to full player
- [ ] Play/pause button works correctly
- [ ] Mini player persists across tab switches
- [ ] Mini player persists during deep navigation
- [ ] Mini player updates when changing books
- [ ] Slide-up animation smooth on appear
- [ ] Slide-down animation smooth on disappear

### Accessibility Testing

- [ ] VoiceOver reads mini player correctly
- [ ] VoiceOver reads play/pause button
- [ ] Dynamic Type increases text size
- [ ] Touch targets are 44x44pt minimum
- [ ] Color contrast meets WCAG standards

### Edge Case Testing

- [ ] Handles missing cover art gracefully
- [ ] Handles very long book titles
- [ ] Handles very long author names
- [ ] Works in landscape orientation
- [ ] Works on iPhone SE (smallest screen)
- [ ] Works on iPad
- [ ] Doesn't interfere with keyboard

---

## Implementation Steps (Developer Checklist)

### Phase 3.5 Implementation Order

1. **Setup** (5 min)
   - [ ] Create new branch: `git checkout -b feature/ios-phase3.5-mini-player`
   - [ ] Create new file: `ios/BookVault/Components/MiniPlayerView.swift`

2. **Implement MiniPlayerView** (30 min)
   - [ ] Create SwiftUI view structure
   - [ ] Add cover art with AsyncImage or cached UIImage
   - [ ] Add book title and author text
   - [ ] Add play/pause button
   - [ ] Add tap gesture for navigation
   - [ ] Style with colors, spacing, shadows

3. **Integrate into ContentView** (10 min)
   - [ ] Add `.safeAreaInset()` modifier to TabView
   - [ ] Add conditional rendering based on `currentBook != nil`
   - [ ] Add animations (slide-up/down, opacity)

4. **Handle Navigation** (15 min)
   - [ ] Implement navigation to PlaybackView on tap
   - [ ] Test navigation flow (forward and back)
   - [ ] Ensure mini player persists after navigation

5. **Polish & Accessibility** (20 min)
   - [ ] Add accessibility labels
   - [ ] Test VoiceOver
   - [ ] Test Dynamic Type
   - [ ] Add haptic feedback (optional)
   - [ ] Fine-tune animations

6. **Testing** (15 min)
   - [ ] Test on iPhone Simulator (various sizes)
   - [ ] Test on iPad Simulator
   - [ ] Test dark mode and light mode
   - [ ] Test all edge cases from checklist

7. **Commit & Document** (10 min)
   - [ ] Run XcodeGen: `cd ios && xcodegen generate`
   - [ ] Build and verify: `xcodebuild -scheme BookVault ...`
   - [ ] Commit with detailed message
   - [ ] Update CHANGELOG or STATUS.md

**Total Estimated Time**: 1.5-2 hours

---

## Code Snippets

### MiniPlayerView.swift (Full Implementation)

```swift
//
//  MiniPlayerView.swift
//  BookVault
//
//  Phase 3.5: Mini Player UI
//

import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var audioManager = AudioPlayerManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let book = audioManager.currentBook {
            NavigationLink(destination: PlaybackView(book: book)) {
                HStack(spacing: 12) {
                    // Cover Art
                    coverArt(for: book)

                    // Book Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        Text(book.authors.map { $0.name }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Play/Pause Button
                    Button(action: {
                        audioManager.togglePlayPause()
                    }) {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(.systemBackground).opacity(0.95))
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 8, y: -2)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing: \(book.title)")
            .accessibilityHint("Tap to open full player")
        }
    }

    @ViewBuilder
    private func coverArt(for book: Book) -> some View {
        // Option 1: If AudioPlayerManager provides cached image
        if let coverImage = audioManager.currentBookCoverImage {
            Image(uiImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // Placeholder
            Image(systemName: "book.fill")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Preview
#Preview("Mini Player - Playing") {
    MiniPlayerView()
        .previewLayout(.sizeThatFits)
}

#Preview("Mini Player - Paused") {
    MiniPlayerView()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
}
```

### ContentView.swift Modification

```swift
// Add this modifier to the TabView
TabView {
    // ... existing tabs
}
.safeAreaInset(edge: .bottom) {
    if AudioPlayerManager.shared.currentBook != nil {
        MiniPlayerView()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: AudioPlayerManager.shared.currentBook != nil)
    }
}
```

### AudioPlayerManager.swift Enhancement (Optional)

```swift
// Add this property to cache cover image for mini player
@Published var currentBookCoverImage: UIImage?

// Update this in the play() method after setting currentBook
private func updateCoverImageForMiniPlayer() {
    guard let book = currentBook else {
        currentBookCoverImage = nil
        return
    }

    Task { @MainActor in
        currentBookCoverImage = await loadCoverImage(from: book.coverUrl)
    }
}

// Call from play() method
func play(book: Book) {
    // ... existing code
    currentBook = book
    updateCoverImageForMiniPlayer()
    // ... rest of existing code
}
```

---

## Success Criteria

Phase 3.5 is complete when:

✅ Mini player appears when playback starts
✅ Mini player disappears when playback stops
✅ Tapping mini player navigates to full player
✅ Play/pause button works from mini player
✅ Cover art loads with authentication
✅ Text truncates properly on all screen sizes
✅ Works on all tabs and deep navigation
✅ Smooth slide-up/down animations
✅ Accessibility labels work with VoiceOver
✅ Looks good in dark mode and light mode
✅ No layout issues on iPhone SE to iPad

---

## Future Enhancements (Post-Phase 3.5)

Optional improvements for later:

1. **Swipe Gestures**
   - Swipe up to expand to full player
   - Swipe down to dismiss (close audio)

2. **Progress Indicator**
   - Thin progress bar at top of mini player
   - Shows playback position

3. **Skip Buttons**
   - Add skip forward/backward buttons (15 or 30 seconds)
   - May make UI crowded on small screens

4. **Animated Cover Art**
   - Subtle rotation or pulse during playback
   - Like vinyl record spinning

5. **Scrolling Marquee**
   - For very long titles, scroll horizontally
   - After 2 seconds of display

6. **Haptic Feedback**
   - Light haptic on play/pause
   - Medium haptic on tap to expand

---

## Related Documentation

- [Phase 3: Background Audio & Lock Screen](../implementation-phases.md#phase-3-background-audio--lock-screen)
- [Phase 4: Progress Sync](../implementation-phases.md#phase-4-progress-sync)
- [AudioPlayerManager Architecture](../architecture.md#audio-playback-layer)
- [Component Guide](../../component-guide.md)

---

**Implementation Date**: TBD
**Implemented By**: Claude Code + Demetri
**Status**: Ready for Implementation
