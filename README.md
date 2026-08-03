# Book Vault

[![Main Validation](https://github.com/dlionikis/book_vault/actions/workflows/main.yml/badge.svg)](https://github.com/dlionikis/book_vault/actions/workflows/main.yml)
[![API Contract](https://github.com/dlionikis/book_vault/actions/workflows/api.yml/badge.svg)](https://github.com/dlionikis/book_vault/actions/workflows/api.yml)
[![iOS Tests](https://github.com/dlionikis/book_vault/actions/workflows/ios-tests.yml/badge.svg)](https://github.com/dlionikis/book_vault/actions/workflows/ios-tests.yml)
[![E2E](https://github.com/dlionikis/book_vault/actions/workflows/e2e.yml/badge.svg)](https://github.com/dlionikis/book_vault/actions/workflows/e2e.yml)
[![Storybook](https://github.com/dlionikis/book_vault/actions/workflows/storybook.yml/badge.svg)](https://github.com/dlionikis/book_vault/actions/workflows/storybook.yml)

A personal audiobook library — web app and native iOS app — for hosting, organizing, and streaming audiobooks from Audible, processed through [Libation](https://github.com/rmcrackan/Libation).

## Status

See **[docs/STATUS.md](docs/STATUS.md)** for current state, recent merges, and the roadmap. That file is the single source of truth — this README intentionally doesn't duplicate it.

## Overview

Book Vault organizes, searches, and streams a personal audiobook collection. It provides a rich browsing experience across authors, series, narrators, titles, and categories, with full-text search over book descriptions — on the web, on iOS, and in CarPlay.

## Features

### Playback

- **Web player**: play/pause, seek bar, skip back 15s / forward 30s, playback speed (0.75x–2x), volume with mute, time display, automatic position saving and resume
- **iOS player**: background audio, lock-screen and Control Center controls, audio-interruption resume, a persistent mini player, and chapter navigation
- **CarPlay**: browse your library, series, and downloaded books; Now Playing with chapter navigation
- **Chapter support**: chapters extracted from audio files and used for navigation

### Library

- **Progress tracking**: automatic position saving, three states (not started / in progress / finished), manual mark-finished and reset, "Continue Listening" carousel, visual progress indicators
- **Multi-faceted browsing**: by author, series (properly sequenced), narrator, title, and hierarchical category
- **Series view toggle**: switch between a Books and a Series view on Catalog and Library, with derived series covers and "N of M in your library" ownership
- **Full-text search**: across authors, narrators, titles, categories, and descriptions
- **User lists**: custom collections for organizing books
- **Offline downloads (iOS)**: background downloads for listening without a connection
- **Pagination**, **cover art**, and **dark mode** throughout

### Platform

- **Dual authentication**: NextAuth session for the web, JWT bearer tokens for mobile, with a shared token-refresh coordinator
- **S3 archive restore**: books in the S3 Intelligent-Tiering Archive tier show a badge and auto-initiate a restore on play; a poller and nightly sync track state; APNs push notifies when a restore completes
- **Admin dashboard**: AWS infrastructure health, cost/budget monitoring, ECS tasks, and a Restores tab
- **OpenAPI-first API**: the spec drives generated TypeScript and Swift types, enforced by contract tests

## Technology Stack

| Layer          | Technology                                                |
| -------------- | --------------------------------------------------------- |
| Framework      | Next.js 16 (App Router)                                   |
| Language       | TypeScript 5.7 (strict mode)                              |
| UI             | React 19, Tailwind CSS 3.4                                |
| Database       | PostgreSQL — Docker locally, Amazon RDS in production     |
| ORM            | Prisma 7                                                  |
| Authentication | NextAuth.js 4 (web sessions) + JWT bearer tokens (mobile) |
| Media storage  | Local filesystem in development, Amazon S3 in production  |
| iOS            | Swift 6 (strict concurrency) + SwiftUI                    |
| Runtime        | Node.js 24                                                |
| Hosting        | AWS — ALB (HTTPS) → ECS Fargate (arm64/Graviton), RDS, S3 |

### Development Tools

- **Testing**: Jest + React Testing Library (web), XCTest + XCUITest (iOS), Playwright (E2E), contract tests against the OpenAPI spec
- **Linting**: ESLint 9 with Next.js config; SwiftLint for iOS
- **Formatting**: Prettier 3
- **Components**: Storybook 10 with the a11y addon
- **Git hooks**: Husky + lint-staged
- **Project generation**: XcodeGen for the iOS project

## Getting Started

### Prerequisites

- Node.js 24+
- Docker (for PostgreSQL)
- A Libation audiobook directory (or use the bundled `test-data`)
- Xcode (latest stable, matching CI) and XcodeGen — for iOS work only

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/dlionikis/book_vault.git
   cd book_vault
   ```

2. **Install dependencies**

   ```bash
   npm install
   ```

3. **Start PostgreSQL**

   ```bash
   docker-compose up -d
   ```

   This starts PostgreSQL on port **5433** (avoiding conflicts with a local postgres on 5432). To stop it: `docker-compose down`.

4. **Configure environment**

   ```bash
   cp .env.example .env.local
   ```

   Edit `.env.local` — at minimum `DATABASE_URL`, `NEXTAUTH_SECRET`, and `MEDIA_DATA_PATH`.

   **Media path options:**

   ```bash
   MEDIA_DATA_PATH="test-data"                  # Small bundled test dataset (default)
   MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation" # Your full Libation library
   MEDIA_DATA_PATH="/path/to/audiobooks"        # Any custom directory
   ```

   See [docs/media-configuration.md](docs/media-configuration.md) for details.

5. **Set up the database**

   ```bash
   npm run db:migrate
   ```

   This runs migrations and generates the Prisma client.

6. **Import audiobooks**

   ```bash
   npm run import
   ```

   The import script reads from `LIBATION_PATH` if set, otherwise `MEDIA_DATA_PATH`.

7. **Seed a test user**

   ```bash
   npm run db:seed
   ```

   Creates `testuser` / `password123` — override with `TEST_USER_USERNAME` and `TEST_USER_PASSWORD`. Book Vault authenticates by **username**, not email.

   For any other user, use `npm run user:create local <username> [password]` (a password is generated if you omit it).

8. **Start the development server**

   ```bash
   npm run dev
   ```

   Then open [http://localhost:3000](http://localhost:3000).

## Commands

### Development

```bash
npm run dev            # Start dev server
npm run dev:https      # Start dev server over HTTPS (for iOS device testing)
npm run build          # Production build
npm run start          # Start production server
npm run storybook      # Component explorer on :6006
```

### Validation

```bash
npm run validate:full  # THE PR GATE — web + DB + iOS + E2E + drift + coverage
npm run validate:web   # Web only (no Xcode required)
npm run validate:ios   # iOS only
npm run validate       # format:check + lint + type-check + unit tests
npm test               # Unit tests only — NOT sufficient before a PR
```

**Run `npm run validate:full` before every PR.** It requires Docker and Xcode. See [docs/development-process.md](docs/development-process.md) for the complete test inventory, what CI enforces, and the hardening invariants that must not regress.

### Testing

```bash
npm test               # Unit tests
npm run test:coverage  # With coverage report
npm run test:integration  # Integration tests (needs Docker)
npm run test:contract  # API contract tests against the OpenAPI spec
npm run test:e2e       # Playwright web smoke tests
npm run ios:test       # iOS unit tests
npm run ios:test:ui    # iOS XCUITest UI tests
```

Full details in [docs/testing.md](docs/testing.md).

### Database

```bash
npm run db:migrate        # Run migrations + generate client
npm run db:migrate:deploy # Apply migrations to production
npm run db:generate       # Generate the Prisma client
npm run db:seed           # Seed the test user
npm run db:studio         # Prisma Studio GUI
npm run db:connect        # psql into local or production
```

**Reset and reimport:**

```bash
npx prisma migrate reset --force  # Drops data, reapplies migrations, reseeds the test user
npm run import
```

See [docs/database-migration-guide.md](docs/database-migration-guide.md) and [docs/database-reset-procedure.md](docs/database-reset-procedure.md).

### Users

```bash
npm run user:list <local|prod>                        # All users: admin flag, last login, last active
npm run user:create <local|prod> <username> [password]
npm run user:reset-password
npm run user:delete
npm run user:cleanup:check                            # Read-only: test accounts lingering in prod?
npm run user:cleanup <local|prod>                     # Remove them
```

`testuser` / `password123` is published in this public repo, so it is **local
only**. If a production test needs it, remove it afterward with
`npm run user:cleanup prod` — see [docs/development-process.md](docs/development-process.md) §10.
There is no soft-delete: deleting a user cascades to their progress, lists,
downloads, and device tokens.

### API

```bash
npm run api:validate       # Lint the OpenAPI spec
npm run api:generate       # Regenerate TypeScript + Swift types
npm run api:generate:ts    # TypeScript types only
npm run api:generate:swift # Swift models only
npm run api:docs           # Build docs/api/api-reference.html
npm run api:watch          # Auto-regenerate on spec changes
npm run api:check-drift    # Fail if generated types are stale
```

### iOS

```bash
npm run api:generate:swift  # Regenerate Swift models from the spec
cd ios && xcodegen generate # Rebuild the Xcode project (required for new files)
open ios/BookVault.xcodeproj
npm run ios:validate        # Lint + build + test
```

### Deployment

```bash
npm run deploy          # Full validation + deploy
npm run deploy:dry-run  # Validate only
npm run deploy:web      # Web only
```

Production import (the RDS instance sits in a private VPC — `import:prod` opens the firewall for your IP and closes it again on exit):

```bash
npm run import:prod

# Manual firewall control, if you need it
npm run db:firewall:open
npm run db:firewall:list
npm run db:firewall:close
```

See [docs/aws-deployment-reference.md](docs/aws-deployment-reference.md).

## Data Source

The application imports from a Libation export directory. Each folder is one book:

- Audio file (`.m4b` or `.mp3`)
- Metadata (`.metadata.json`)
- Cover image (`.jpg`)
- Cue sheet (`.cue`)

### Metadata Structure

Each book's `.metadata.json` provides:

| Field                | Meaning                                |
| -------------------- | -------------------------------------- |
| `title`              | Book title                             |
| `asin`               | Amazon Standard Identification Number  |
| `authors`            | Author objects with name and ASIN      |
| `narrators`          | Narrator objects with name and ASIN    |
| `series`             | Series info including sequence numbers |
| `publisher_summary`  | HTML-formatted description             |
| `category_ladders`   | Hierarchical category information      |
| `runtime_length_min` | Duration in minutes                    |

## API Documentation

Book Vault is OpenAPI-first: [docs/api/openapi.yaml](docs/api/openapi.yaml) is updated **before** endpoints are implemented, and it generates both the TypeScript types (`lib/api-types.ts`) and the iOS Swift models. Contract tests enforce that the implementation matches.

Build and view the reference:

```bash
npm run api:docs   # writes docs/api/api-reference.html
```

For a quick endpoint cheat sheet, see [docs/api-quick-ref.md](docs/api-quick-ref.md).

## iOS App

A native Swift 6 / SwiftUI app lives in [ios/BookVault/](ios/BookVault/), with streaming and offline playback, background downloads, push notifications, and CarPlay support.

```bash
npm run api:generate:swift
cd ios && xcodegen generate
open ios/BookVault.xcodeproj
```

New Swift files require `xcodegen generate` before building, even when `project.yml` already globs the directory.

See [docs/mobile/architecture.md](docs/mobile/architecture.md) for patterns and maintenance, [docs/mobile/ios-development-setup.md](docs/mobile/ios-development-setup.md) for setup, and [docs/mobile/xcodegen-guide.md](docs/mobile/xcodegen-guide.md) for adding files.

## Documentation

**Start with [docs/INDEX.md](docs/INDEX.md)** — the complete documentation map. Highlights:

### Essential

| File                                                       | Purpose                                         |
| ---------------------------------------------------------- | ----------------------------------------------- |
| [CLAUDE.md](CLAUDE.md)                                     | Project overview, commands, and coding patterns |
| [docs/STATUS.md](docs/STATUS.md)                           | Current state, recent PRs, roadmap              |
| [docs/development-process.md](docs/development-process.md) | The PR gate, all tests, hardening invariants    |
| [docs/architecture.md](docs/architecture.md)               | System design and data models                   |

### Reference

| File                                               | Purpose                        |
| -------------------------------------------------- | ------------------------------ |
| [docs/component-guide.md](docs/component-guide.md) | Which component to use         |
| [docs/data-flows.md](docs/data-flows.md)           | How data moves through the app |
| [docs/api-quick-ref.md](docs/api-quick-ref.md)     | API endpoint cheat sheet       |
| [docs/testing.md](docs/testing.md)                 | All testing commands           |
| [docs/storybook.md](docs/storybook.md)             | Component stories              |
| [docs/conventions.md](docs/conventions.md)         | Code conventions               |
| [docs/decisions.md](docs/decisions.md)             | Architecture decision records  |

### Operations & Security

| File                                                                 | Purpose                              |
| -------------------------------------------------------------------- | ------------------------------------ |
| [docs/aws-deployment-reference.md](docs/aws-deployment-reference.md) | Deploy commands and AWS architecture |
| [docs/database-migration-guide.md](docs/database-migration-guide.md) | Production DB migrations             |
| [docs/media-configuration.md](docs/media-configuration.md)           | Media paths and file locations       |
| [docs/API_SECURITY.md](docs/API_SECURITY.md)                         | Auth, endpoint protection, audit     |
| [docs/media-security.md](docs/media-security.md)                     | File access patterns and safeguards  |

Also: [CONTRIBUTING.md](CONTRIBUTING.md) and [CHANGELOG.md](CHANGELOG.md).

## Development Approach

This is an **AI-first development project**:

1. AI agents assist across all development phases
2. Context and goals are documented for AI reference — see [CLAUDE.md](CLAUDE.md)
3. Architecture decisions are made collaboratively and recorded in [docs/decisions.md](docs/decisions.md)
4. Code quality is enforced by gates, not convention — see [docs/development-process.md](docs/development-process.md)

**Project motto**: "Keep it simple, make it work, test thoroughly"

## License

Personal Use Only

## Contact

Demetri — personal project
