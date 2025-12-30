# Code Quality Implementation Plan

> **Created**: December 30, 2025
> **Status**: Ready for Implementation
> **Estimated Total Effort**: 2-3 sessions (can be done incrementally)

This document provides step-by-step instructions for implementing code quality improvements identified in the BookVault assessment. Each phase is self-contained and can be completed independently.

---

## Table of Contents

1. [Phase 1: Fix Pre-commit + Add Main CI](#phase-1-fix-pre-commit--add-main-ci)
2. [Phase 2: Add SwiftLint + SwiftFormat](#phase-2-add-swiftlint--swiftformat)
3. [Phase 3: Dead Code Detection + Stricter Warnings](#phase-3-dead-code-detection--stricter-warnings)
4. [Phase 4: iOS Dependency Injection Refactor](#phase-4-ios-dependency-injection-refactor)
5. [Phase 5: OpenAPI Swift Drift + Security CI](#phase-5-openapi-swift-drift--security-ci)
6. [Appendix: Tool Reference](#appendix-tool-reference)

---

## Phase 1: Fix Pre-commit + Add Main CI

**Effort**: Small (30-45 minutes)
**Priority**: High
**Dependencies**: None

### Problem

The pre-commit hook calls `npx lint-staged` but there's no lint-staged configuration in `package.json`. Additionally, the backend has no CI workflow that runs lint/typecheck/tests on PRs.

### Implementation Steps

#### Step 1.1: Add lint-staged configuration

Edit `package.json` and add the `lint-staged` key at the root level (after `overrides`):

```json
{
  "overrides": {
    "glob": "^11.0.0"
  },
  "lint-staged": {
    "*.{js,jsx,ts,tsx}": ["prettier --write", "eslint --fix --max-warnings=0"],
    "*.{json,md,yaml,yml}": ["prettier --write"]
  }
}
```

#### Step 1.2: Install lint-staged as dev dependency

```bash
npm install --save-dev lint-staged
```

#### Step 1.3: Verify pre-commit hook works

```bash
# Make a small change to any .ts file
echo "// test" >> lib/types.ts

# Stage and attempt commit
git add lib/types.ts
git commit -m "test: verify pre-commit hook"

# Should see lint-staged output
# Then abort or amend to remove test comment
git reset HEAD~1
git checkout lib/types.ts
```

#### Step 1.4: Create main validation CI workflow

Create `.github/workflows/main.yml`:

```yaml
name: Main Validation

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    name: Lint, Type Check, and Test
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: book_vault_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Check formatting
        run: npm run format:check

      - name: Lint
        run: npm run lint

      - name: Type check
        run: npm run type-check

      - name: Setup test database
        run: |
          echo "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/book_vault_test?schema=public" >> .env.test
          echo "NEXTAUTH_SECRET=test-secret" >> .env.test
          npx prisma migrate deploy
          npx prisma generate
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/book_vault_test?schema=public

      - name: Run tests
        run: npm test
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/book_vault_test?schema=public
          NEXTAUTH_SECRET: test-secret

  security-audit:
    name: Security Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - name: Run npm audit
        run: npm audit --production --audit-level=high
        continue-on-error: true # Don't fail build, just warn
```

#### Step 1.5: Test the workflow locally (optional)

```bash
# Run the same commands the CI will run
npm run format:check
npm run lint
npm run type-check
npm test
```

### Verification Checklist

- [ ] `lint-staged` appears in `package.json` devDependencies
- [ ] `lint-staged` config block exists in `package.json`
- [ ] Pre-commit hook runs Prettier and ESLint on staged files
- [ ] `.github/workflows/main.yml` exists
- [ ] Push to a branch and verify workflow runs on GitHub

### Commit Message

```
feat(ci): add main validation workflow and fix lint-staged

- Add lint-staged configuration to package.json
- Create main.yml workflow for PR validation
- Run format, lint, typecheck, and tests on every PR
- Add security audit step (non-blocking)

🤖 Generated with Claude Code
```

---

## Phase 2: Add SwiftLint + SwiftFormat

**Effort**: Small-Medium (45-60 minutes)
**Priority**: High
**Dependencies**: Phase 1 recommended but not required

### Problem

iOS code has no linting or formatting enforcement. Only the auto-generated OpenAPI models have SwiftFormat configuration.

### Prerequisites

```bash
# Install tools (if not already installed)
brew install swiftlint swiftformat
```

### Implementation Steps

#### Step 2.1: Create SwiftLint configuration

Create `ios/.swiftlint.yml`:

```yaml
# SwiftLint Configuration for BookVault iOS App
# Docs: https://realm.github.io/SwiftLint/rule-directory.html

included:
  - BookVault
  - BookVaultTests

excluded:
  - BookVault/Generated # Auto-generated OpenAPI models

# Start with reasonable defaults, can tighten later
disabled_rules:
  - line_length # Too noisy initially
  - file_length # Some views are legitimately long
  - type_body_length # ViewModels can be large
  - function_body_length # Some complex functions are fine
  - trailing_whitespace # SwiftFormat handles this

opt_in_rules:
  - empty_count # Prefer .isEmpty over .count == 0
  - empty_string # Prefer .isEmpty for strings
  - fallthrough # Require explicit fallthrough
  - fatal_error_message # Require message in fatalError
  - first_where # Prefer .first(where:) over .filter().first
  - force_unwrapping # Warn on force unwrap (!)
  - implicitly_unwrapped_optional # Warn on implicitly unwrapped optionals
  - last_where # Prefer .last(where:)
  - legacy_random # Use modern random APIs
  - modifier_order # Consistent modifier ordering
  - overridden_super_call # Ensure super is called
  - private_action # @IBAction should be private
  - private_outlet # @IBOutlet should be private
  - redundant_nil_coalescing # Remove redundant ?? nil
  - sorted_first_last # Use .first/.last instead of sorted().first
  - toggle_bool # Prefer .toggle() over x = !x
  - unneeded_parentheses_in_closure_argument # Clean closure syntax
  - vertical_whitespace_closing_braces # No blank line before }
  - yoda_condition # Avoid constant == variable

# Customize specific rules
identifier_name:
  min_length:
    warning: 2 # Allow 2-char names like 'id', 'to'
  excluded:
    - id
    - to
    - x
    - y
    - i
    - j

type_name:
  min_length:
    warning: 3
  max_length:
    warning: 50

nesting:
  type_level:
    warning: 2
  function_level:
    warning: 3

# Reporter type (xcode for CI integration)
reporter: xcode
```

#### Step 2.2: Create SwiftFormat configuration

Create `ios/.swiftformat`:

```
# SwiftFormat Configuration for BookVault iOS App
# Docs: https://github.com/nicklockwood/SwiftFormat/blob/master/Rules.md

# File options
--exclude BookVault/Generated

# Format options (match team preferences)
--allman false
--binarygrouping 4,8
--commas always
--comments indent
--decimalgrouping 3,6
--elseposition same-line
--empty void
--exponentcase lowercase
--fractiongrouping disabled
--header ignore
--hexgrouping 4,8
--hexliteralcase uppercase
--ifdef indent
--indent 4
--indentcase false
--importgrouping testable-bottom
--linebreaks lf
--maxwidth 120
--octalgrouping 4,8
--operatorfunc spaced
--patternlet hoist
--ranges spaced
--self remove
--semicolons inline
--stripunusedargs always
--swiftversion 5.9
--trimwhitespace always
--wraparguments before-first
--wrapcollections before-first
--wrapparameters before-first

# Rules
--enable isEmpty
--enable wrapEnumCases
--enable wrapSwitchCases
--enable markTypes
--enable sortImports
--enable blankLinesBetweenScopes

# Disable rules that conflict with SwiftUI patterns
--disable redundantSelf
--disable trailingClosures
```

#### Step 2.3: Run initial lint and fix

```bash
cd ios

# See all current violations (don't fix yet)
swiftlint lint --config .swiftlint.yml

# Auto-fix what can be fixed
swiftlint lint --config .swiftlint.yml --fix

# Format all code
swiftformat BookVault BookVaultTests --config .swiftformat

# Run lint again to see remaining issues
swiftlint lint --config .swiftlint.yml
```

#### Step 2.4: Fix remaining violations manually

Common fixes you'll likely need:

```swift
// Force unwrapping warning - replace:
let value = optionalValue!
// With:
guard let value = optionalValue else { return }
// Or:
let value = optionalValue ?? defaultValue

// Empty count warning - replace:
if array.count == 0 { }
// With:
if array.isEmpty { }
```

#### Step 2.5: Add SwiftLint to CI

Update `.github/workflows/ios-tests.yml`, add after "Install xcpretty" step:

```yaml
- name: Install SwiftLint
  run: brew install swiftlint

- name: Lint Swift code
  working-directory: ios
  run: swiftlint lint --config .swiftlint.yml --strict --reporter github-actions-logging
```

#### Step 2.6: (Optional) Add pre-commit hook for Swift

Update `.husky/pre-commit`:

```bash
npx lint-staged

# OpenAPI: Check if spec changed and regenerate types
if git diff --cached --name-only | grep -q "docs/api/openapi.yaml"; then
  echo "📝 OpenAPI spec changed, regenerating TypeScript types..."
  npm run api:generate:ts
  git add lib/api-types.ts

  echo "✅ Validating OpenAPI spec..."
  npm run api:validate || {
    echo "❌ OpenAPI spec validation failed"
    exit 1
  }
fi

# Swift: Lint and format changed Swift files
SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' | grep -v 'Generated/' || true)
if [ -n "$SWIFT_FILES" ]; then
  echo "🔍 Linting Swift files..."
  cd ios
  echo "$SWIFT_FILES" | xargs -I {} swiftlint lint --config .swiftlint.yml --path "../{}" --strict || {
    echo "❌ SwiftLint found issues"
    exit 1
  }
  cd ..
fi
```

### Verification Checklist

- [ ] `ios/.swiftlint.yml` exists with custom rules
- [ ] `ios/.swiftformat` exists
- [ ] `swiftlint lint --config .swiftlint.yml` shows zero violations (or only intentional ones)
- [ ] `swiftformat --lint BookVault` shows no formatting changes needed
- [ ] iOS CI workflow runs SwiftLint

### Commit Message

```
feat(ios): add SwiftLint and SwiftFormat configuration

- Create .swiftlint.yml with project-specific rules
- Create .swiftformat with team style preferences
- Fix existing lint violations
- Add SwiftLint step to iOS CI workflow
- Exclude Generated/ directory from linting

🤖 Generated with Claude Code
```

---

## Phase 3: Dead Code Detection + Stricter Warnings

**Effort**: Small-Medium (30-60 minutes)
**Priority**: Medium
**Dependencies**: Phase 2 recommended

### Problem

No automated detection of unused code. Default Xcode warnings miss many issues. This phase answers the original question about orphaned code like `KeychainStoring`.

### Prerequisites

```bash
brew install peripheryapp/periphery/periphery
```

### Implementation Steps

#### Step 3.1: Run Periphery scan

```bash
cd ios

# Generate fresh Xcode project
xcodegen generate

# Run Periphery (this takes 1-2 minutes)
periphery scan \
  --project BookVault.xcodeproj \
  --schemes BookVault \
  --targets BookVault \
  --format xcode

# For more detailed output:
periphery scan \
  --project BookVault.xcodeproj \
  --schemes BookVault \
  --targets BookVault \
  --format json > periphery-results.json
```

#### Step 3.2: Review results

Periphery will report things like:

- Unused protocols (like `KeychainStoring` if unused)
- Unused functions and properties
- Unused parameters
- Unused imports

**Important**: Not all "unused" code should be deleted. Review each finding:

| Category                | Action                                         |
| ----------------------- | ---------------------------------------------- |
| Truly dead code         | Delete it                                      |
| Protocol for testing    | Keep, mark with `// periphery:ignore`          |
| Future API              | Consider deleting (YAGNI) or keep with comment |
| SwiftUI Preview helpers | Keep, may need `// periphery:ignore`           |

#### Step 3.3: Add Periphery ignore comments where needed

```swift
// For code that appears unused but is intentional:

// periphery:ignore - Protocol used for dependency injection in tests
protocol KeychainStoring {
    func save(_ data: Data, for key: String) throws
}

// periphery:ignore - Used via @EnvironmentObject injection
class SomeManager: ObservableObject { }
```

#### Step 3.4: Create Periphery configuration (optional)

Create `ios/.periphery.yml` for consistent scans:

```yaml
project: BookVault.xcodeproj
schemes:
  - BookVault
targets:
  - BookVault
format: xcode
retain_public: false
retain_objc_accessible: true
```

Then run with: `periphery scan --config .periphery.yml`

#### Step 3.5: Enable stricter Swift compiler warnings

Update `ios/project.yml` in the `settings.base` section:

```yaml
settings:
  base:
    MARKETING_VERSION: '1.0'
    CURRENT_PROJECT_VERSION: '1'

    # Existing settings...
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS: YES
    ENABLE_LOCALIZATION_STRING_GENERATION: YES

    # NEW: Stricter warnings
    SWIFT_STRICT_CONCURRENCY: complete # Full concurrency checking
    GCC_WARN_UNINITIALIZED_AUTOS: YES_AGGRESSIVE
    CLANG_WARN_IMPLICIT_FALLTHROUGH: YES
    CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER: YES
    CLANG_WARN_SUSPICIOUS_MOVE: YES
    GCC_WARN_SHADOW: YES
    GCC_WARN_SIGN_COMPARE: YES
    CLANG_WARN_STRICT_PROTOTYPES: YES
    GCC_WARN_UNUSED_FUNCTION: YES
    GCC_WARN_UNUSED_VARIABLE: YES
```

#### Step 3.6: Regenerate project and fix warnings

```bash
cd ios
xcodegen generate

# Build and see warnings
xcodebuild build \
  -scheme BookVault \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  2>&1 | grep -E "warning:|error:"
```

Fix warnings as they appear. Common ones:

- Sendable conformance issues (from `SWIFT_STRICT_CONCURRENCY`)
- Unused variables
- Implicit fallthrough in switch statements

#### Step 3.7: (Optional) Add Periphery to CI

Add to `.github/workflows/ios-tests.yml`:

```yaml
- name: Install Periphery
  run: brew install peripheryapp/periphery/periphery

- name: Check for unused code
  working-directory: ios
  run: |
    periphery scan \
      --project BookVault.xcodeproj \
      --schemes BookVault \
      --targets BookVault \
      --format xcode \
      --strict
  continue-on-error: true # Warn but don't fail initially
```

### Verification Checklist

- [ ] Periphery scan runs successfully
- [ ] Dead code has been removed or marked with `// periphery:ignore`
- [ ] `ios/project.yml` has stricter warning settings
- [ ] Project builds with zero warnings (or only intentional ones)
- [ ] XcodeGen regenerates project successfully

### Commit Message

```
refactor(ios): remove dead code and enable strict warnings

- Run Periphery to detect unused code
- Remove truly dead code: [list specific items]
- Add periphery:ignore for intentional unused code
- Enable SWIFT_STRICT_CONCURRENCY: complete
- Enable additional compiler warnings
- Fix all new warnings

🤖 Generated with Claude Code
```

---

## Phase 4: iOS Dependency Injection Refactor

**Effort**: Medium-Large (2-3 hours)
**Priority**: Medium
**Dependencies**: Phases 1-3 recommended

### Problem

Services use singleton pattern (`AuthManager.shared`, `APIClient.shared`, etc.) which:

- Makes unit testing harder (must reset global state)
- Creates hidden dependencies
- Prevents true isolation in tests

### Current Architecture

```
BookVaultApp
    └── AuthManager.shared (singleton)
         └── APIClient.shared (singleton)
              └── URLSession.shared (singleton)
```

### Target Architecture

```
BookVaultApp
    └── DependencyContainer (created at app launch)
         ├── AuthManager (injected)
         ├── APIClient (injected)
         ├── LibraryManager (injected)
         └── ... (all services)
```

### Implementation Steps

#### Step 4.1: Create DependencyContainer protocol and implementation

Create `ios/BookVault/DI/DependencyContainer.swift`:

```swift
//
//  DependencyContainer.swift
//  BookVault
//
//  Dependency injection container for service management
//

import Foundation

/// Protocol defining all app dependencies
/// Using a protocol allows for easy mocking in tests
@MainActor
protocol DependencyContaining {
    var apiClient: APIClientProtocol { get }
    var authManager: AuthManaging { get }
    var libraryManager: LibraryManaging { get }
    var progressManager: ProgressManaging { get }
    var downloadManager: DownloadManaging { get }
    var audioPlayerManager: AudioPlayerManaging { get }
    var chapterManager: ChapterManaging { get }
    var syncManager: SyncManaging { get }
    var networkMonitor: NetworkMonitoring { get }
    var storageManager: StorageManaging { get }
}

/// Production dependency container
@MainActor
final class DependencyContainer: DependencyContaining, ObservableObject {
    // MARK: - Lazy Services (created on first access)

    lazy var apiClient: APIClientProtocol = {
        APIClient.shared  // Keep singleton for now, but access through container
    }()

    lazy var authManager: AuthManaging = {
        AuthManager(apiClient: apiClient)
    }()

    lazy var networkMonitor: NetworkMonitoring = {
        NetworkMonitor.shared
    }()

    lazy var storageManager: StorageManaging = {
        StorageManager()
    }()

    lazy var libraryManager: LibraryManaging = {
        LibraryManager(
            apiClient: apiClient,
            networkMonitor: networkMonitor
        )
    }()

    lazy var progressManager: ProgressManaging = {
        ProgressManager(apiClient: apiClient)
    }()

    lazy var downloadManager: DownloadManaging = {
        DownloadManager(storageManager: storageManager)
    }()

    lazy var audioPlayerManager: AudioPlayerManaging = {
        AudioPlayerManager(
            progressManager: progressManager,
            chapterManager: chapterManager
        )
    }()

    lazy var chapterManager: ChapterManaging = {
        ChapterManager(apiClient: apiClient)
    }()

    lazy var syncManager: SyncManaging = {
        SyncManager(
            networkMonitor: networkMonitor,
            progressManager: progressManager
        )
    }()
}

/// Mock dependency container for testing
@MainActor
final class MockDependencyContainer: DependencyContaining {
    var apiClient: APIClientProtocol
    var authManager: AuthManaging
    var libraryManager: LibraryManaging
    var progressManager: ProgressManaging
    var downloadManager: DownloadManaging
    var audioPlayerManager: AudioPlayerManaging
    var chapterManager: ChapterManaging
    var syncManager: SyncManaging
    var networkMonitor: NetworkMonitoring
    var storageManager: StorageManaging

    init(
        apiClient: APIClientProtocol = MockAPIClient(),
        authManager: AuthManaging = MockAuthManager(),
        libraryManager: LibraryManaging = MockLibraryManager(),
        progressManager: ProgressManaging = MockProgressManager(),
        downloadManager: DownloadManaging = MockDownloadManager(),
        audioPlayerManager: AudioPlayerManaging = MockAudioPlayerManager(),
        chapterManager: ChapterManaging = MockChapterManager(),
        syncManager: SyncManaging = MockSyncManager(),
        networkMonitor: NetworkMonitoring = MockNetworkMonitor(),
        storageManager: StorageManaging = MockStorageManager()
    ) {
        self.apiClient = apiClient
        self.authManager = authManager
        self.libraryManager = libraryManager
        self.progressManager = progressManager
        self.downloadManager = downloadManager
        self.audioPlayerManager = audioPlayerManager
        self.chapterManager = chapterManager
        self.syncManager = syncManager
        self.networkMonitor = networkMonitor
        self.storageManager = storageManager
    }
}
```

#### Step 4.2: Define missing protocols

For any service without a protocol, create one. Example for `AuthManager`:

```swift
// In AuthManager.swift, add at top:

@MainActor
protocol AuthManaging: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    func login(email: String, password: String) async throws
    func logout() async
    func forceLogout()
}

// Then conform:
class AuthManager: AuthManaging {
    // ... existing implementation
}
```

Repeat for all services that need protocols:

- `LibraryManaging`
- `ProgressManaging`
- `DownloadManaging`
- `AudioPlayerManaging`
- `ChapterManaging`
- `SyncManaging`
- `NetworkMonitoring`
- `StorageManaging`

#### Step 4.3: Update BookVaultApp to create container

Update `ios/BookVault/BookVaultApp.swift`:

```swift
import SwiftUI

@main
struct BookVaultApp: App {
    @StateObject private var container = DependencyContainer()

    init() {
        // Phase 8: Start background sync monitoring
        Task { @MainActor in
            SyncManager.shared.startMonitoring()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .environmentObject(container.authManager as! AuthManager)
                // Add other services as needed
        }
    }
}
```

#### Step 4.4: Update views to use injected dependencies

Gradually update views to receive dependencies from environment:

```swift
// Before:
struct LibraryView: View {
    @StateObject private var authManager = AuthManager.shared  // ❌ Singleton

// After:
struct LibraryView: View {
    @EnvironmentObject var container: DependencyContainer  // ✅ Injected

    // Access via container:
    // container.authManager.isAuthenticated
```

#### Step 4.5: Update tests to use MockDependencyContainer

```swift
func testLibraryLoading() async {
    let mockAPI = MockAPIClient()
    mockAPI.fetchLibraryResult = .success([testBook])

    let container = MockDependencyContainer(
        apiClient: mockAPI,
        libraryManager: MockLibraryManager()
    )

    let viewModel = LibraryViewModel(container: container)
    await viewModel.loadLibrary()

    XCTAssertEqual(viewModel.books.count, 1)
}
```

#### Step 4.6: Deprecate .shared accessors (optional)

Add deprecation warnings to encourage migration:

```swift
class AuthManager: AuthManaging {
    @available(*, deprecated, message: "Use dependency injection instead of shared instance")
    static let shared = AuthManager()

    // ...
}
```

### Verification Checklist

- [ ] `DependencyContainer.swift` exists with all service properties
- [ ] All services have corresponding protocols
- [ ] `BookVaultApp` creates and injects container
- [ ] At least one view is updated to use container
- [ ] At least one test uses `MockDependencyContainer`
- [ ] All tests pass

### Commit Message

```
refactor(ios): implement dependency injection container

- Create DependencyContainer protocol and implementation
- Create MockDependencyContainer for testing
- Add protocols for all services (AuthManaging, etc.)
- Update BookVaultApp to create and inject container
- Update [specific views] to use injected dependencies
- Update tests to use mock container

This enables better testability and explicit dependency management.

🤖 Generated with Claude Code
```

---

## Phase 5: OpenAPI Swift Drift + Security CI

**Effort**: Small (30 minutes)
**Priority**: Lower
**Dependencies**: None (can be done anytime)

### Problem

TypeScript types have drift detection (`api:check-drift`) but Swift models don't. If someone modifies the OpenAPI spec and forgets to regenerate Swift, the iOS app will have stale types.

### Implementation Steps

#### Step 5.1: Add Swift drift check to api.yml

Update `.github/workflows/api.yml`, add new job:

```yaml
check-swift-types:
  name: Check Swift Types are Up-to-Date
  runs-on: macos-14
  steps:
    - uses: actions/checkout@v4

    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.0'

    - name: Install OpenAPI Generator
      run: brew install openapi-generator

    - name: Install SwiftFormat
      run: brew install swiftformat

    - name: Generate Swift types
      run: npm run api:generate:swift

    - name: Check for uncommitted changes
      run: |
        if ! git diff --exit-code ios/BookVault/Generated/; then
          echo "❌ ERROR: Generated Swift types are out of sync with OpenAPI spec"
          echo "Please run: npm run api:generate:swift"
          echo "Then commit the updated files in ios/BookVault/Generated/"
          git diff ios/BookVault/Generated/
          exit 1
        fi
        echo "✅ Swift types are up-to-date"
```

#### Step 5.2: Add npm script for Swift drift check

Update `package.json` scripts:

```json
{
  "scripts": {
    "api:check-drift": "npm run api:generate:ts && git diff --exit-code lib/api-types.ts",
    "api:check-drift:swift": "npm run api:generate:swift && git diff --exit-code ios/BookVault/Generated/",
    "api:check-drift:all": "npm run api:check-drift && npm run api:check-drift:swift"
  }
}
```

#### Step 5.3: Update pre-commit hook (optional)

Update `.husky/pre-commit` to regenerate Swift too:

```bash
# OpenAPI: Check if spec changed and regenerate types
if git diff --cached --name-only | grep -q "docs/api/openapi.yaml"; then
  echo "📝 OpenAPI spec changed, regenerating TypeScript types..."
  npm run api:generate:ts
  git add lib/api-types.ts

  echo "📝 Regenerating Swift types..."
  npm run api:generate:swift
  git add ios/BookVault/Generated/

  echo "✅ Validating OpenAPI spec..."
  npm run api:validate || {
    echo "❌ OpenAPI spec validation failed"
    exit 1
  }
fi
```

#### Step 5.4: (Optional) Add Semgrep security scanning

Create `.github/workflows/security.yml`:

```yaml
name: Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 * * 1' # Weekly on Monday

jobs:
  semgrep:
    name: Semgrep SAST
    runs-on: ubuntu-latest
    container:
      image: semgrep/semgrep
    steps:
      - uses: actions/checkout@v4

      - name: Run Semgrep
        run: semgrep ci --config auto --config p/security-audit --config p/secrets
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }} # Optional: for Semgrep Cloud
```

**Note**: Semgrep is optional and requires signing up at semgrep.dev for the app token (free for open source).

### Verification Checklist

- [ ] Swift drift check job added to `api.yml`
- [ ] `npm run api:check-drift:swift` works locally
- [ ] Pre-commit hook regenerates Swift types (if enabled)
- [ ] (Optional) Semgrep workflow runs on PR

### Commit Message

```
feat(ci): add Swift type drift detection

- Add check-swift-types job to api.yml workflow
- Add api:check-drift:swift npm script
- Update pre-commit hook to regenerate Swift types
- Ensures iOS app types stay in sync with OpenAPI spec

🤖 Generated with Claude Code
```

---

## Appendix: Tool Reference

### Installation Commands

```bash
# All tools at once
brew install swiftlint swiftformat peripheryapp/periphery/periphery openapi-generator

# Verify installations
swiftlint version
swiftformat --version
periphery version
openapi-generator version
```

### Quick Reference

| Tool        | Purpose             | Config File          | Run Command                                   |
| ----------- | ------------------- | -------------------- | --------------------------------------------- |
| SwiftLint   | Swift linting       | `ios/.swiftlint.yml` | `swiftlint lint --config .swiftlint.yml`      |
| SwiftFormat | Swift formatting    | `ios/.swiftformat`   | `swiftformat BookVault --config .swiftformat` |
| Periphery   | Dead code detection | `ios/.periphery.yml` | `periphery scan --config .periphery.yml`      |
| lint-staged | Pre-commit linting  | `package.json`       | Runs via husky                                |
| ESLint      | JS/TS linting       | `.eslintrc.json`     | `npm run lint`                                |
| Prettier    | JS/TS formatting    | `.prettierrc.json`   | `npm run format`                              |

### Troubleshooting

**SwiftLint: "No lintable files found"**

- Check `included` paths in `.swiftlint.yml`
- Run from `ios/` directory

**Periphery: "Could not find scheme"**

- Run `xcodegen generate` first
- Check scheme name matches `project.yml`

**Pre-commit hook not running**

- Ensure husky is installed: `npm run prepare`
- Check `.husky/pre-commit` is executable: `chmod +x .husky/pre-commit`

**CI Swift job fails on macOS runner**

- Ensure `macos-14` runner is used (has Xcode 15)
- Check Homebrew installs aren't cached incorrectly

---

## Progress Tracking

Use this checklist to track implementation progress:

- [ ] **Phase 1**: Pre-commit + Main CI
- [ ] **Phase 2**: SwiftLint + SwiftFormat
- [ ] **Phase 3**: Dead Code + Strict Warnings
- [ ] **Phase 4**: Dependency Injection
- [ ] **Phase 5**: Swift Drift + Security

**Last Updated**: [Date when you complete each phase]
