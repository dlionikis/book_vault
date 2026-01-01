# Documentation Index

> **Quick navigation for all Book Vault documentation**

---

## 📢 Recent Changes (December 29, 2025)

- **iOS app complete** - All 8 phases implemented (offline mode included)
- **Web app complete** - Ready for AWS deployment
- **Next priority**: AWS Deployment → User Lists (post-launch)

---

## 🚀 Start Here (Required Reading)

1. **[../CLAUDE.md](../CLAUDE.md)** - 📍 **READ THIS FIRST**
   - Quick onboarding reference for new sessions
   - Common commands, tech stack, coding patterns
   - Critical knowledge & gotchas
   - AI-assisted development workflow

2. **[STATUS.md](STATUS.md)** - Current state of the project
   - What's completed (features, recent PRs)
   - What's in progress
   - Known issues & next priorities

---

## 📚 Core References (Read as Needed)

**Use these for daily development work:**

| File                                                   | Purpose                                         | When to Use                                  | Tokens |
| ------------------------------------------------------ | ----------------------------------------------- | -------------------------------------------- | ------ |
| [component-guide.md](component-guide.md)               | Component selection decision tree               | "Which component should I use?"              | ~660   |
| [data-flows.md](data-flows.md)                         | How data moves through the app                  | "How does data flow here?"                   | ~1,170 |
| [data-validation-layers.md](data-validation-layers.md) | OpenAPI/TypeScript/Zod/Prisma/Swift integration | "How do all the type systems work together?" | ~5,200 |
| [api-quick-ref.md](api-quick-ref.md)                   | API endpoint reference (copy-paste)             | "What's the request/response?"               | ~1,000 |
| [storybook.md](storybook.md)                           | Using Storybook for component development       | "How do I use Storybook?"                    | ~300   |

**💡 Token-saving tip**: Read these BEFORE exploring the codebase. Saves 5,000-8,000 tokens per feature.

---

## 🔌 API Documentation

| File                                             | Purpose                                       | Tokens  |
| ------------------------------------------------ | --------------------------------------------- | ------- |
| [api/openapi.yaml](api/openapi.yaml)             | **OpenAPI 3.0 spec** (single source of truth) | ~varies |
| [api/api-reference.html](api/api-reference.html) | 🤖 Auto-generated API docs (interactive)      | N/A     |
| [api-quick-ref.md](api-quick-ref.md)             | Quick cheat sheet + links to generated docs   | ~500    |

**OpenAPI Tools**:

- `npm run api:validate` - Validate spec
- `npm run api:generate` - Generate TypeScript + Swift types
- `npm run api:docs` - Generate HTML documentation
- `npm run docs:generate` - Generate all (types + docs)
- `npm run api:watch` - Auto-regenerate on changes

**After OpenAPI**: [api-reference.html](api/api-reference.html) becomes primary API docs (always up-to-date)

---

## 🏗️ Architecture & Design

| File                                             | Purpose                                          | Tokens |
| ------------------------------------------------ | ------------------------------------------------ | ------ |
| [architecture.md](architecture.md)               | System architecture, tech stack, database schema | ~2,650 |
| [development-roadmap.md](development-roadmap.md) | Future plans, prioritization, feature roadmap    | ~4,100 |

---

## 🔐 Security & Configuration

| File                                             | Purpose                                            | Tokens |
| ------------------------------------------------ | -------------------------------------------------- | ------ |
| [API_SECURITY.md](API_SECURITY.md)               | Auth patterns, endpoint protection, security audit | ~1,500 |
| [media-configuration.md](media-configuration.md) | S3 vs local file setup, environment config         | ~470   |
| [media-security.md](media-security.md)           | Media access control, S3 security                  | ~750   |
| [security.md](security.md)                       | Code quality tools, linting, git hooks             | ~395   |

---

## 📱 Mobile Development (iOS - Complete)

**Status**: ✅ All 8 phases implemented (December 2025)

### Overview & Workflow

| File                                     | Purpose                                  | Tokens |
| ---------------------------------------- | ---------------------------------------- | ------ |
| [mobile-ios-plan.md](mobile-ios-plan.md) | **iOS overview, commands & maintenance** | ~800   |
| [mobile/README.md](mobile/README.md)     | Quick reference & documentation index    | ~300   |

### Setup Guides (Active)

| File                                                               | Purpose                                 | Tokens |
| ------------------------------------------------------------------ | --------------------------------------- | ------ |
| [mobile/ios-development-setup.md](mobile/ios-development-setup.md) | iOS development environment setup       | ~1,200 |
| [mobile/xcodegen-guide.md](mobile/xcodegen-guide.md)               | **XcodeGen: How to add files to Xcode** | ~3,000 |
| [mobile/vscode-ios-setup.md](mobile/vscode-ios-setup.md)           | VS Code for iOS development (optional)  | ~3,000 |

### Implementation Reference (Completed - Use for Debugging)

| File                                                   | Purpose                                     | Tokens |
| ------------------------------------------------------ | ------------------------------------------- | ------ |
| [mobile/architecture.md](mobile/architecture.md)       | SwiftUI + MVVM architecture, file structure | ~3,800 |
| [mobile/api-integration.md](mobile/api-integration.md) | Swift API client implementation examples    | ~4,000 |
| [mobile/ios-features.md](mobile/ios-features.md)       | Background audio, lock screen, CarPlay      | ~3,500 |

**Quick Start for iOS Development**:

1. Read [mobile-ios-plan.md](mobile-ios-plan.md) for overview & commands
2. See [mobile/xcodegen-guide.md](mobile/xcodegen-guide.md) for adding files
3. Reference implementation docs only when debugging

**Archived**: [archive/completed-plans/ios-implementation-phases.md](archive/completed-plans/ios-implementation-phases.md) - Original phase plan

---

## 🧪 Testing & Quality

| File                                                                       | Purpose                                                          | Tokens |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------ |
| [testing.md](testing.md)                                                   | **Complete testing guide** (web, iOS, CI, deployment validation) | ~1,500 |
| [code-quality-implementation-plan.md](code-quality-implementation-plan.md) | SwiftLint, Periphery, CI improvements (5 phases)                 | ~4,500 |

---

## 📦 Setup & Deployment

| File                                             | Purpose                                        | Tokens |
| ------------------------------------------------ | ---------------------------------------------- | ------ |
| [project-setup.md](project-setup.md)             | Initial project setup, installation, first run | ~1,170 |
| [aws-deployment-plan.md](aws-deployment-plan.md) | AWS infrastructure & **Quick Deploy Guide**    | ~8,000 |

**Quick Deploy** (routine code deployments):
See [aws-deployment-plan.md#quick-deploy-guide](aws-deployment-plan.md#quick-deploy-guide) for streamlined build → push → deploy commands.

---

## 📚 Archived Documentation

**Historical planning documents** (completed work, rarely needed):

Located in `archive/` folder:

- `archive/completed-plans/ios-implementation-phases.md` - iOS phase plan (all 8 phases complete)
- `archive/completed-plans/ios-testing-implementation-plan.md` - iOS testing (568 tests complete)
- `archive/completed-plans/ios-testing-real-services-plan.md` - Real service testing strategy
- `archive/completed-plans/ios-testing-recommendations.md` - Testing recommendations
- `archive/completed-plans/ios-backend-sync.md` - iOS-backend sync tracker (historical)
- `archive/completed-plans/implement-backend-support-for-mobile.md` (71K, 9,512 words)
- `archive/completed-plans/storybook-plan.md` (30K, 3,913 words)
- `archive/completed-plans/fix-api-tests.md` (10K, 1,311 words)
- `archive/completed-plans/library-concurrency-tests.md` (6K, 819 words)

**Implementation Plans**:

Located in `archive/implementation-plans/` folder:

- [OpenAPI Drift Prevention Plan](archive/implementation-plans/openapi-drift-prevention.md) (~3,800 tokens) - CI/CD workflow for API contract enforcement

**When to read archived docs**: Only if investigating historical decisions or debugging edge cases.

---

## 📖 Documentation Categories Summary

### By Use Case

**I'm starting a new session**:

1. Read [../CLAUDE.md](../CLAUDE.md)
2. Check [STATUS.md](STATUS.md)
3. Review [development-roadmap.md](development-roadmap.md) for priorities

**I'm implementing a new feature**:

1. Read [component-guide.md](component-guide.md) - Which component to use
2. Read [data-flows.md](data-flows.md) - How data flows
3. Read [api-quick-ref.md](api-quick-ref.md) - API endpoints
4. Check component `.stories.tsx` files - Usage examples

**I'm working on mobile iOS app**:

1. Read [mobile-ios-plan.md](mobile-ios-plan.md) - Overview & commands
2. See [mobile/xcodegen-guide.md](mobile/xcodegen-guide.md) - Adding/removing files
3. Reference [mobile/architecture.md](mobile/architecture.md) for patterns (if debugging)

**I'm making API changes that affect iOS**:

1. Update OpenAPI spec first (`docs/api/openapi.yaml`)
2. Run `npm run api:generate` to regenerate types (TypeScript + Swift)
3. Run `cd ios && xcodegen generate` if new Swift files created
4. Update iOS code if needed
5. Test both platforms before committing

**I'm debugging an issue**:

1. Check [STATUS.md](STATUS.md) - Known issues
2. Read [testing.md](testing.md) - Complete testing guide
3. Review [architecture.md](architecture.md) - System design

**I'm setting up the project**:

1. Read [project-setup.md](project-setup.md) - Installation
2. Check [media-configuration.md](media-configuration.md) - Media setup
3. Read [security.md](security.md) - Git hooks, linting

**I'm deploying to production**:

1. Run `npm run deploy --dry-run` - Validate before deploying
2. See [testing.md#deployment-validation](testing.md#deployment-validation) - Deploy commands
3. Full infrastructure setup in [aws-deployment-plan.md](aws-deployment-plan.md)

---

## 📊 Token Efficiency Guide

**Most efficient** (read these first):

- [component-guide.md](component-guide.md) - 660 tokens, high value
- [storybook.md](storybook.md) - 300 tokens, high value

**Moderate cost**:

- [data-flows.md](data-flows.md) - 1,170 tokens
- [api-quick-ref.md](api-quick-ref.md) - 1,000 tokens
- [testing.md](testing.md) - 1,500 tokens (comprehensive)

**Expensive** (read only when needed):

- [architecture.md](architecture.md) - 2,650 tokens
- [development-roadmap.md](development-roadmap.md) - 4,100 tokens
- [mobile-ios-plan.md](mobile-ios-plan.md) - 2,140 tokens

**Avoid unless necessary**:

- Archived docs - 10,000+ tokens each (historical only)

---

## 🔄 Maintenance

**Last Updated**: December 29, 2025

**When to update this index**:

- New documentation file added
- File archived or removed
- Major documentation restructuring
- Token estimates significantly change

**Updating token estimates**:

```bash
# Count words in a doc file
wc -w docs/filename.md

# Estimate tokens: words * 1.33 (approximate)
```

---

## ❓ Questions?

**Can't find what you need?**

1. Search this index for keywords
2. Check [STATUS.md](STATUS.md) for recent changes
3. Review [../CLAUDE.md](../CLAUDE.md) Section 4 (Refs)
4. Scan `**/*.test.ts` files for code examples

**File organization principle**:

- **Quick references** (<1,000 tokens) - Use frequently
- **Implementation guides** (1,000-3,000 tokens) - Read when implementing
- **Planning docs** (3,000+ tokens) - Read for strategic decisions
- **Archived docs** (10,000+ tokens) - Historical reference only
