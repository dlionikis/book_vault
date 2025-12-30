# Code Quality Implementation Plan

> **Created**: December 30, 2025
> **Status**: Archived (Phases 1-3 Complete, Phases 4-5 Deferred)
> **Archived**: December 30, 2025

This document provides step-by-step instructions for implementing code quality improvements identified in the BookVault assessment. Each phase is self-contained and can be completed independently.

---

## Implementation Status

| Phase   | Description             | Status      | Notes                                                        |
| ------- | ----------------------- | ----------- | ------------------------------------------------------------ |
| Phase 1 | Pre-commit + Main CI    | ✅ Complete | lint-staged + main.yml workflow                              |
| Phase 2 | SwiftLint + SwiftFormat | ✅ Complete | iOS linting and formatting                                   |
| Phase 3 | Dead Code Detection     | ✅ Complete | Periphery scan, removed dead code                            |
| Phase 4 | Dependency Injection    | ⏸️ Deferred | Low priority - 568 tests work fine with current architecture |
| Phase 5 | Swift Drift + Security  | ⏸️ Deferred | Nice-to-have, TypeScript drift detection already in place    |

### Completed Work (PR #XX)

**Phase 1:**

- Added lint-staged configuration to `package.json`
- Created `.github/workflows/main.yml` for PR validation
- Fixed pre-commit hook that was calling unconfigured lint-staged

**Phase 2:**

- Created `ios/.swiftlint.yml` with project-specific rules
- Created `ios/.swiftformat` with team style preferences
- Reduced SwiftLint violations from 160 to 4 warnings
- Added SwiftLint to iOS CI workflow

**Phase 3:**

- Ran Periphery to detect unused code
- Removed 4 dead code items (~300 lines):
  - `SaveProgressRequest` struct
  - `AudioPlayable.swift` (unused protocol + wrapper)
  - `FlowLayout` struct
  - `ContinueListeningCard` struct
- Added `// periphery:ignore` to intentionally kept code (Previews, MockData)

### Why Phases 4-5 Were Deferred

**Phase 4 (Dependency Injection):**

- The iOS app already has 568 tests with good coverage
- Current singleton pattern works well for this codebase size
- Refactoring would take 2-3 hours with minimal benefit
- Can be revisited if testing becomes painful

**Phase 5 (Swift Drift Detection):**

- TypeScript drift detection is already enforced in CI
- Swift models are tracked in git and updated with spec changes
- Pre-commit hook already regenerates TypeScript types
- Adding Swift regeneration to pre-commit is nice-to-have

---

## Original Plan (For Reference)

### Phase 1: Fix Pre-commit + Add Main CI

**Effort**: Small (30-45 minutes)
**Priority**: High

[Original implementation steps preserved below for reference...]

### Phase 2: Add SwiftLint + SwiftFormat

**Effort**: Small-Medium (45-60 minutes)
**Priority**: High

[Original implementation steps preserved below for reference...]

### Phase 3: Dead Code Detection + Stricter Warnings

**Effort**: Small-Medium (30-60 minutes)
**Priority**: Medium

[Original implementation steps preserved below for reference...]

### Phase 4: iOS Dependency Injection Refactor (DEFERRED)

**Effort**: Medium-Large (2-3 hours)
**Priority**: Medium → Low (deferred)
**Reason for deferral**: Current architecture works well, 568 tests provide good coverage

### Phase 5: OpenAPI Swift Drift + Security CI (DEFERRED)

**Effort**: Small (30 minutes)
**Priority**: Lower → Deferred
**Reason for deferral**: TypeScript drift detection covers the main risk, Swift models are tracked in git

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
| Periphery   | Dead code detection | N/A                  | `periphery scan --project ... --schemes ...`  |
| lint-staged | Pre-commit linting  | `package.json`       | Runs via husky                                |
| ESLint      | JS/TS linting       | `.eslintrc.json`     | `npm run lint`                                |
| Prettier    | JS/TS formatting    | `.prettierrc.json`   | `npm run format`                              |
