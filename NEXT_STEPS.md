# Next Steps: iOS Development

**Last Updated**: December 27, 2025
**Current Status**: ✅ VS Code iOS environment complete and verified

---

## ✅ Setup Complete!

All VS Code iOS development tools are configured and working:

- ✅ Swift extension installed and configured
- ✅ Sweetpad extension installed
- ✅ Build server config generated (`buildServer.json`)
- ✅ Debugging configuration created (`.vscode/launch.json`)
- ✅ App builds successfully
- ✅ App runs in iOS Simulator
- ✅ IntelliSense working for Swift code

**VS Code iOS Workflow Verified**:

- Build: Command Palette → `Sweetpad: Build`
- Run: Command Palette → `Sweetpad: Run (for debugging)`
- Debug: Press F5 or use Debug panel

---

## After VS Code Setup Complete

### Phase 1: Authentication & Browsing Implementation

**Goal**: Build login and book browsing functionality

**Prerequisites**:

- ✅ VS Code iOS environment set up
- ✅ Backend running (`npm run dev`)
- ✅ Test user available (test@example.com / password123)

**Implementation Steps**:

#### 1. Build Core Services (Backend Integration)

Create these Swift files in `ios/BookVault/Services/`:

- **APIClient.swift** - Network layer with authentication
  - Base URL configuration
  - JWT token management
  - Request/response handling
  - Error handling

- **AuthManager.swift** - Authentication service
  - Login/logout functionality
  - Keychain storage for JWT tokens
  - Token refresh logic
  - Session management

#### 2. Create Authentication Views

Create these Swift files in `ios/BookVault/Views/Auth/`:

- **LoginView.swift** - Login screen
  - Email/password input fields
  - Login button
  - Error message display
  - Loading state

#### 3. Create Book Browsing Views

Create these Swift files in `ios/BookVault/Views/Books/`:

- **BooksListView.swift** - Book grid/list
  - Paginated book display
  - Cover image loading
  - Pull to refresh
  - Search integration (Phase 6)

- **BookDetailView.swift** - Book details
  - Full metadata display
  - Author/narrator info
  - Series information
  - Play button (links to Phase 2)

#### 4. Update App Structure

Modify existing files:

- **BookVaultApp.swift** - App entry point
  - Add AuthManager as environment object
  - Conditional navigation (login vs books list)
  - Deep linking setup

- **ContentView.swift** - Root view
  - Check authentication state
  - Show LoginView or BooksListView

#### 5. Testing Checklist

- [ ] Can log in with test@example.com
- [ ] Tokens stored securely in Keychain
- [ ] Books list loads from backend
- [ ] Book covers display correctly
- [ ] Can navigate to book details
- [ ] All metadata displays correctly
- [ ] Logout works and clears tokens

---

## Prompt to Start Phase 1

Copy this prompt to begin implementation:

```
I'm ready to start Phase 1: Authentication & Browsing for the iOS app.

Please implement the following in order:

1. Create APIClient.swift - the core networking layer that:
   - Connects to http://localhost:3000 (backend)
   - Handles JWT authentication headers
   - Uses the generated models from OpenAPI spec
   - Has proper error handling

2. Create AuthManager.swift - authentication service that:
   - Handles login via POST /api/auth/mobile/login
   - Stores JWT tokens in iOS Keychain
   - Provides authentication state to views
   - Handles token refresh

3. Create LoginView.swift - a simple login screen with:
   - Email and password text fields
   - Login button
   - Error message display
   - SwiftUI best practices

4. Update BookVaultApp.swift and ContentView.swift to:
   - Check if user is authenticated
   - Show LoginView if not authenticated
   - Show placeholder for books list if authenticated

Start with step 1 (APIClient.swift) and we'll work through each component.
Use the generated Swift models from ios/BookVault/Generated/Models/ for type safety.
```

---

## Development Workflow

### Daily Setup

```bash
# Terminal 1: Start backend
docker-compose up -d
npm run dev

# Terminal 2 (optional): Watch API changes
npm run api:watch

# VS Code: Open project
# - Edit Swift files with full IntelliSense
# - Build with ⌘⇧B or Sweetpad commands
# - Debug with F5
```

### Making Changes

1. Edit Swift files in VS Code
2. Build: Command Palette → `Sweetpad: Build`
3. Run: Command Palette → `Sweetpad: Run`
4. Debug: Set breakpoints, press F5
5. Commit: Use VS Code git integration

### API Changes Workflow

If you need to modify API endpoints:

1. Update `docs/api/openapi.yaml`
2. Run `npm run api:generate:swift`
3. New Swift models appear in `ios/BookVault/Generated/Models/`
4. Update Swift code to use new models
5. Test integration

---

## Phase Roadmap Overview

After Phase 1, the remaining phases are:

**Phase 2: Audio Playback** (~2 weeks)

- Stream audio from S3 using AVPlayer
- Play/pause/seek controls
- Now playing screen

**Phase 3: Background Audio** (~1 week)

- Background playback mode
- Lock screen controls
- Interruption handling

**Phase 4: Progress Sync** (~1 week)

- Auto-save playback position
- Sync to backend
- Resume across devices

**Phase 5: Chapter Navigation** (~1 week)

- Chapter list display
- Jump to chapter
- Chapter progress

**Phase 6: Search & Browse** (~2 weeks)

- Search functionality
- Browse by author/narrator/series
- Filtering

**Phase 7: User Lists** (~1 week)

- Library management
- Add/remove books

**Phase 8: Offline Downloads** (~2 weeks, optional)

- Download for offline playback
- Manage downloads

---

## Quick Reference

**Documentation**:

- [VS Code iOS Setup](docs/mobile/vscode-ios-setup.md) - Complete VS Code setup guide
- [iOS Development Plan](docs/mobile-ios-plan.md) - Full implementation plan
- [API Quick Reference](docs/api-quick-ref.md) - Backend endpoints
- [iOS Backend Sync](docs/ios-backend-sync.md) - API sync tracker

**Test Credentials**:

- Email: `test@example.com`
- Password: `password123`

**Backend URL**: `http://localhost:3000`

**Key Commands**:

- Build: `Sweetpad: Build`
- Run: `Sweetpad: Run`
- Debug: F5 (after launch.json setup)
- Generate Swift models: `npm run api:generate:swift`

---

## Questions?

Refer to:

1. [docs/mobile/vscode-ios-setup.md](docs/mobile/vscode-ios-setup.md) for VS Code issues
2. [docs/mobile-ios-plan.md](docs/mobile-ios-plan.md) for architecture questions
3. [docs/STATUS.md](docs/STATUS.md) for project status
4. Test fixtures in `test-fixtures/` for API response examples

---

**Current Step**: Complete VS Code debugging setup, then use the prompt above to start Phase 1! 🚀
