# iOS Mobile Documentation

**Last Updated**: December 25, 2025

This directory contains detailed iOS implementation documentation broken down by topic for better token optimization.

---

## Files in This Directory

| File                                                 | Purpose                                     | Tokens | Read When                          |
| ---------------------------------------------------- | ------------------------------------------- | ------ | ---------------------------------- |
| [implementation-phases.md](implementation-phases.md) | 8 phases with acceptance criteria           | ~1,500 | Planning implementation order      |
| [architecture.md](architecture.md)                   | SwiftUI + MVVM architecture, file structure | ~3,800 | Setting up iOS project structure   |
| [api-integration.md](api-integration.md)             | Swift API client implementation examples    | ~4,000 | Implementing API calls             |
| [ios-features.md](ios-features.md)                   | Background audio, lock screen, CarPlay      | ~3,500 | Implementing iOS-specific features |

**Total**: ~12,800 tokens (split across 4 files for selective reading)

---

## Reading Strategy

### Phase-by-Phase Approach (Recommended)

**Phase 1: Authentication & Browsing**

1. Read [architecture.md](architecture.md) - Understand overall structure
2. Read [api-integration.md](api-integration.md) - Learn API patterns
3. Skip iOS-specific features for now

**Phase 2: Audio Playback (Basic)** 4. Read [ios-features.md](ios-features.md) - Background audio basics 5. Review AVPlayer examples in [architecture.md](architecture.md)

**Phase 3: Background Audio & Lock Screen** 6. Reread [ios-features.md](ios-features.md) - Full background audio section

**Phase 4-8: Continue Reading as Needed**

- Reference [implementation-phases.md](implementation-phases.md) for each phase
- Use other guides as reference for specific implementations

### Topic-Based Approach

**"How do I structure the iOS app?"**
→ Read [architecture.md](architecture.md)

**"How do I call the backend API?"**
→ Read [api-integration.md](api-integration.md)

**"How do I implement background audio?"**
→ Read [ios-features.md](ios-features.md)

**"What should I build first?"**
→ Read [implementation-phases.md](implementation-phases.md)

---

## Parent Documentation

**Start Here First**:

- [../mobile-ios-plan.md](../mobile-ios-plan.md) - Overview & development workflow (~2,800 tokens)
- [../ios-backend-sync.md](../ios-backend-sync.md) - API sync tracker (~2,000 tokens)

**Then read files in this directory as needed per implementation phase.**

---

## Quick Reference

**File organization principle**: Each file in this directory covers a distinct aspect of iOS development:

1. **Phases** → What to build and in what order
2. **Architecture** → How to structure the code
3. **API Integration** → How to communicate with backend
4. **iOS Features** → How to implement platform-specific functionality

Read selectively based on current implementation phase to minimize token usage.
