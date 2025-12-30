# iOS Mobile Documentation

**Status**: ✅ **Complete** (All 8 phases implemented - December 2025)
**Last Updated**: December 29, 2025

---

## Quick Reference

| File                                                 | Purpose                            | When to Read                   |
| ---------------------------------------------------- | ---------------------------------- | ------------------------------ |
| [ios-development-setup.md](ios-development-setup.md) | Environment setup & daily workflow | Setting up or onboarding       |
| [xcodegen-guide.md](xcodegen-guide.md)               | Adding/removing Swift files        | After creating new files       |
| [vscode-ios-setup.md](vscode-ios-setup.md)           | VS Code iOS development            | Optional: unified IDE workflow |

---

## Implementation Reference (Completed)

These docs contain patterns and examples from the implementation. Useful for debugging or understanding architecture:

| File                                     | Purpose                                 | Tokens |
| ---------------------------------------- | --------------------------------------- | ------ |
| [architecture.md](architecture.md)       | SwiftUI + MVVM patterns, file structure | ~3,800 |
| [api-integration.md](api-integration.md) | Swift API client examples, auth flow    | ~4,000 |
| [ios-features.md](ios-features.md)       | Background audio, lock screen, CarPlay  | ~3,500 |

---

## What Was Built

**Phases 1-8 Complete:**

1. ✅ Authentication & Browsing
2. ✅ Audio Playback (Basic)
3. ✅ Background Audio & Lock Screen
4. ✅ Progress Sync
5. ✅ Chapter Navigation
6. ✅ Search & Browse
7. ✅ Offline Downloads
8. ✅ Offline Mode Support

**Deferred to Post-Launch:** User Lists (requires backend API development)

**Archived Plans:** See [archive/completed-plans/ios-implementation-phases.md](../archive/completed-plans/ios-implementation-phases.md)

---

## Common Commands

```bash
# Generate Swift models from OpenAPI
npm run api:generate:swift

# Regenerate Xcode project (after adding/removing files)
cd ios && xcodegen generate

# Start backend for iOS development
npm run dev

# Watch for OpenAPI changes
npm run api:watch
```

---

## Parent Documentation

- [../mobile-ios-plan.md](../mobile-ios-plan.md) - Overview & development workflow
- [../../CLAUDE.md](../../CLAUDE.md) - Project quick reference
