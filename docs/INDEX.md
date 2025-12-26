# Documentation Index

> **Quick navigation for all Book Vault documentation**

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

| File                                     | Purpose                                   | When to Use                     | Tokens |
| ---------------------------------------- | ----------------------------------------- | ------------------------------- | ------ |
| [component-guide.md](component-guide.md) | Component selection decision tree         | "Which component should I use?" | ~660   |
| [data-flows.md](data-flows.md)           | How data moves through the app            | "How does data flow here?"      | ~1,170 |
| [api-quick-ref.md](api-quick-ref.md)     | API endpoint reference (copy-paste)       | "What's the request/response?"  | ~1,000 |
| [storybook.md](storybook.md)             | Using Storybook for component development | "How do I use Storybook?"       | ~300   |

**💡 Token-saving tip**: Read these BEFORE exploring the codebase. Saves 5,000-8,000 tokens per feature.

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

## 📱 Mobile Development

| File                                     | Purpose                                    | Tokens |
| ---------------------------------------- | ------------------------------------------ | ------ |
| [api-mobile.md](api-mobile.md)           | **Mobile API quick reference** (condensed) | ~370   |
| [mobile-ios-plan.md](mobile-ios-plan.md) | Native iOS app 8-phase implementation plan | ~2,140 |

**Note**: For detailed Swift code examples, see `archive/api-mobile-detailed.md` (2,925 lines, ~10,600 tokens).

---

## 🧪 Testing & Quality

| File                     | Purpose                                      | Tokens |
| ------------------------ | -------------------------------------------- | ------ |
| [testing.md](testing.md) | Test patterns, Jest examples, best practices | ~750   |

---

## 📦 Setup & Deployment

| File                                 | Purpose                                        | Tokens |
| ------------------------------------ | ---------------------------------------------- | ------ |
| [project-setup.md](project-setup.md) | Initial project setup, installation, first run | ~1,170 |

---

## 📚 Archived Documentation

**Historical planning documents** (completed work, rarely needed):

Located in `archive/` folder:

- `archive/completed-plans/implement-backend-support-for-mobile.md` (71K, 9,512 words)
- `archive/completed-plans/storybook-plan.md` (30K, 3,913 words)
- `archive/completed-plans/fix-api-tests.md` (10K, 1,311 words)
- `archive/completed-plans/library-concurrency-tests.md` (6K, 819 words)

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

**I'm working on mobile integration**:

1. Read [api-mobile.md](api-mobile.md) - Quick reference
2. Read [mobile-ios-plan.md](mobile-ios-plan.md) - Implementation roadmap
3. Check [API_SECURITY.md](API_SECURITY.md) - Auth patterns

**I'm debugging an issue**:

1. Check [STATUS.md](STATUS.md) - Known issues
2. Read [testing.md](testing.md) - Test patterns
3. Review [architecture.md](architecture.md) - System design

**I'm setting up the project**:

1. Read [project-setup.md](project-setup.md) - Installation
2. Check [media-configuration.md](media-configuration.md) - Media setup
3. Read [security.md](security.md) - Git hooks, linting

---

## 📊 Token Efficiency Guide

**Most efficient** (read these first):

- [component-guide.md](component-guide.md) - 660 tokens, high value
- [storybook.md](storybook.md) - 300 tokens, high value
- [api-mobile.md](api-mobile.md) - 370 tokens, high value (condensed)

**Moderate cost**:

- [data-flows.md](data-flows.md) - 1,170 tokens
- [api-quick-ref.md](api-quick-ref.md) - 1,000 tokens
- [testing.md](testing.md) - 750 tokens

**Expensive** (read only when needed):

- [architecture.md](architecture.md) - 2,650 tokens
- [development-roadmap.md](development-roadmap.md) - 4,100 tokens
- [mobile-ios-plan.md](mobile-ios-plan.md) - 2,140 tokens

**Avoid unless necessary**:

- Archived docs - 10,000+ tokens each (historical only)

---

## 🔄 Maintenance

**Last Updated**: December 25, 2025

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
