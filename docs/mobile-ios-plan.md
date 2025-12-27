# iOS Mobile App - Implementation Plan

**Status**: Planning
**Priority**: Post-deployment
**Last Updated**: December 25, 2025

> **TL;DR (30 seconds)**
>
> - **Tech**: Native Swift + SwiftUI (best for audio performance)
> - **Backend**: ✅ Already mobile-ready (JWT, REST API, S3 streaming)
> - **Development**: Monorepo with OpenAPI-driven code generation
> - **Workflow**: VS Code (backend) + Xcode (iOS) with shared API contracts
> - **Plan**: 8 phased rollout (Auth → Playback → Background → Sync → Lists → Offline)
> - **Timeline**: Start after AWS deployment
> - **Key features**: AVPlayer streaming, background audio, offline downloads, progress sync

**Jump to**: [Development Workflow](#development-workflow) · [Technology Decision](#technology-decision) · [Implementation Phases](#implementation-phases)

---

## Overview

Native iOS app for Book Vault audiobook library, built on the existing API-first backend. The web app backend is already mobile-ready with JWT authentication, RESTful JSON endpoints, and S3 streaming support.

This plan includes a comprehensive **dual-platform development strategy** that optimizes for AI-assisted development across both backend (TypeScript/Next.js) and iOS (Swift/SwiftUI) codebases.

## Technology Decision

**Native Swift + SwiftUI** (chosen over React Native)

**Rationale**:

- Best performance for audio streaming and background playback
- Native iOS features: CarPlay, background audio modes, interruption handling
- Superior battery optimization vs web-based alternatives
- SwiftUI provides modern, declarative UI development
- Full access to AVFoundation for professional audio playback
- Better offline support with local storage

## Development Workflow

### Repository Structure: Monorepo (Recommended)

```
book-vault/
├── app/                      # Next.js app (current root)
├── components/               # React components
├── lib/                      # Backend utilities
├── prisma/                   # Database schema
├── ios/                      # 🆕 Xcode project
│   ├── BookVault.xcodeproj
│   ├── BookVault/
│   │   ├── Views/
│   │   ├── Models/           # Generated from OpenAPI
│   │   └── Services/
│   └── BookVaultTests/
├── docs/
│   ├── api/                  # 🆕 OpenAPI specifications
│   │   ├── openapi.yaml      # API contract (source of truth)
│   │   └── README.md         # API documentation
│   ├── mobile/               # 🆕 iOS-specific docs
│   │   ├── development-workflow.md
│   │   ├── api-integration.md
│   │   └── implementation-phases.md
│   └── ios-backend-sync.md   # 🆕 Sync status tracker
└── test-fixtures/            # 🆕 Shared test data (backend + iOS)
    ├── books-list.json
    ├── book-detail.json
    └── user-progress.json
```

**Why Monorepo**:

- Single `git clone` for both projects
- Atomic commits across backend + iOS changes
- Easier for Claude Code to see both codebases
- Shared documentation and test fixtures
- Simpler for solo/small team development

### Development Environment

**Backend (VS Code)**:

```bash
# Terminal 1: Backend with network access for iOS
npm run dev:mobile              # Next.js on 0.0.0.0:3000

# Terminal 2: Watch API specs (auto-regenerate types)
npm run api:watch               # Regenerates TypeScript + Swift on changes

# Terminal 3: Tests
npm run test:watch
```

**iOS (Xcode)**:

- Run iOS app in Simulator (points to `http://localhost:3000`)
- Build/run for debugging
- Interface previews

**Tooling Setup**:

```bash
# Add to package.json
{
  "scripts": {
    "dev:mobile": "next dev --hostname 0.0.0.0",
    "api:validate": "redocly lint docs/api/openapi.yaml",
    "api:docs": "redocly build-docs docs/api/openapi.yaml -o docs/api/api-reference.html",
    "api:generate": "npm run api:generate:ts && npm run api:generate:swift",
    "api:generate:ts": "openapi-typescript docs/api/openapi.yaml -o lib/api-types.ts",
    "api:generate:swift": "openapi-generator generate -i docs/api/openapi.yaml -g swift5 -o ios/BookVault/Generated",
    "api:watch": "nodemon --watch docs/api/openapi.yaml --exec 'npm run api:generate'",
    "docs:generate": "npm run api:generate && npm run api:docs"
  }
}

# Install tools (✅ Phase 0 complete - using @redocly/cli instead of deprecated swagger-cli)
npm install --save-dev openapi-typescript @redocly/cli nodemon yaml
brew install openapi-generator
```

### API Contract Management (CRITICAL)

**OpenAPI as Single Source of Truth**:

1. **Update API contract first** (`docs/api/openapi.yaml`)
2. **Generate code** for both platforms (`npm run api:generate`)
3. **Implement** using generated types
4. **Test** both backend and iOS
5. **Commit atomically** (both changes together)

**Example OpenAPI Spec**:

```yaml
# docs/api/openapi.yaml
openapi: 3.0.0
info:
  title: Book Vault API
  version: 1.0.0
paths:
  /api/books:
    get:
      summary: Get all books
      parameters:
        - name: page
          in: query
          schema:
            type: integer
        - name: limit
          in: query
          schema:
            type: integer
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/BookListResponse'
components:
  schemas:
    Book:
      type: object
      required: [id, title, asin]
      properties:
        id: { type: string, format: uuid }
        title: { type: string }
        asin: { type: string }
        # ... rest of schema
    BookListResponse:
      type: object
      properties:
        books:
          type: array
          items:
            $ref: '#/components/schemas/Book'
        pagination:
          $ref: '#/components/schemas/Pagination'
```

**Benefits**:

- TypeScript and Swift stay in sync automatically
- Documentation is always up-to-date
- Prevents API contract drift
- Reduces manual typing errors

### Development Workflow for API Changes

**Scenario: Adding a new "Playlists" feature**

```bash
# Step 1: Design API in OpenAPI (5 min)
# Edit docs/api/openapi.yaml - add /api/playlists endpoint

# Step 2: Generate Types (1 min)
npm run api:generate

# Step 3: Implement Backend (VS Code, 30 min)
# Create app/api/playlists/route.ts

# Step 4: Test Backend (VS Code, 10 min)
npm test -- playlists
curl http://localhost:3000/api/playlists

# Step 5: Implement iOS (Xcode, 30 min)
# Use generated Swift models in PlaylistService.swift

# Step 6: Test Integration (Both, 10 min)
# Backend: npm run dev:mobile
# iOS: Run in Simulator, verify data flows

# Step 7: Commit Atomically (VS Code, 2 min)
git add .
git commit -m "feat: add playlists feature (backend + iOS)"
```

**Total time**: ~90 minutes for full-stack feature

### VS Code + Xcode Workflow

> **NEW**: VS Code can now handle iOS development directly with proper tooling! See Option D below.

**Option A: Dual Monitor** (Recommended - Traditional)

```
Monitor 1: VS Code (backend code, git, docs)
Monitor 2: Xcode (iOS) + iOS Simulator
```

**Option B: Single Monitor** (Use macOS Desktops - Traditional)

```
Desktop 1: VS Code (backend)
Desktop 2: Xcode (iOS)
Desktop 3: Browser (Postman, docs)

Keyboard: Ctrl + → to switch desktops
```

**Option C: VS Code Primary** (Minimal Xcode - Traditional)

```
VS Code: Backend dev, Swift editing, git, docs
Xcode: Only for building/running iOS app

# Install official Swift extension
# Extension ID: swiftlang.swift-vscode
```

**Option D: VS Code All-in-One** (⭐ RECOMMENDED - Fully Integrated)

```
VS Code: Backend + iOS development, git, debugging, all editing
Xcode: OPTIONAL - Only for Interface Builder/Storyboards (if needed)

# Install required tools
brew install xcode-build-server

# Install VS Code extensions
# 1. Official Swift extension: swiftlang.swift-vscode (already installed ✅)
# 2. Sweetpad extension for iOS support
```

**VS Code iOS Setup (Option D)**:

This approach enables full iOS development within VS Code, including:

- ✅ Swift code completion and IntelliSense
- ✅ Build and run iOS apps
- ✅ Full debugging with breakpoints
- ✅ GitHub Copilot integration for Swift
- ✅ Unified backend + iOS workflow

**Configuration Steps**:

1. **Install Sweetpad Extension**:
   - Open Extensions in VS Code
   - Search for "Sweetpad"
   - Install the extension

2. **Configure Workspace** (`.vscode/settings.json`):

   ```json
   {
     "sweetpad.build.xcodeProjectPath": "ios/BookVault.xcodeproj",
     "sweetpad.build.scheme": "BookVault",
     "sweetpad.build.buildConfiguration": "Debug"
   }
   ```

   **Note**: Use `xcodeProjectPath` for `.xcodeproj` files (not `xcodeWorkspacePath`)

3. **Generate Build Server Config**:
   - Open Command Palette (⌘⇧P)
   - Run: `Sweetpad: Generate Build Server Config`
   - Creates `buildServer.json` automatically

4. **Setup Debugging** (`.vscode/launch.json`):
   - Open Debug pane
   - Click "create a launch.json file"
   - Select `Sweetpad (LLDB)` template
   - Auto-configures iOS debugging

**What Works in VS Code**:

- ✅ Swift syntax highlighting and code completion
- ✅ Jump to definition, peek definition, find references
- ✅ Build and run iOS apps directly
- ✅ Full LLDB debugging (breakpoints, variable inspection, step through)
- ✅ GitHub Copilot integration (superior to Xcode's Copilot extension)
- ✅ Git integration and version control
- ✅ Unified terminal for backend + iOS

**Limitations** (Must use Xcode for):

- ❌ SwiftUI Previews (Xcode-only feature)
- ❌ Interface Builder / Storyboards (if used)
- ❌ Asset catalog visual editing (can edit JSON directly)
- ❌ App Store submission (use Xcode Archive)

**Recommended Workflow**:

- Use VS Code for all development (backend + iOS code editing)
- Use Xcode only when you need SwiftUI Previews
- Leverage Copilot for AI-assisted Swift development in VS Code

**Common Setup Issues**:

1. **Missing `contents.xcworkspacedata` file**:
   - **Symptom**: Sweetpad errors when trying to build/run
   - **Solution**: Xcode auto-generates this file when opening `.xcodeproj` for the first time. If missing, create manually:
     ```xml
     <?xml version="1.0" encoding="UTF-8"?>
     <Workspace version="1.0">
       <FileRef location="self:"></FileRef>
     </Workspace>
     ```
   - **Location**: `ios/BookVault.xcodeproj/project.xcworkspace/contents.xcworkspacedata`

2. **App build succeeds but run fails**:
   - **Symptom**: "App path does not exist. Have you built the app?"
   - **Solution**: Build the app first using Command Palette → "Sweetpad: Build"
   - Then run using "Sweetpad: Run (for debugging)"

3. **IntelliSense not working**:
   - **Solution**: Ensure `buildServer.json` exists (run "Sweetpad: Generate Build Server Config")
   - Add to `.gitignore` since it contains machine-specific paths

**See Also**: [docs/mobile/vscode-ios-setup.md](mobile/vscode-ios-setup.md) for complete VS Code setup guide

### Testing Strategy

**Backend (API Integration Tests)**:

```typescript
// __tests__/api/mobile-integration.test.ts
describe('Mobile API Integration', () => {
  test('GET /api/books returns mobile-friendly response', async () => {
    const response = await fetch('http://localhost:3000/api/books');
    const data = await response.json();

    // Validate against OpenAPI schema
    expect(data).toMatchSchema(bookListSchema);

    // Mobile-specific checks
    expect(data.books[0].coverUrl).toMatch(/^https?:\/\//); // Absolute URLs
    expect(data.books[0].audioUrl).toMatch(/^https?:\/\//);
  });
});
```

**iOS (Unit Tests with Mocks)**:

```swift
// BookVaultTests/Services/BookServiceTests.swift
class BookServiceTests: XCTestCase {
    func testFetchBooks() async throws {
        let mockSession = MockURLSession()
        let service = BookService(session: mockSession)

        // Load fixture from shared test-fixtures/
        mockSession.nextResponse = loadFixture("books-list.json")

        let books = try await service.fetchBooks()
        XCTAssertEqual(books.count, 10)
    }
}
```

**Shared Test Fixtures**:

```
test-fixtures/
├── books-list.json      # Used by both backend and iOS tests
├── book-detail.json
└── user-progress.json
```

### Recommended Tools

1. **Postman/Insomnia** (API testing before iOS integration)
2. **Charles Proxy** (debug iOS ↔ Backend traffic)
3. **OpenAPI Generator** (code generation)
4. **Swagger UI** (interactive API docs)

### Git Workflow with Dual Codebases

**Pre-commit Hooks** (`.husky/pre-commit`):

```bash
#!/bin/sh
# Validate API contract
npm run api:validate

# Backend checks
npm run type-check
npm run lint

# iOS build check (fast validation)
cd ios && xcodebuild -scheme BookVault \
  -destination 'generic/platform=iOS' \
  -quiet || exit 1
```

**Commit Messages** (atomic changes):

```bash
# Both platforms changed together
git commit -m "feat(playlists): add playlist feature (backend + iOS)"

# Backend only
git commit -m "feat(api): add playlist sorting endpoint"

# iOS only
git commit -m "feat(ios): add pull-to-refresh on playlist screen"
```

## Backend Readiness ✅

The web app backend is **fully prepared** for mobile:

1. **Authentication**: JWT tokens (mobile-compatible)
   - Web: Secure cookies for sessions
   - Mobile: JWT in Authorization headers
   - Refresh token mechanism ready

2. **API Design**: RESTful JSON (all endpoints return JSON)
   - See [api-quick-ref.md](api-quick-ref.md) for complete endpoint list
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

## Implementation Phases

**Detailed implementation phases**: See [docs/mobile/implementation-phases.md](mobile/implementation-phases.md)

**Quick overview**:

1. **Phase 1**: Authentication & Browsing
2. **Phase 2**: Audio Playback (Basic)
3. **Phase 3**: Background Audio & Lock Screen
4. **Phase 4**: Progress Sync
5. **Phase 5**: Chapter Navigation
6. **Phase 6**: Search & Browse
7. **Phase 7**: User Lists
8. **Phase 8**: Offline Downloads (Optional)

## Architecture

**Detailed architecture**: See [docs/mobile/architecture.md](mobile/architecture.md)

**Quick overview**:

- SwiftUI for UI layer
- AVPlayer for audio playback
- URLSession for networking
- Keychain for JWT storage
- FileManager for offline downloads

## API Integration

**Detailed API integration guide**: See [docs/mobile/api-integration.md](mobile/api-integration.md)

**Quick reference**:

- Authentication flow (JWT tokens)
- Data fetching patterns
- Progress sync mechanism
- Error handling strategy

## iOS-Specific Features

**Detailed iOS considerations**: See [docs/mobile/ios-features.md](mobile/ios-features.md)

**Key features**:

- Background audio mode
- Lock screen controls (MPNowPlayingInfoCenter)
- Interruption handling (calls, alarms)
- CarPlay support (future)

## Deployment

**App Store Requirements**:

- Apple Developer account ($99/year)
- Privacy policy (required)
- Terms of service
- App Store assets (icon, screenshots)
- TestFlight beta testing

**Minimum Requirements**:

- iOS 16+ deployment target
- Privacy manifest (App Privacy Details)

## Success Metrics

- User can browse entire library
- Audio playback is smooth and reliable
- Background audio works consistently
- Progress syncs accurately with web app
- App feels native and responsive
- Battery usage is acceptable
- Network usage is efficient

---

**Detailed Documentation**:

- [Development Workflow](mobile/development-workflow.md) - VS Code + Xcode coordination
- [Implementation Phases](mobile/implementation-phases.md) - 8 phases with acceptance criteria
- [Architecture](mobile/architecture.md) - Technical architecture and file structure
- [API Integration](mobile/api-integration.md) - API endpoints and integration patterns
- [iOS Features](mobile/ios-features.md) - iOS-specific implementations

**Next Steps**:

1. Complete web app deployment to AWS
2. Create OpenAPI specification from existing APIs
3. Setup iOS project in monorepo
4. Begin Phase 1 of iOS development
