# VS Code iOS Development Setup Guide

**Last Updated**: December 26, 2025

> **TL;DR**: Complete iOS development in VS Code with Swift extension + Sweetpad + xcode-build-server. Get code completion, debugging, and Copilot support without leaving VS Code.

---

## Why VS Code for iOS Development?

**Advantages over Xcode-only workflow**:

- ✅ **Unified environment**: Backend + iOS in one IDE
- ✅ **Superior Copilot integration**: Better AI assistance than Xcode's Copilot extension
- ✅ **Familiar workflow**: Same editor for TypeScript and Swift
- ✅ **Better git integration**: VS Code's git tooling is excellent
- ✅ **Faster context switching**: No need to switch between IDEs
- ✅ **Shared extensions**: Use same productivity tools for both codebases

**When you still need Xcode**:

- SwiftUI Previews (Canvas feature)
- Interface Builder / Storyboards (if using them)
- App Store submission and archiving
- Initial project setup (already done ✅)

---

## Prerequisites

- ✅ macOS with Xcode installed
- ✅ VS Code installed
- ✅ Homebrew package manager

---

## Step 1: Install Required Tools

### 1.1 Install xcode-build-server

```bash
brew install xcode-build-server
```

This tool generates `buildServer.json` that enables SourceKit-LSP (the Swift language server) to understand your Xcode project.

### 1.2 Verify Swift Extension

Check that the official Swift extension is installed:

```bash
# The extension is already installed at:
# ~/.vscode/extensions/swiftlang.swift-vscode-2.14.2
```

If not installed, install via VS Code:

- Open Extensions (⌘⇧X)
- Search: `swiftlang.swift-vscode`
- Click Install

### 1.3 Install Sweetpad Extension

Sweetpad adds iOS-specific features (build, run, debug):

1. Open Extensions in VS Code (⌘⇧X)
2. Search: `Sweetpad`
3. Click Install
4. Reload VS Code if prompted

---

## Step 2: Configure Workspace

### 2.1 Create VS Code Settings

Create `.vscode/settings.json` in project root:

```json
{
  "sweetpad.build.xcodeProjectPath": "ios/BookVault.xcodeproj",
  "sweetpad.build.scheme": "BookVault",
  "sweetpad.build.buildConfiguration": "Debug",
  "swift.path": "/usr/bin/swift",
  "swift.sourcekit-lsp.serverPath": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
  "editor.formatOnSave": true,
  "swift.autoGenerateLaunchConfigurations": true
}
```

**Important**:

- Use `xcodeProjectPath` for `.xcodeproj` files (what we have)
- Use `xcodeWorkspacePath` only if you have a `.xcworkspace` file
- Adjust Swift paths if using multiple Xcode versions or custom Swift toolchains

### 2.2 Generate Build Server Config

1. Open Command Palette (⌘⇧P)
2. Type: `Sweetpad: Generate Build Server Config`
3. Press Enter
4. Wait for `buildServer.json` to be created in project root

This file tells SourceKit-LSP how to compile your project, enabling full IntelliSense.

---

## Step 3: Setup Debugging

### 3.1 Create Launch Configuration

1. Open Debug panel (⌘⇧D)
2. Click "create a launch.json file"
3. Select: `Sweetpad (LLDB)` from the list
4. VS Code creates `.vscode/launch.json` automatically

**Generated configuration** (example):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "sweetpad-lldb",
      "request": "launch",
      "name": "Debug iOS App",
      "program": "${workspaceFolder}/ios/build/Debug-iphonesimulator/BookVault.app"
    }
  ]
}
```

### 3.2 Test Debugging

1. Set a breakpoint in `BookVaultApp.swift` (click left gutter)
2. Press F5 or click "Run and Debug"
3. Select iOS Simulator when prompted
4. App should build, launch, and stop at breakpoint

---

## Step 4: Verify Everything Works

### 4.1 Test Code Completion

1. Open `ios/BookVault/BookVaultApp.swift`
2. Start typing `import Swi...`
3. Should see autocomplete suggestions for `SwiftUI`
4. Type `struct` - should get completion for struct syntax

### 4.2 Test Jump to Definition

1. In `BookVaultApp.swift`, ⌘-click on `ContentView`
2. Should jump to `ContentView.swift`
3. Use ⌘T to search for symbols across the project

### 4.3 Test Building

1. Open Command Palette (⌘⇧P)
2. Run: `Sweetpad: Build`
3. Should see build output in terminal
4. Verify build succeeds

### 4.4 Test Running

**Important**: The app must be built before it can run.

1. Open Command Palette (⌘⇧P)
2. Run: `Sweetpad: Build` (first time only)
3. Wait for build to complete
4. Run: `Sweetpad: Run (for debugging)`
5. Select iOS Simulator
6. App should launch in Simulator

**Note**: Subsequent runs will automatically rebuild if needed, but the first run requires an explicit build.

---

## Step 5: Optional Enhancements

### 5.1 Add GitHub Copilot (if not installed)

VS Code's Copilot integration is superior to Xcode's:

```bash
# Install Copilot extension
# Open Extensions, search "GitHub Copilot", install
```

### 5.2 Recommended Extensions

- **Swift Indent**: Better Swift code formatting
- **GitLens**: Enhanced git features
- **Error Lens**: Inline error messages
- **Todo Tree**: Track TODOs across codebase

### 5.3 Keyboard Shortcuts

Add to `keybindings.json` for iOS-specific tasks:

```json
[
  {
    "key": "cmd+r",
    "command": "sweetpad.build.run",
    "when": "resourceLangId == swift"
  },
  {
    "key": "cmd+b",
    "command": "sweetpad.build.build",
    "when": "resourceLangId == swift"
  }
]
```

---

## Daily Workflow

### Start Development Session

```bash
# Terminal 1: Start backend
docker-compose up -d
npm run dev

# Terminal 2: Watch API changes (optional)
npm run api:watch

# VS Code: Open workspace
# - Backend files on left
# - iOS files on right
# - Integrated terminal at bottom
```

### Edit Swift Code

1. Open Swift file in VS Code
2. Get full IntelliSense and autocomplete
3. Use Copilot for AI suggestions
4. Set breakpoints as needed
5. Save file (auto-formats with SwiftFormat)

### Build and Test

```bash
# From VS Code Command Palette (⌘⇧P):
Sweetpad: Build              # Compile app
Sweetpad: Run                # Launch in Simulator
Sweetpad: Test               # Run unit tests

# Or use keyboard shortcuts (if configured):
⌘R                           # Run
⌘B                           # Build
```

### Debug

1. Set breakpoints in Swift code (click gutter)
2. Press F5 or click Debug button
3. Use Debug Console to inspect variables
4. Step through code with F10 (step over) / F11 (step into)
5. View call stack and variables in sidebar

### Commit Changes

```bash
# Git integration works seamlessly for both backend and iOS
git add .
git commit -m "feat(ios): add login screen"
git push
```

---

## Troubleshooting

### Code Completion Not Working

**Problem**: No autocomplete suggestions in Swift files

**Solutions**:

1. Ensure `buildServer.json` exists in project root
   - Run `Sweetpad: Generate Build Server Config` again
2. Check SourceKit-LSP path in settings.json
3. Restart Swift Language Server:
   - Command Palette → `Swift: Restart Language Server`
4. Check Output panel → Swift LSP for errors

### Build Fails

**Problem**: `Sweetpad: Build` command fails

**Solutions**:

1. Verify Xcode project builds in Xcode first
2. Check `xcodeWorkspacePath` in settings.json is correct
3. Clean build folder: `Sweetpad: Clean Build`
4. Check Output panel for detailed error messages

### Debugger Won't Attach

**Problem**: Debugging doesn't start or breakpoints don't work

**Solutions**:

1. Verify LLDB DAP extension is installed (dependency of Swift extension)
2. Check launch.json configuration is correct
3. Ensure app builds successfully first
4. Try restarting VS Code

### Simulator Not Launching

**Problem**: iOS Simulator doesn't start when running app

**Solutions**:

1. Launch Simulator manually first:
   ```bash
   open -a Simulator
   ```
2. Select a device in Simulator (Hardware → Device)
3. Run `Sweetpad: Run` again
4. Check Console for error messages

### Missing Workspace Contents File

**Problem**: Error reading `contents.xcworkspacedata` file

**Symptom**:

```
Error: ENOENT: no such file or directory, open '.../project.xcworkspace/contents.xcworkspacedata'
```

**Solution**:

This file is auto-generated by Xcode but may be missing in fresh projects. Create it manually:

```bash
# Create the file
cat > ios/BookVault.xcodeproj/project.xcworkspace/contents.xcworkspacedata << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
EOF
```

Alternatively, open the project in Xcode once - it will auto-generate this file.

### App Path Does Not Exist

**Problem**: "App path does not exist. Have you built the app?"

**Solution**:

The app must be built before it can run. Use Command Palette:

1. Run: `Sweetpad: Build`
2. Wait for build to succeed
3. Then run: `Sweetpad: Run (for debugging)`

---

## Performance Tips

1. **Disable unused extensions** when working on iOS to reduce memory usage
2. **Use .swiftlint.yml** for consistent code style across team
3. **Enable "Format on Save"** in settings.json for auto-formatting
4. **Use workspace folders** to organize backend and iOS separately

---

## Migration Path

If you're currently using Xcode exclusively:

**Week 1**: Try VS Code for simple edits, use Xcode for building/running
**Week 2**: Start building and running from VS Code, use Xcode for debugging
**Week 3**: Full VS Code workflow, only use Xcode for SwiftUI Previews
**Week 4**: VS Code primary, Xcode only when absolutely necessary

---

## Additional Resources

- [GitHub - swiftlang/vscode-swift](https://github.com/swiftlang/vscode-swift) - Official Swift extension repo
- [Swift.org VS Code Guide](https://www.swift.org/documentation/articles/getting-started-with-vscode-swift.html) - Official setup guide
- [Visual Studio Code setup for iOS development with Copilot](https://blog.kulman.sk/vscode-ios-setup/) - Detailed blog post
- [VS Code Swift Language Docs](https://code.visualstudio.com/docs/languages/swift) - Official VS Code documentation

---

## Summary

You now have a fully-functional iOS development environment in VS Code that supports:

- ✅ Swift code completion and IntelliSense
- ✅ Building and running iOS apps
- ✅ Full debugging with LLDB
- ✅ GitHub Copilot integration
- ✅ Unified backend + iOS workflow
- ✅ Git version control

**Next Steps**: Start Phase 1 development (Authentication & Browsing) directly in VS Code!
