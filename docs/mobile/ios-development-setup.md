# iOS Development Setup

Quick guide to setting up the iOS development environment.

> **⭐ NEW**: You can now develop iOS apps entirely in VS Code! See [VS Code iOS Setup Guide](vscode-ios-setup.md) for the recommended workflow.

## Prerequisites

- macOS with Xcode 15+ installed
- Node.js 18+ (for backend)
- OpenAPI Generator: `brew install openapi-generator`
- jq (for test fixtures): `brew install jq`

**Optional (for VS Code iOS development)**:

- xcode-build-server: `brew install xcode-build-server`
- Sweetpad extension for VS Code
- Swift extension for VS Code (swiftlang.swift-vscode)

## Initial Setup

### 1. Clone and Install

```bash
git clone <repo>
cd book_vault
npm install
```

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
