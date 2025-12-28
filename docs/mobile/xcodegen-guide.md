# XcodeGen Guide - Automated Xcode Project Management

**Last Updated**: December 27, 2025

> **TL;DR**: We use XcodeGen to automatically manage the Xcode project file. Run `cd ios && xcodegen generate` after adding/removing Swift files. No manual "Add Files to Xcode" needed!

---

## What is XcodeGen?

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is a command-line tool that generates Xcode projects from a YAML specification file.

**Benefits**:

- ✅ No manual file management in Xcode
- ✅ Auto-discovers all Swift files
- ✅ Consistent project structure
- ✅ Reduces merge conflicts in `.xcodeproj`
- ✅ Version control friendly (only `project.yml` changes)
- ✅ Fast (~1 second to regenerate)

---

## Installation

```bash
brew install xcodegen
```

**Verify installation**:

```bash
xcodegen --version
# Should show: Version: 2.x.x
```

---

## Configuration

Our XcodeGen configuration is in [`ios/project.yml`](../../ios/project.yml).

### Key Settings

```yaml
name: BookVault

options:
  createIntermediateGroups: true # Auto-creates folder groups

targets:
  BookVault:
    type: application
    platform: iOS

    sources:
      # Main source files - auto-discovers ALL Swift files!
      - path: BookVault
        excludes:
          - 'Generated/**'
          - '**/*.md'
          - 'Assets.xcassets'
          - 'Preview Content/**'
        createIntermediateGroups: true

      # Generated OpenAPI models
      - path: BookVault/Generated/Models
        excludes:
          - 'Package.swift'
          - '*.md'
        type: group
```

**How it works**:

1. `path: BookVault` tells XcodeGen to scan the entire `BookVault/` folder
2. `createIntermediateGroups: true` creates folder groups matching directory structure
3. Excluded files (`.md`, `Assets.xcassets`, etc.) are skipped
4. All discovered Swift files are automatically added to the build target

---

## Usage

### Basic Commands

```bash
# Navigate to iOS directory
cd ios

# Generate/regenerate Xcode project
xcodegen generate

# Verify configuration (doesn't generate)
xcodegen dump

# Get help
xcodegen --help
```

### When to Regenerate

Run `xcodegen generate` after:

- ✅ Creating new Swift files
- ✅ Deleting Swift files
- ✅ Moving files between folders
- ✅ Renaming files
- ✅ Pulling changes that add/remove files
- ✅ Modifying `project.yml` configuration

**You can run it anytime** - it's idempotent and fast!

---

## Workflows

### Adding a New Swift File

**Old Way (Manual)**:

1. Create Swift file
2. Open Xcode
3. Right-click folder → "Add Files to BookVault..."
4. Navigate to file
5. Check settings
6. Click Add
7. Verify it's in the correct group
8. Verify target membership

**New Way (XcodeGen)**:

```bash
# 1. Create the file
touch ios/BookVault/Views/MyNewView.swift

# 2. Regenerate project
cd ios && xcodegen generate

# 3. Done! File is discovered and added automatically
```

### Adding Multiple Files (e.g., Phase 2)

**Example**: Phase 2 added `AudioPlayerManager.swift` and `NowPlayingView.swift`

```bash
# Files were created:
# - ios/BookVault/Services/AudioPlayerManager.swift
# - ios/BookVault/Views/Player/NowPlayingView.swift

# Regenerate project (discovers both files)
cd ios && xcodegen generate

# Build to verify
xcodebuild -project BookVault.xcodeproj -scheme BookVault build
# Result: BUILD SUCCEEDED
```

XcodeGen automatically:

- Found both files
- Created the `Player` group under `Views`
- Added files to the `BookVault` target
- Maintained proper folder structure

### After Pulling Changes

```bash
# Pull latest from Git
git pull

# If new Swift files were added, regenerate
cd ios && xcodegen generate

# Build and run
open BookVault.xcodeproj
# Press ⌘R in Xcode
```

---

## Project Structure

XcodeGen mirrors the filesystem structure:

```
ios/BookVault/
├── Services/
│   ├── APIClient.swift         ← Auto-added to "Services" group
│   ├── AuthManager.swift        ← Auto-added to "Services" group
│   └── AudioPlayerManager.swift ← Auto-added to "Services" group
├── Views/
│   ├── Auth/
│   │   └── LoginView.swift      ← Auto-added to "Views/Auth" group
│   ├── Books/
│   │   ├── BookDetailView.swift ← Auto-added to "Views/Books" group
│   │   └── BooksListView.swift  ← Auto-added to "Views/Books" group
│   └── Player/
│       └── NowPlayingView.swift ← Auto-added to "Views/Player" group
└── Generated/
    └── Models/                  ← Separate group (different config)
        └── *.swift              ← Auto-added to "Generated/Models" group
```

**In Xcode navigator**, you'll see the same structure!

---

## Advanced Configuration

### Adding a New Target

To add a new target (e.g., tests, extension):

```yaml
targets:
  BookVault:
    # ... existing config

  BookVaultTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: BookVaultTests
    dependencies:
      - target: BookVault
```

Then regenerate: `xcodegen generate`

### Adding Dependencies

For SPM packages or frameworks:

```yaml
targets:
  BookVault:
    dependencies:
      - package: Alamofire # SPM package
      - framework: AVFoundation # System framework
      - sdk: CoreData.framework # SDK framework
```

### Custom Build Settings

```yaml
targets:
  BookVault:
    settings:
      base:
        SWIFT_VERSION: '5.0'
        IPHONEOS_DEPLOYMENT_TARGET: '17.0'
      configs:
        Debug:
          SWIFT_OPTIMIZATION_LEVEL: '-Onone'
        Release:
          SWIFT_OPTIMIZATION_LEVEL: '-O'
```

---

## Troubleshooting

### "File not found" errors in Xcode

**Problem**: Xcode shows files in red or "file not found"

**Solution**:

```bash
cd ios
xcodegen generate
```

This regenerates the project and fixes broken file references.

### Files not in correct group

**Problem**: Files are in the wrong folder group in Xcode

**Cause**: Filesystem structure doesn't match what XcodeGen expects

**Solution**:

1. Move files to correct folder on filesystem
2. Regenerate: `xcodegen generate`

### Xcode project has uncommitted changes

**Problem**: Git shows `.xcodeproj` as modified even after regenerating

**Cause**: Xcode auto-saves project changes (build settings, etc.)

**Solution**:

1. Review changes: `git diff ios/BookVault.xcodeproj/project.pbxproj`
2. If they're Xcode auto-saves, discard: `git checkout ios/BookVault.xcodeproj`
3. Regenerate: `xcodegen generate`
4. Commit only `project.yml` changes

### XcodeGen fails with "Invalid YAML"

**Problem**: `xcodegen generate` fails with YAML syntax error

**Solution**:

1. Validate YAML: `xcodegen dump` (shows parsed config)
2. Check indentation (YAML is whitespace-sensitive)
3. Fix syntax errors in `project.yml`

---

## Git Workflow

### What to Commit

**✅ Commit**:

- `ios/project.yml` (XcodeGen config)
- Swift source files
- `ios/.gitignore`

**❌ Don't manually edit**:

- `ios/BookVault.xcodeproj/project.pbxproj` (auto-generated)
- `ios/BookVault.xcodeproj/xcuserdata/` (already gitignored)

### Handling Merge Conflicts

**Old way** (manual Xcode):

- Merge conflicts in `project.pbxproj` are a nightmare (XML format)
- Often require manual Xcode project repair

**New way** (XcodeGen):

1. Resolve conflicts in `project.yml` (simple YAML)
2. Regenerate: `xcodegen generate`
3. Project file is now conflict-free

---

## Integration with Other Tools

### With OpenAPI Generator

```bash
# 1. Generate Swift models from OpenAPI
npm run api:generate:swift

# 2. Regenerate Xcode project (includes new models)
cd ios && xcodegen generate

# 3. Build
xcodebuild -project BookVault.xcodeproj -scheme BookVault build
```

### With VS Code + Sweetpad

```bash
# 1. Create files in VS Code
touch ios/BookVault/Services/NewService.swift

# 2. Regenerate project
cd ios && xcodegen generate

# 3. Generate build server config (for IntelliSense)
# In VS Code Command Palette: "Sweetpad: Generate Build Server Config"

# 4. Build in VS Code
# Command Palette: "Sweetpad: Build"
```

### With CI/CD

```yaml
# .github/workflows/ios.yml
- name: Generate Xcode Project
  run: |
    cd ios
    xcodegen generate

- name: Build iOS App
  run: |
    xcodebuild -project ios/BookVault.xcodeproj \
      -scheme BookVault \
      -destination 'platform=iOS Simulator,name=iPhone 15' \
      build
```

---

## Best Practices

### 1. Regenerate Often

Run `xcodegen generate` frequently. It's fast and ensures project is always in sync.

### 2. Keep project.yml Simple

Only add configuration that's truly needed. XcodeGen has good defaults.

### 3. Use Filesystem Structure

Organize files in folders the way you want them in Xcode. XcodeGen mirrors it.

### 4. Version Control project.yml

Commit all changes to `project.yml`. It's the source of truth for project structure.

### 5. Document Custom Settings

If you add custom build settings, comment them in `project.yml`:

```yaml
settings:
  base:
    # Enable background audio mode (Phase 3)
    INFOPLIST_KEY_UIBackgroundModes: 'audio'
```

---

## Resources

- **Official Docs**: https://github.com/yonaskolb/XcodeGen
- **Specification**: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- **Examples**: https://github.com/yonaskolb/XcodeGen/tree/master/Examples

---

## Summary

XcodeGen eliminates manual Xcode project management:

1. ✅ Create Swift files in the right folders
2. ✅ Run `cd ios && xcodegen generate`
3. ✅ Build and run

**No more**:

- ❌ "Add Files to Xcode..." dialogs
- ❌ Forgetting to add files to targets
- ❌ Merge conflicts in `project.pbxproj`
- ❌ Inconsistent project structure

**The result**: Faster development, fewer errors, happier developers! 🎉
