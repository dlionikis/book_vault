# CLAUDE.md - Project Memory Anchor

> **Purpose**: Quick onboarding reference for Claude Code sessions. Read this first.

**Last Updated**: January 4, 2026
**Status**: Production-ready at https://bookvault.lionikis.com

---

## 1. Project Overview

**Book Vault** is a personal audiobook library web + iOS application for managing and streaming audiobooks from [Libation](https://github.com/rmcrackan/Libation).

### Tech Stack

| Layer         | Technology                   |
| ------------- | ---------------------------- |
| **Framework** | Next.js 14 (App Router)      |
| **Language**  | TypeScript (strict mode)     |
| **Database**  | PostgreSQL + Prisma ORM      |
| **Styling**   | Tailwind CSS                 |
| **Auth**      | NextAuth.js (JWT)            |
| **Testing**   | Jest + React Testing Library |
| **iOS**       | Swift + SwiftUI              |

### Architecture

```
Browser/iOS → API Routes (/api/*) → Prisma → PostgreSQL
                                         ↓
                              S3 (media) or Local files
```

---

## 2. Essential Commands

```bash
# Development
npm run dev                    # Start server (http://localhost:3000)
docker-compose up -d           # Start PostgreSQL (port 5433)

# Validation (run before commits)
npm run validate               # format + lint + typecheck + test
npm run validate:full          # + API contract tests + drift checks

# iOS
npm run api:generate:swift     # Regenerate Swift models
cd ios && xcodegen generate    # Rebuild Xcode project

# Deployment
npm run deploy                 # Full validation + deploy
npm run deploy:dry-run         # Validate only
```

**Before every PR**: run `npm run validate:full` (the complete web gate — unit + integration + contract + E2E + drift + coverage), and `npm run ios:validate` if `ios/**` changed. `npm test` alone is unit-only and is **not** sufficient. See **[docs/development-process.md](docs/development-process.md)** for the full test inventory, the pre-commit hook, what CI enforces, and the **hardening invariants that must not regress**.

**Full command reference**: See [docs/testing.md](docs/testing.md)

---

## 3. Coding Patterns

### Critical Rules

1. **Prisma Singleton** - Never create `new PrismaClient()`. Always:

   ```typescript
   import { prisma } from '@/lib/db';
   ```

2. **OpenAPI-First** - Update `docs/api/openapi.yaml` BEFORE implementing endpoints:

   ```bash
   npm run api:generate:ts    # Regenerate TypeScript types
   npm run test:contract      # Verify compliance
   ```

3. **Server Components by Default** - Only add `'use client'` when needed (hooks, interactivity)

4. **Read-Only Libation** - Never modify source audiobook files

5. **No AI attribution in git** - Never mention Claude or AI assistance in commit messages, PR titles, or PR bodies. No `Co-Authored-By: Claude` trailers, no "Generated with Claude Code" footers.

6. **Run the full gate + protect the invariants** - `validate:full` before every PR (not just `npm test`). Never regress the hardening invariants (auth via `requireUser`/`requireAdmin`, no inline `getServerSession`; images route authed; chapter POST admin-only; iOS via `APIClientProtocol` not `URLSession.shared`; `isValidUuid` for id params; test partitioning; coverage ratchet). Full list + manual checks in [docs/development-process.md](docs/development-process.md) §5.

### File Organization

```
app/api/          # RESTful JSON endpoints
components/       # React components
lib/
├── db.ts        # Prisma singleton (use this!)
├── types.ts     # Shared TypeScript types
├── api-types.ts # Auto-generated from OpenAPI (don't edit)
└── auth.ts      # NextAuth config
```

---

## 4. Documentation

**Start here**: [docs/INDEX.md](docs/INDEX.md) - Complete documentation map

### Quick References (read these for most tasks)

| File                                               | Purpose                                |
| -------------------------------------------------- | -------------------------------------- |
| [docs/STATUS.md](docs/STATUS.md)                   | Current state, recent PRs, what's next |
| [docs/component-guide.md](docs/component-guide.md) | Which component to use                 |
| [docs/data-flows.md](docs/data-flows.md)           | How data moves through the app         |
| [docs/api-quick-ref.md](docs/api-quick-ref.md)     | API endpoints cheat sheet              |
| [docs/testing.md](docs/testing.md)                 | All testing commands                   |

### By Task

- **Implementing features**: component-guide.md → data-flows.md → api-quick-ref.md
- **iOS development**: [docs/mobile/architecture.md](docs/mobile/architecture.md)
- **Deploying**: [docs/aws-deployment-reference.md](docs/aws-deployment-reference.md)
- **Database changes**: [docs/database-migration-guide.md](docs/database-migration-guide.md)

---

## 5. Database Schema

```prisma
Book {
  id, asin, title, description, runtimeMinutes
  authors[] → BookAuthor → Author
  narrators[] → BookNarrator → Narrator
  series[] → BookSeries → Series
  chapters[] → Chapter
}

User {
  id, username, passwordHash
  progress[] → UserProgress
  lists[] → UserList
}
```

**Patterns**: Many-to-many via join tables, UUIDs everywhere, snake_case in DB via `@map()`

---

## 6. Environment Variables

```bash
# Required
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/book_vault"
NEXTAUTH_SECRET="your-secret"
NEXTAUTH_URL="http://localhost:3000"
MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"  # or "test-data"
LIBATION_PATH="/Volumes/BeeDrive/Libation"    # source for import (overrides MEDIA_DATA_PATH)

# AWS (production)
AWS_S3_BUCKET="book-vault-media"
AWS_REGION="us-east-1"
```

**Default dev credentials**: testuser / password123

---

## 7. Common Gotchas

1. **Port 5433** - PostgreSQL uses 5433, not 5432
2. **Media paths** - Dev uses local files, prod uses S3
3. **Chapter extraction** - Lazy-loaded on first playback (requires FFmpeg)
4. **Dark mode** - Always include `dark:` Tailwind variants

---

## 8. Quick Start Checklist

- [ ] Read this file
- [ ] Check [docs/STATUS.md](docs/STATUS.md) for current state
- [ ] Start Docker: `docker-compose up -d`
- [ ] Start dev: `npm run dev`
- [ ] Run tests if making changes: `npm test`

---

## Questions?

1. Check [docs/INDEX.md](docs/INDEX.md) for documentation map
2. Search tests in `**/*.test.ts` for examples
3. Check [docs/STATUS.md](docs/STATUS.md) for known issues

**Project Motto**: "Keep it simple, make it work, test thoroughly"
