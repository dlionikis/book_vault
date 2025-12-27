# iOS Pre-Development Setup - Implementation Plan

**Goal**: Prepare backend for iOS development with minimal prerequisites
**Strategy**: Option A - Minimal Path (Start iOS ASAP)
**Status**: Ready to implement
**Estimated Time**: 2-3 hours
**Risk Level**: Low

---

## Overview

This plan prepares the Book Vault backend for iOS development by completing the minimum required infrastructure work. The backend is already 95% mobile-ready - this fills in the final 5% gaps.

**What's Already Done**:

- ✅ 26 API endpoints with dual authentication (session + JWT)
- ✅ Mobile auth endpoints implemented (login, refresh, verify, logout)
- ✅ OpenAPI spec for main endpoints
- ✅ S3 streaming with range requests
- ✅ Contract testing framework

**What's Missing**:

- ⏳ Mobile auth endpoints in OpenAPI spec
- ⏳ Shared test fixtures for iOS
- ⏳ iOS project structure
- ⏳ Swift code generation setup

---

## Success Criteria

- [ ] All mobile auth endpoints documented in OpenAPI spec
- [ ] OpenAPI spec validates with zero warnings
- [ ] 6+ shared test fixtures created from real API responses
- [ ] iOS project structure created in monorepo
- [ ] Swift code generation working (`npm run api:generate:swift`)
- [ ] Generated Swift models compile (basic validation)
- [ ] Documentation updated with iOS setup instructions
- [ ] All changes committed and ready for iOS Phase 1

---

## Phase 1: Add Mobile Auth Endpoints to OpenAPI Spec

**Time**: 30-45 minutes
**Files**: `docs/api/openapi.yaml`

### Step 1.1: Add Token Refresh Endpoint

Add after `/api/auth/mobile/login` endpoint (around line 441):

```yaml
/api/auth/mobile/refresh:
  post:
    operationId: refreshToken
    tags: [Mobile Authentication]
    summary: Refresh JWT access token using refresh token
    security: [] # No auth needed for refresh
    requestBody:
      required: true
      content:
        application/json:
          schema:
            type: object
            required: [refreshToken]
            properties:
              refreshToken:
                type: string
                format: uuid
                description: Refresh token from login response
                example: '19706212-c220-465e-a94f-b3042ceb47ba'
    responses:
      '200':
        description: Token refreshed successfully
        content:
          application/json:
            schema:
              type: object
              required: [accessToken, refreshToken, expiresIn]
              properties:
                accessToken:
                  type: string
                  description: New JWT access token
                  example: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
                refreshToken:
                  type: string
                  format: uuid
                  description: New refresh token (rotated for security)
                  example: 'f8e5d3c2-b1a0-4f6e-9d8c-7b6a5e4d3c2b'
                expiresIn:
                  type: integer
                  description: Token lifetime in seconds
                  example: 3600
      '400':
        description: Missing refresh token
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Error'
      '401':
        description: Invalid or expired refresh token
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Error'
```

### Step 1.2: Add Token Verification Endpoint

Add after refresh endpoint:

```yaml
/api/auth/mobile/verify:
  post:
    operationId: verifyToken
    tags: [Mobile Authentication]
    summary: Verify JWT token is valid and not expired
    security:
      - bearerAuth: []
    responses:
      '200':
        description: Token is valid
        content:
          application/json:
            schema:
              type: object
              required: [valid, user]
              properties:
                valid:
                  type: boolean
                  example: true
                user:
                  $ref: '#/components/schemas/User'
      '401':
        description: Token is invalid or expired
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Error'
```

### Step 1.3: Add Logout Endpoint

Add after verify endpoint:

```yaml
/api/auth/mobile/logout:
  post:
    operationId: logoutMobile
    tags: [Mobile Authentication]
    summary: Logout and invalidate refresh token
    security:
      - bearerAuth: []
    requestBody:
      required: true
      content:
        application/json:
          schema:
            type: object
            required: [refreshToken]
            properties:
              refreshToken:
                type: string
                format: uuid
                description: Refresh token to invalidate
    responses:
      '200':
        description: Logged out successfully
        content:
          application/json:
            schema:
              type: object
              required: [message]
              properties:
                message:
                  type: string
                  example: 'Logged out successfully'
      '401':
        description: Invalid token
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Error'
```

### Step 1.4: Validate OpenAPI Spec

```bash
# Validate spec
npm run api:validate

# Should show: 0 warnings, spec is valid
# Regenerate TypeScript types
npm run api:generate:ts

# Verify types compile
npm run type-check
```

**Verification**:

- OpenAPI spec validates with 0 warnings
- TypeScript types regenerate successfully
- No type errors

### ✅ Phase 1 Complete - Next Steps

**Copy this prompt to continue to Phase 2:**

```
Phase 1 complete! OpenAPI spec now includes all mobile auth endpoints.

Verification results:
- [ ] npm run api:validate: PASS (0 warnings)
- [ ] npm run api:generate:ts: PASS
- [ ] npm run type-check: PASS

Please proceed to Phase 2: Create Shared Test Fixtures

Read /Users/demetri/projects/book_vault/docs/architecture/ios-pre-development-setup.md
and implement Phase 2: Create Shared Test Fixtures (starting at line ~200).

Generate 7 JSON test fixtures from real API responses.
```

---

## Phase 2: Create Shared Test Fixtures

**Time**: 30 minutes
**Location**: `test-fixtures/` (create directory)

### Step 2.1: Create Test Fixtures Directory

```bash
mkdir -p test-fixtures
```

### Step 2.2: Generate Fixtures from Real API

Start dev server and create fixtures from actual API responses:

```bash
# Terminal 1: Start server
npm run dev

# Terminal 2: Create fixtures
cd test-fixtures
```

### Step 2.3: Create Individual Fixtures

**File: `test-fixtures/books-list.json`**

```bash
# Fetch from real API
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/books?page=1&limit=5" \
  | jq '.' > books-list.json
```

**File: `test-fixtures/book-detail.json`**

```bash
# Get a single book with all relations
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/books/BOOK_ID" \
  | jq '.' > book-detail.json
```

**File: `test-fixtures/user-progress.json`**

```bash
# Get progress for a book
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/progress?bookId=BOOK_ID" \
  | jq '.' > user-progress.json
```

**File: `test-fixtures/chapters-list.json`**

```bash
# Get chapters for a book
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/books/BOOK_ID/chapters" \
  | jq '.' > chapters-list.json
```

**File: `test-fixtures/search-results.json`**

```bash
# Search results
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/search?q=fantasy&limit=5" \
  | jq '.' > search-results.json
```

**File: `test-fixtures/author-books.json`**

```bash
# Author with books
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/authors/AUTHOR_ID" \
  | jq '.' > author-books.json
```

**File: `test-fixtures/browse-authors.json`**

```bash
# Browse authors list
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/browse/authors?limit=10" \
  | jq '.' > browse-authors.json
```

### Step 2.4: Anonymize Sensitive Data (Optional)

Edit fixtures to remove any sensitive data:

- Replace real email addresses with `user@example.com`
- Use generic usernames
- Keep structure intact

### Step 2.5: Add README

**File: `test-fixtures/README.md`**

````markdown
# Test Fixtures

Shared JSON test fixtures for backend and iOS testing.

## Files

- `books-list.json` - Paginated book list (5 books)
- `book-detail.json` - Single book with all relations
- `user-progress.json` - User progress for a book
- `chapters-list.json` - Chapter list for a book
- `search-results.json` - Search results
- `author-books.json` - Author with their books
- `browse-authors.json` - Browse authors list

## Usage

### Backend Tests (TypeScript)

```typescript
import booksListFixture from '@/../test-fixtures/books-list.json';

test('API returns correct structure', () => {
  expect(response.data).toMatchObject(booksListFixture);
});
```
````

### iOS Tests (Swift)

```swift
let fixture = Bundle.main.url(forResource: "books-list", withExtension: "json")!
let data = try Data(contentsOf: fixture)
let books = try JSONDecoder().decode([Book].self, from: data)
```

## Regenerating Fixtures

```bash
# Get fresh auth token
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq -r .accessToken)

# Fetch and save
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/books?page=1&limit=5" \
  | jq '.' > books-list.json
```

```

**Verification**:
- 7 JSON fixtures created
- All files are valid JSON (run through `jq`)
- README documents usage

### ✅ Phase 2 Complete - Next Steps

**Copy this prompt to continue to Phase 3:**

```

Phase 2 complete! Test fixtures created and ready for iOS testing.

Verification results:

- [ ] 7 JSON fixtures created in test-fixtures/
- [ ] All files validated with jq
- [ ] README.md created with usage examples

Test fixtures:

- books-list.json, book-detail.json, user-progress.json
- chapters-list.json, search-results.json, author-books.json
- browse-authors.json

Please proceed to Phase 3: Create iOS Project Structure

Read /Users/demetri/projects/book_vault/docs/architecture/ios-pre-development-setup.md
and implement Phase 3: Create iOS Project Structure (starting at line ~385).

Create Xcode project and setup directory structure.

````

---

## Phase 3: Create iOS Project Structure

**Time**: 45 minutes
**Location**: `ios/` directory

### Step 3.1: Create Xcode Project

```bash
# Create iOS directory
mkdir -p ios
cd ios

# Create Xcode project (manual step in Xcode)
# File > New > Project
# - iOS App
# - Name: BookVault
# - Organization: Your Name
# - Bundle ID: com.yourdomain.bookvault
# - Interface: SwiftUI
# - Language: Swift
# - Storage: None
# - Include Tests: Yes

# Save to: book_vault/ios/
````

### Step 3.2: Create Generated Code Directory

In Xcode:

1. Right-click BookVault folder
2. New Group > "Generated"
3. New Group inside Generated > "Models"

Or via command line:

```bash
mkdir -p BookVault/Generated/Models
mkdir -p BookVault/Generated/API
```

### Step 3.3: Add .gitignore for iOS

**File: `ios/.gitignore`**

```gitignore
# Xcode
*.xcuserstate
*.xcworkspace
!*.xcworkspace/contents.xcworkspacedata
xcuserdata/
*.moved-aside
DerivedData/
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# Swift Package Manager
.build/
Packages/
Package.pins
Package.resolved

# CocoaPods
Pods/
*.xcworkspace
!default.xcworkspace

# Generated code
BookVault/Generated/Models/*
BookVault/Generated/API/*
!BookVault/Generated/Models/.gitkeep
!BookVault/Generated/API/.gitkeep

# Build artifacts
build/
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3
```

### Step 3.4: Create Basic File Structure

```bash
cd BookVault

# Create directory structure
mkdir -p Views/Auth
mkdir -p Views/Books
mkdir -p Views/Playback
mkdir -p Models
mkdir -p Services
mkdir -p Utilities
mkdir -p Generated/Models
mkdir -p Generated/API

# Create .gitkeep files for generated directories
touch Generated/Models/.gitkeep
touch Generated/API/.gitkeep
```

### Step 3.5: Create Basic Service Files (Placeholders)

**File: `ios/BookVault/Services/APIClient.swift`**

```swift
//
//  APIClient.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

/// API client for Book Vault backend
/// Uses generated models from OpenAPI specification
class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        // Use localhost for development
        // TODO: Switch to production URL after deployment
        self.baseURL = URL(string: "http://localhost:3000")!
        self.session = URLSession.shared
    }

    // MARK: - Authentication
    // TODO: Implement auth methods using generated models

    // MARK: - Books
    // TODO: Implement book fetching using generated models

    // MARK: - Progress
    // TODO: Implement progress sync using generated models
}
```

**File: `ios/BookVault/Services/AuthManager.swift`**

```swift
//
//  AuthManager.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

/// Manages authentication state and token storage
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private let keychainService = "com.bookvault.auth"

    // MARK: - Token Management
    // TODO: Implement keychain storage for JWT tokens

    // MARK: - Authentication
    // TODO: Implement login/logout using APIClient
}
```

**Verification**:

- Xcode project created and opens successfully
- Directory structure in place
- Basic service files compile (empty implementations)

### ✅ Phase 3 Complete - Next Steps

**Copy this prompt to continue to Phase 4:**

```
Phase 3 complete! iOS project structure created successfully.

Verification results:
- [ ] Xcode project created at ios/BookVault.xcodeproj
- [ ] Directory structure in place (Views, Services, Models, Generated)
- [ ] Placeholder files: APIClient.swift, AuthManager.swift
- [ ] .gitignore configured for iOS
- [ ] Project builds in Xcode (⌘B)

Directory structure:
- ios/BookVault/Views/
- ios/BookVault/Services/
- ios/BookVault/Models/
- ios/BookVault/Generated/Models/
- ios/BookVault/Generated/API/

Please proceed to Phase 4: Setup Swift Code Generation

Read /Users/demetri/projects/book_vault/docs/architecture/ios-pre-development-setup.md
and implement Phase 4: Setup Swift Code Generation (starting at line ~590).

Configure OpenAPI generator to create Swift models from API spec.
```

---

## Phase 4: Setup Swift Code Generation

**Time**: 45 minutes
**Files**: `package.json`, `scripts/generate-swift.sh`

### Step 4.1: Install OpenAPI Generator (if not installed)

```bash
# Check if installed
which openapi-generator

# If not installed:
brew install openapi-generator
```

### Step 4.2: Create Swift Generation Script

**File: `scripts/generate-swift.sh`**

```bash
#!/bin/bash
set -e

echo "🔄 Generating Swift models from OpenAPI spec..."

# Configuration
SPEC_PATH="docs/api/openapi.yaml"
OUTPUT_DIR="ios/BookVault/Generated/Models"
TEMPLATE_DIR="scripts/swift-templates"

# Validate spec exists
if [ ! -f "$SPEC_PATH" ]; then
  echo "❌ Error: OpenAPI spec not found at $SPEC_PATH"
  exit 1
fi

# Validate iOS project exists
if [ ! -d "ios/BookVault" ]; then
  echo "❌ Error: iOS project not found at ios/BookVault"
  exit 1
fi

# Clean previous generation
echo "🗑️  Cleaning previous generated code..."
rm -rf "$OUTPUT_DIR"/*
mkdir -p "$OUTPUT_DIR"

# Generate Swift models
echo "📝 Generating Swift models..."
openapi-generator generate \
  -i "$SPEC_PATH" \
  -g swift5 \
  -o "$OUTPUT_DIR" \
  --additional-properties=projectName=BookVault \
  --additional-properties=responseAs=AsyncAwait \
  --additional-properties=library=urlsession \
  --additional-properties=swiftPackageManager=false \
  --skip-validate-spec

# Keep only model files, remove API client (we'll write our own)
echo "🧹 Cleaning up unnecessary files..."
find "$OUTPUT_DIR" -type f ! -name "*Models.swift" ! -name ".gitkeep" -delete

# Format generated code (if swiftformat is available)
if command -v swiftformat &> /dev/null; then
  echo "✨ Formatting generated code..."
  swiftformat "$OUTPUT_DIR" --swiftversion 5.9
fi

echo "✅ Swift models generated successfully at $OUTPUT_DIR"
echo ""
echo "Generated files:"
ls -lh "$OUTPUT_DIR"/*.swift 2>/dev/null || echo "  (none yet - run after creating OpenAPI spec)"
```

Make executable:

```bash
chmod +x scripts/generate-swift.sh
```

### Step 4.3: Update npm Script

Edit `package.json`:

```json
{
  "scripts": {
    "api:generate:swift": "./scripts/generate-swift.sh",
    "api:generate": "npm run api:generate:ts && npm run api:generate:swift",
    "api:watch": "concurrently \"npm run api:watch:ts\" \"npm run api:watch:swift\"",
    "api:watch:swift": "nodemon --watch docs/api/openapi.yaml --exec npm run api:generate:swift"
  }
}
```

### Step 4.4: Test Swift Generation

```bash
# Generate Swift models
npm run api:generate:swift

# Verify files created
ls -la ios/BookVault/Generated/Models/

# Should see:
# - Models.swift (all model definitions)
# - .gitkeep
```

### Step 4.5: Add Generated Files to Xcode

1. Open Xcode project
2. Right-click `BookVault/Generated/Models` folder
3. Add Files to "BookVault"...
4. Select all `.swift` files in `Generated/Models/`
5. ✅ "Copy items if needed"
6. ✅ "Create groups"
7. Target: BookVault
8. Click Add

### Step 4.6: Verify Swift Models Compile

In Xcode:

1. Product > Build (⌘B)
2. Should compile successfully (or show fixable errors)
3. Check for:
   - Book model
   - Author model
   - UserProgress model
   - Pagination model

**Verification**:

- Swift generation script works
- Models generated from OpenAPI spec
- Files added to Xcode project
- Project builds (even if empty)

### ✅ Phase 4 Complete - Next Steps

**Copy this prompt to continue to Phase 5:**

```
Phase 4 complete! Swift code generation is now working.

Verification results:
- [ ] openapi-generator installed (brew)
- [ ] scripts/generate-swift.sh created and executable
- [ ] npm run api:generate:swift works
- [ ] Swift models generated in ios/BookVault/Generated/Models/
- [ ] Models added to Xcode project
- [ ] Xcode project builds successfully (⌘B)

Generated models:
- Book, Author, Narrator, Series, Category
- UserProgress, Chapter, Pagination
- All models compile in Swift

Package.json scripts updated:
- npm run api:generate:swift
- npm run api:generate (TypeScript + Swift)
- npm run api:watch:swift

Please proceed to Phase 5: Update Documentation

Read /Users/demetri/projects/book_vault/docs/architecture/ios-pre-development-setup.md
and implement Phase 5: Update Documentation (starting at line ~760).

Update project documentation with iOS setup instructions.
```

---

## Phase 5: Update Documentation

**Time**: 15 minutes
**Files**: Various documentation updates

### Step 5.1: Update ios-backend-sync.md

Mark Swift generation as complete:

```markdown
### iOS (Swift)

**Status**: ✅ Complete
**Command**: `npm run api:generate:swift`
**Output**: `ios/BookVault/Generated/Models/`
**Tooling**: `openapi-generator` (Homebrew)
```

### Step 5.2: Create iOS Development Setup Guide

**File: `docs/mobile/ios-development-setup.md`**

````markdown
# iOS Development Setup

Quick guide to setting up the iOS development environment.

## Prerequisites

- macOS with Xcode 15+ installed
- Node.js 18+ (for backend)
- OpenAPI Generator: `brew install openapi-generator`
- jq (for test fixtures): `brew install jq`

## Initial Setup

### 1. Clone and Install

```bash
git clone <repo>
cd book_vault
npm install
```
````

### 2. Start Backend

```bash
# Start database
docker-compose up -d

# Start dev server (accessible to iOS Simulator)
npm run dev
# Server runs on http://0.0.0.0:3000
```

### 3. Open iOS Project

```bash
open ios/BookVault.xcodeproj
```

### 4. Generate Swift Models

```bash
# One-time or after OpenAPI changes
npm run api:generate:swift
```

### 5. Run iOS App

In Xcode:

- Select iPhone simulator
- Press ⌘R to build and run

## Development Workflow

### Making API Changes

1. Update `docs/api/openapi.yaml`
2. Regenerate types: `npm run api:generate`
3. Implement backend changes
4. Update iOS code to use new models
5. Test integration

### Testing

**Backend**:

```bash
npm test
npm run test:contract  # Validate OpenAPI compliance
```

**iOS**:

- Use test fixtures in `test-fixtures/`
- Unit tests: ⌘U in Xcode
- UI tests: Select test scheme

## Troubleshooting

**iOS can't connect to backend**:

- Ensure using `http://localhost:3000` (not 127.0.0.1)
- Check firewall isn't blocking connections
- Verify backend is running: `curl http://localhost:3000/api/books`

**Swift generation fails**:

- Validate OpenAPI spec: `npm run api:validate`
- Check openapi-generator version: `openapi-generator version`
- Try cleaning: `rm -rf ios/BookVault/Generated/Models/*`

**Xcode build errors**:

- Clean build folder: Product > Clean Build Folder
- Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Regenerate Swift models: `npm run api:generate:swift`

````

### Step 5.3: Update CLAUDE.md

Add iOS development section:

```markdown
## iOS Development (New)

### Getting Started

```bash
# Generate Swift models from OpenAPI spec
npm run api:generate:swift

# Watch for OpenAPI changes
npm run api:watch

# Open Xcode
open ios/BookVault.xcodeproj
````

### Test Fixtures

Shared JSON fixtures for backend and iOS testing in `test-fixtures/`:

- `books-list.json`, `book-detail.json`, `user-progress.json`, etc.

### Development Workflow

See [docs/mobile/ios-development-setup.md](docs/mobile/ios-development-setup.md)

````

### Step 5.4: Update README.md

Add iOS app section:

```markdown
## iOS Mobile App

Native iOS app for Book Vault (in development).

**Status**: Pre-development setup complete
**Technology**: Swift + SwiftUI
**Location**: `ios/BookVault/`

See [docs/mobile-ios-plan.md](docs/mobile-ios-plan.md) for implementation plan.
````

**Verification**:

- Documentation updated
- Setup guide complete
- Links working

### ✅ Phase 5 Complete - Next Steps

**Copy this prompt to continue to Phase 6:**

```
Phase 5 complete! All documentation updated with iOS setup instructions.

Verification results:
- [ ] ios-backend-sync.md updated (Swift generation ✅)
- [ ] ios-development-setup.md created
- [ ] CLAUDE.md updated with iOS workflow
- [ ] README.md updated with iOS section
- [ ] All documentation links verified

Documentation created:
- docs/mobile/ios-development-setup.md (complete setup guide)
- Updated: CLAUDE.md, README.md, ios-backend-sync.md

Please proceed to Phase 6: Final Validation & Commit

Read /Users/demetri/projects/book_vault/docs/architecture/ios-pre-development-setup.md
and implement Phase 6: Final Validation & Commit (starting at line ~960).

Run all validation checks and commit the iOS pre-development setup.
```

---

## Phase 6: Final Validation & Commit

**Time**: 15 minutes

### Step 6.1: Run All Validations

```bash
# Validate OpenAPI spec
npm run api:validate

# Regenerate all types
npm run api:generate

# Type check
npm run type-check

# Run tests
npm test

# Contract tests
npm run test:contract

# Full validation
npm run validate:full
```

### Step 6.2: Verify iOS Project

```bash
# Build iOS project from command line
cd ios
xcodebuild -scheme BookVault \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build
```

### Step 6.3: Git Status Check

```bash
git status

# Should show:
# - docs/api/openapi.yaml (modified - 3 new endpoints)
# - test-fixtures/ (new directory with 7 files)
# - ios/ (new directory with Xcode project)
# - scripts/generate-swift.sh (new file)
# - package.json (modified - new scripts)
# - docs updates
```

### Step 6.4: Create Commit

```bash
git add .
git commit -m "feat(ios): iOS pre-development setup complete

Phase 1: OpenAPI Spec
- Added 3 mobile auth endpoints (refresh, verify, logout)
- Spec validates with 0 warnings
- All auth endpoints documented

Phase 2: Test Fixtures
- Created test-fixtures/ directory
- 7 JSON fixtures from real API responses
- Shared between backend and iOS tests

Phase 3: iOS Project
- Created Xcode project in ios/BookVault/
- Basic directory structure (Views, Services, Models, Generated)
- Placeholder service files (APIClient, AuthManager)

Phase 4: Swift Generation
- Created scripts/generate-swift.sh
- npm run api:generate:swift working
- Swift models generate from OpenAPI spec
- Xcode project builds successfully

Phase 5: Documentation
- Updated ios-backend-sync.md
- Created ios-development-setup.md
- Updated CLAUDE.md with iOS workflow
- Updated README.md

Verification:
✅ OpenAPI spec: 0 warnings, 100% coverage
✅ TypeScript types: regenerated, no errors
✅ Swift models: generated, compiles
✅ Test fixtures: 7 files, valid JSON
✅ iOS project: builds successfully
✅ All tests passing (207 tests)

Ready for iOS Phase 1: Authentication & Browsing

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### ✅ Phase 6 Complete - iOS Pre-Development Setup Finished! 🎉

**All phases complete! Ready to start iOS development.**

**Copy this prompt to start iOS Phase 1:**

```
iOS Pre-Development Setup Complete! 🎉

All 6 phases successfully completed:
✅ Phase 1: Mobile auth endpoints in OpenAPI spec
✅ Phase 2: Test fixtures created (7 JSON files)
✅ Phase 3: iOS project structure created
✅ Phase 4: Swift code generation working
✅ Phase 5: Documentation updated
✅ Phase 6: All changes committed

Final verification:
- npm run validate:full: PASS
- Xcode project builds: PASS
- Swift models generated: PASS
- Git committed and clean

🚀 Ready to start iOS Phase 1: Authentication & Browsing

Next steps:
1. Read docs/mobile/implementation-phases.md (iOS Phase 1 details)
2. Or read docs/mobile-ios-plan.md (complete iOS plan overview)
3. Start implementing login screen and book browsing

Recommended prompt to continue:
"Let's start iOS Phase 1: Authentication & Browsing. Please read docs/mobile/implementation-phases.md and help me implement the login screen and authentication flow."
```

---

## Implementation Checklist

Copy this checklist when implementing:

```
Phase 1: OpenAPI Spec (30-45 min)
[ ] Add /api/auth/mobile/refresh endpoint
[ ] Add /api/auth/mobile/verify endpoint
[ ] Add /api/auth/mobile/logout endpoint
[ ] Validate spec: npm run api:validate
[ ] Regenerate TypeScript: npm run api:generate:ts
[ ] Verify type-check passes

Phase 2: Test Fixtures (30 min)
[ ] Create test-fixtures/ directory
[ ] Generate books-list.json
[ ] Generate book-detail.json
[ ] Generate user-progress.json
[ ] Generate chapters-list.json
[ ] Generate search-results.json
[ ] Generate author-books.json
[ ] Generate browse-authors.json
[ ] Create test-fixtures/README.md
[ ] Verify all JSON files are valid

Phase 3: iOS Project (45 min)
[ ] Create ios/ directory
[ ] Create Xcode project (BookVault)
[ ] Setup directory structure
[ ] Create Generated/Models folder
[ ] Create Generated/API folder
[ ] Add .gitignore for iOS
[ ] Create placeholder APIClient.swift
[ ] Create placeholder AuthManager.swift
[ ] Verify project builds

Phase 4: Swift Generation (45 min)
[ ] Install openapi-generator (brew)
[ ] Create scripts/generate-swift.sh
[ ] Make script executable
[ ] Update package.json scripts
[ ] Test Swift generation
[ ] Add generated files to Xcode
[ ] Verify models compile
[ ] Test npm run api:generate:swift

Phase 5: Documentation (15 min)
[ ] Update ios-backend-sync.md
[ ] Create ios-development-setup.md
[ ] Update CLAUDE.md
[ ] Update README.md
[ ] Verify all links work

Phase 6: Validation & Commit (15 min)
[ ] Run npm run validate:full
[ ] Build iOS project from CLI
[ ] Review git status
[ ] Commit all changes
[ ] Push to remote
```

---

## Next Steps After Completion

Once this setup is complete, you're ready to start:

**iOS Phase 1: Authentication & Browsing** (~1 week)

- Implement login screen
- Keychain token storage
- Book list view
- Book detail view
- Navigation structure

See [docs/mobile/implementation-phases.md](mobile/implementation-phases.md) for full Phase 1 plan.

---

## Troubleshooting

### OpenAPI Validation Fails

**Symptom**: `npm run api:validate` shows errors

**Solution**:

```bash
# Check spec syntax
npx @redocly/cli lint docs/api/openapi.yaml

# Common issues:
# - Missing required fields
# - Invalid $ref references
# - Duplicate operationId
```

### Swift Generation Fails

**Symptom**: `npm run api:generate:swift` errors

**Solution**:

```bash
# Verify openapi-generator installed
which openapi-generator

# Try manual generation
openapi-generator generate \
  -i docs/api/openapi.yaml \
  -g swift5 \
  -o ios/BookVault/Generated/Models

# Check generator logs for specific errors
```

### Xcode Build Fails

**Symptom**: Swift models don't compile in Xcode

**Solution**:

1. Check models are added to target
2. Clean build folder (⇧⌘K)
3. Regenerate models
4. Restart Xcode

### Test Fixtures Missing Data

**Symptom**: Fixture JSON files are incomplete

**Solution**:

```bash
# Get fresh auth token
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq -r .accessToken)

# Verify token works
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/books

# Re-fetch fixtures with valid token
```

---

## File Summary

**New Files** (18 total):

- `docs/api/openapi.yaml` (modified - 3 endpoints added)
- `test-fixtures/books-list.json`
- `test-fixtures/book-detail.json`
- `test-fixtures/user-progress.json`
- `test-fixtures/chapters-list.json`
- `test-fixtures/search-results.json`
- `test-fixtures/author-books.json`
- `test-fixtures/browse-authors.json`
- `test-fixtures/README.md`
- `ios/.gitignore`
- `ios/BookVault.xcodeproj/` (Xcode project)
- `ios/BookVault/Services/APIClient.swift`
- `ios/BookVault/Services/AuthManager.swift`
- `scripts/generate-swift.sh`
- `docs/mobile/ios-development-setup.md`
- `package.json` (modified - new scripts)
- `CLAUDE.md` (modified - iOS section)
- `README.md` (modified - iOS section)

**Generated Files** (not committed):

- `ios/BookVault/Generated/Models/*.swift`
- `lib/api-types.ts` (regenerated)

---

**Document Version**: 1.0
**Last Updated**: December 26, 2025
**Author**: Claude (Sonnet 4.5)
**Status**: Ready for implementation
