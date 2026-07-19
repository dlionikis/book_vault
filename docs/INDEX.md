# Documentation Index

> Quick navigation for Book Vault documentation

**Last Updated**: January 4, 2026

---

## Start Here

| File                         | Purpose                                               |
| ---------------------------- | ----------------------------------------------------- |
| [../CLAUDE.md](../CLAUDE.md) | **Read first** - Project overview, commands, patterns |
| [STATUS.md](STATUS.md)       | Current state, recent PRs, roadmap                    |

---

## Quick Reference

| File                                               | Purpose              | When to Use                     |
| -------------------------------------------------- | -------------------- | ------------------------------- |
| [../components/README.md](../components/README.md) | Component inventory  | "Which component should I use?" |
| [../app/api/README.md](../app/api/README.md)       | All API endpoints    | "What's the endpoint path?"     |
| [../lib/README.md](../lib/README.md)               | Utility module index | "Where's the helper function?"  |

---

## Core References

| File                                             | Purpose                      | When to Use                     |
| ------------------------------------------------ | ---------------------------- | ------------------------------- |
| [development-process.md](development-process.md) | Gates, all tests, invariants | "What must pass before I push?" |
| [component-guide.md](component-guide.md)         | Component selection          | "Which component?"              |
| [data-flows.md](data-flows.md)                   | How data moves               | "How does this flow?"           |
| [api-quick-ref.md](api-quick-ref.md)             | API endpoints                | "What's the request/response?"  |
| [testing.md](testing.md)                         | All test commands            | "How do I test?"                |
| [storybook.md](storybook.md)                     | Component stories            | "How do I use Storybook?"       |

---

## By Task

**Before pushing / opening a PR** (read this first):

- [development-process.md](development-process.md) - The complete gate: every test, the pre-commit hook, what CI enforces, and the hardening invariants that must not regress

**Implementing features**:

1. [component-guide.md](component-guide.md) → 2. [data-flows.md](data-flows.md) → 3. [api-quick-ref.md](api-quick-ref.md)

**iOS development**:

- [mobile/architecture.md](mobile/architecture.md) - SwiftUI + MVVM patterns & maintenance
- [mobile/xcodegen-guide.md](mobile/xcodegen-guide.md) - Adding files to Xcode

**Deploying**:

- [aws-deployment-reference.md](aws-deployment-reference.md) - Quick deploy commands & architecture
- [database-migration-guide.md](database-migration-guide.md) - Production DB migrations

**Understanding the system**:

- [architecture.md](architecture.md) - System design
- [data-validation-overview.md](data-validation-overview.md) - Type safety quick overview
- [data-validation-layers.md](data-validation-layers.md) - Full details (when needed)

---

## API Documentation

| File                                             | Purpose                        |
| ------------------------------------------------ | ------------------------------ |
| [api/openapi.yaml](api/openapi.yaml)             | OpenAPI spec (source of truth) |
| [api/api-reference.html](api/api-reference.html) | Generated API docs             |

**Commands**: `npm run api:validate`, `npm run api:generate`, `npm run api:docs`

---

## Security & Config

| File                                             | Purpose                            |
| ------------------------------------------------ | ---------------------------------- |
| [API_SECURITY.md](API_SECURITY.md)               | Auth patterns, endpoint protection |
| [media-configuration.md](media-configuration.md) | S3 vs local file setup             |
| [media-security.md](media-security.md)           | Media access control               |

---

## iOS Reference

| File                                                   | Purpose                       |
| ------------------------------------------------------ | ----------------------------- |
| [mobile/architecture.md](mobile/architecture.md)       | SwiftUI + MVVM patterns       |
| [mobile/api-integration.md](mobile/api-integration.md) | API client examples           |
| [mobile/ios-features.md](mobile/ios-features.md)       | Background audio, lock screen |
| [mobile/xcodegen-guide.md](mobile/xcodegen-guide.md)   | Adding files to Xcode         |

---

## Setup & Deployment

| File                                                       | Purpose                                                       |
| ---------------------------------------------------------- | ------------------------------------------------------------- |
| [aws-deployment-reference.md](aws-deployment-reference.md) | AWS deploy commands & architecture                            |
| [infra/production.md](infra/production.md)                 | Auto-generated AWS infrastructure inventory (ARNs, endpoints) |
| [database-migration-guide.md](database-migration-guide.md) | Production DB migrations                                      |
| [database-reset-procedure.md](database-reset-procedure.md) | Full database reset                                           |

---

## Plans (In Progress)

| File                                                                                     | Purpose                              |
| ---------------------------------------------------------------------------------------- | ------------------------------------ |
| [plans/s3-archive-restore-workflow-v2.md](plans/s3-archive-restore-workflow-v2.md)       | S3 cold storage restore feature plan |
| [plans/audible-download-plan.md](plans/audible-download-plan.md)                         | Audible download integration plan    |
| [plans/app-store-submission-review-guide.md](plans/app-store-submission-review-guide.md) | App Store submission guide           |

---

## Archived Documentation

Historical plans in `archive/` - read only for investigating past decisions:

- `archive/completed-plans/` - Completed implementation plans
- `archive/ios-phases/` - iOS phase completion summaries
