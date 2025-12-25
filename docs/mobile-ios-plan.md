# iOS Mobile App - Implementation Plan

**Status**: Planning
**Priority**: Post-deployment
**Last Updated**: December 24, 2025

---

## Overview

Native iOS app for Book Vault audiobook library, built on the existing API-first backend. The web app backend is already mobile-ready with JWT authentication, RESTful JSON endpoints, and S3 streaming support.

## Technology Decision

**Native Swift + SwiftUI** (chosen over React Native)

**Rationale**:

- Best performance for audio streaming and background playback
- Native iOS features: CarPlay, background audio modes, interruption handling
- Superior battery optimization vs web-based alternatives
- SwiftUI provides modern, declarative UI development
- Full access to AVFoundation for professional audio playback
- Better offline support with local storage

## Backend Readiness ✅

The web app backend is **fully prepared** for mobile:

1. **Authentication**: JWT tokens (mobile-compatible)
   - Web: Secure cookies for sessions
   - Mobile: JWT in Authorization headers
   - Refresh token mechanism ready

2. **API Design**: RESTful JSON (all endpoints return JSON)
   - See [architecture.md](architecture.md) for complete endpoint list
   - Pagination support on all list endpoints
   - CORS configuration for mobile origins

3. **Media Streaming**: S3 with range request support
   - Audio: HTTP range requests for seeking (required for iOS AVPlayer)
   - Images: Direct S3 URLs with caching headers
   - Automatic fallback to filesystem in development

4. **Data Models**: Shared types from TypeScript can inform Swift models
   - Book, Author, Narrator, Series, Category
   - UserProgress, UserList, Chapter
   - JSON responses map cleanly to Swift Codable structs

## Core Features (MVP)

### Phase 1: Authentication & Browsing

**Objective**: Users can log in and browse their audiobook library

**Key Tasks**:

- Swift project setup with SwiftUI
- API client with URLSession (JWT token management)
- Login screen with credential validation
- Home screen with book grid (fetch from `/api/books`)
- Book detail screen with metadata
- Navigation structure (TabView + NavigationStack)

**Acceptance Criteria**:

- User can log in with existing web credentials
- User can browse books with cover images
- User can view book details (title, author, narrator, description)
- App handles network errors gracefully

**Stop Point**: Commit code, test on device, clear context

---

### Phase 2: Audio Playback (Basic)

**Objective**: Users can stream and play audiobooks

**Key Tasks**:

- AVPlayer integration with remote URL streaming
- Playback controls (play, pause, seek)
- Playback speed control (0.5x - 2.5x)
- Volume control
- Now Playing screen UI
- Progress bar with time display

**Acceptance Criteria**:

- User can start playback from book detail
- User can control playback (play/pause/seek)
- User can adjust playback speed
- Audio streams without buffering issues
- Playback position updates in real-time

**Stop Point**: Test audio streaming, verify seek performance

---

### Phase 3: Background Audio & Lock Screen

**Objective**: Audio continues when app is backgrounded

**Key Tasks**:

- Background audio mode configuration (Info.plist)
- AVAudioSession setup for background playback
- Lock screen controls (MPNowPlayingInfoCenter)
- Remote command center (play/pause/skip from lock screen)
- Interruption handling (phone calls, alarms)
- Route change handling (headphones disconnect)

**Acceptance Criteria**:

- Audio continues when screen locks
- Lock screen shows cover art, title, author
- Lock screen controls work (play, pause, skip)
- Audio pauses on interruption, resumes after
- Audio handles headphone disconnect properly

**Stop Point**: Test background audio, verify interruption handling

---

### Phase 4: Progress Sync

**Objective**: Playback position syncs with backend

**Key Tasks**:

- Integrate with `/api/progress` endpoints
- Auto-save position every 10 seconds
- Load saved position on playback start
- Mark book as completed when finished
- Continue listening section on home screen
- Progress indicators on book cards

**Acceptance Criteria**:

- Position saves automatically during playback
- Position resumes correctly on app restart
- Books marked as completed sync to backend
- Continue listening section shows recent books
- Progress syncs between web and mobile

**Stop Point**: Test sync behavior, verify cross-platform consistency

---

### Phase 5: Chapter Navigation

**Objective**: Users can navigate by chapter

**Key Tasks**:

- Fetch chapters from `/api/books/:id/chapters`
- Chapter list UI in Now Playing screen
- Skip to chapter functionality
- Current chapter highlighting
- Chapter metadata display (title, duration)

**Acceptance Criteria**:

- User can view chapter list
- User can skip to any chapter
- Current chapter is highlighted during playback
- Chapter transitions are smooth

**Stop Point**: Test chapter navigation, verify timing accuracy

---

### Phase 6: Search & Browse

**Objective**: Users can search and browse by author/series/narrator

**Key Tasks**:

- Search screen with `/api/search` integration
- Browse by authors (`/api/browse/authors`)
- Browse by series (`/api/browse/series`)
- Browse by narrators (`/api/browse/narrators`)
- Browse by categories (`/api/browse/categories`)
- Author/Series/Narrator detail screens

**Acceptance Criteria**:

- User can search across books, authors, narrators
- User can browse by author/series/narrator/category
- Search results are relevant and fast
- Detail screens show all related books

**Stop Point**: Test search performance, verify filtering

---

### Phase 7: User Lists

**Objective**: Users can create and manage custom lists

**Key Tasks**:

- My Library screen (show user's added books)
- Add/remove books from library
- Custom lists UI (Want to Listen, Favorites)
- Create/edit/delete lists
- Drag-to-reorder books in lists
- Sync with `/api/library/*` endpoints

**Acceptance Criteria**:

- User can add/remove books from library
- User can create custom lists
- User can reorder books in lists
- Lists sync between web and mobile

**Stop Point**: Test list management, verify sync

---

### Phase 8: Offline Downloads (Optional)

**Objective**: Users can download books for offline listening

**Key Tasks**:

- Download manager (URLSession background downloads)
- Local storage management (file system)
- Download progress UI
- Offline playback mode (local files)
- Storage limit management
- Delete downloaded books

**Acceptance Criteria**:

- User can download books for offline use
- Downloads work in background
- Offline playback works without network
- Storage usage is visible and manageable

**Stop Point**: Test offline mode, verify storage limits

---

## Technical Architecture

### App Structure

```
BookVault/
├── App/
│   ├── BookVaultApp.swift           # App entry point
│   └── AppState.swift                # Global state management
├── Features/
│   ├── Auth/
│   │   ├── Views/
│   │   │   └── LoginView.swift
│   │   └── AuthService.swift
│   ├── Home/
│   │   └── Views/
│   │       └── HomeView.swift
│   ├── Browse/
│   │   └── Views/
│   │       ├── BooksListView.swift
│   │       ├── BookDetailView.swift
│   │       └── SearchView.swift
│   ├── Player/
│   │   ├── Views/
│   │   │   └── NowPlayingView.swift
│   │   └── AudioPlayerService.swift
│   └── Library/
│       └── Views/
│           └── LibraryView.swift
├── Networking/
│   ├── APIClient.swift               # URLSession wrapper
│   ├── Endpoints.swift               # API endpoint definitions
│   └── Models/                       # Codable response models
│       ├── Book.swift
│       ├── Author.swift
│       └── UserProgress.swift
├── Services/
│   ├── AuthenticationService.swift  # JWT token management
│   ├── AudioPlayerService.swift     # AVPlayer wrapper
│   └── DownloadService.swift        # Offline downloads
└── Resources/
    └── Assets.xcassets
```

### Key Services

**AuthenticationService**:

- JWT token storage (Keychain)
- Token refresh mechanism
- Login/logout flows

**AudioPlayerService**:

- AVPlayer management
- Background audio setup
- Lock screen integration
- Progress tracking

**APIClient**:

- URLSession configuration
- Request/response handling
- Error handling
- Authentication headers

**DownloadService** (Phase 8):

- Background download tasks
- File system management
- Progress tracking

## API Integration

### Authentication Flow

```swift
// Login
POST /api/auth/login
Body: { email, password }
Response: { token, user: { id, email } }

// Store token in Keychain
// Add to Authorization header: "Bearer {token}"
```

### Data Fetching Examples

```swift
// Get books
GET /api/books?page=1&limit=20
Response: { books: [...], pagination: {...} }

// Get book detail
GET /api/books/{id}
Response: { id, title, authors, ... }

// Get user progress
GET /api/progress?bookId={id}
Response: { positionSeconds, completed, lastPlayed }

// Update progress
POST /api/progress
Body: { bookId, positionSeconds, completed }
```

## iOS-Specific Considerations

### Background Audio

- Add "Audio, AirPlay, and Picture in Picture" background mode
- Configure AVAudioSession for playback
- Handle interruptions (calls, alarms)
- Support remote control events

### Lock Screen Integration

```swift
// MPNowPlayingInfoCenter
nowPlayingInfo = [
    MPMediaItemPropertyTitle: book.title,
    MPMediaItemPropertyArtist: book.authors.joined(", "),
    MPMediaItemPropertyArtwork: coverArt,
    MPMediaItemPropertyPlaybackDuration: duration,
    MPNowPlayingInfoPropertyElapsedPlaybackTime: position
]
```

### CarPlay (Future)

- CarPlay audio app template
- Simplified UI for driving safety
- Voice control integration

### Offline Storage

- Use FileManager for local audio files
- Store in app's Documents directory
- Respect iOS storage limits
- Clean up when space is low

## Testing Strategy

### Unit Tests

- API client request/response handling
- Authentication service token management
- Progress sync logic
- Download manager file operations

### UI Tests

- Login flow
- Book browsing and search
- Playback controls
- Chapter navigation

### Manual Testing

- Background audio on real device
- Lock screen controls
- Interruption handling (phone calls)
- Network connectivity changes
- Different iOS versions (16+)

## Deployment

### App Store Submission

1. Apple Developer account (individual or organization)
2. App Store Connect setup
3. App ID and provisioning profiles
4. TestFlight beta testing
5. App Store review submission

### Requirements

- iOS 16+ minimum deployment target
- Privacy policy (required for App Store)
- Terms of service
- App icon and screenshots
- App Store description and metadata

## Future Enhancements

### Post-MVP Features

- CarPlay integration
- Widgets (Continue Listening, Recent Books)
- Share audiobook recommendations
- Sleep timer
- Bookmarks and notes
- iCloud sync for downloads
- Siri integration ("Play [book title]")
- AirPlay support
- Picture-in-Picture mode

## Success Metrics

- User can browse entire library
- Audio playback is smooth and reliable
- Background audio works consistently
- Progress syncs accurately with web app
- App feels native and responsive
- Battery usage is acceptable
- Network usage is efficient

---

**Next Steps**: Complete web app deployment to AWS, then begin Phase 1 of iOS development.
