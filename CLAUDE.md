# CLAUDE.md - Project Memory Anchor

> **Purpose**: Quick onboarding reference for Claude Code sessions. Read this first to understand the project instantly.

**Last Updated**: December 29, 2025
**Status**: Production-ready with S3 streaming support
**Test Status**: 207 tests passing (23 OpenAPI contract tests + 184 unit tests)

---

## 1. WHAT: Project Overview

**Book Vault** is a personal audiobook library web application for managing and streaming audiobooks purchased from Audible, processed through [Libation](https://github.com/rmcrackan/Libation).

**Project Details**:

- **Started**: December 21, 2025
- **Owner**: Demetri
- **Development Approach**: AI-First Development (documentation-first for continuity across sessions)

### Tech Stack

| Layer         | Technology                   | Version   |
| ------------- | ---------------------------- | --------- |
| **Framework** | Next.js (App Router)         | 14.2+     |
| **Language**  | TypeScript                   | 5.7+      |
| **Database**  | PostgreSQL + Prisma ORM      | 15 / 5.22 |
| **Styling**   | Tailwind CSS                 | 3.4+      |
| **Auth**      | NextAuth.js (JWT)            | 4.24+     |
| **Testing**   | Jest + React Testing Library | 30+ / 16+ |
| **Container** | Docker (PostgreSQL)          | -         |

### System Dependencies (Optional)

| Dependency | Purpose                       | Installation          | Required? |
| ---------- | ----------------------------- | --------------------- | --------- |
| **FFmpeg** | Chapter extraction from audio | `brew install ffmpeg` | Optional  |

**Note**: FFmpeg provides `ffprobe` for extracting chapter metadata from audiobook files. Without it, the app will gracefully degrade and return empty chapters arrays instead of crashing.

### Core Architecture

```
┌─────────────┐
│   Next.js   │  App Router (SSR + API Routes)
│  Frontend   │
└──────┬──────┘
       │
┌──────▼──────┐
│  API Routes │  /api/* (RESTful JSON)
│             │
└──────┬──────┘
       │
┌──────▼──────┐
│   Prisma    │  ORM + Type-safe queries
│   Client    │
└──────┬──────┘
       │
┌──────▼──────┐
│ PostgreSQL  │  Metadata + user data
│  (Docker)   │  Port: 5433
└─────────────┘
```

**Media Storage**:

- **Development**: Local files at `/Volumes/BeeDrive/Libation/` or `test-data/`
- **Production**: AWS S3 with streaming support (images + audio with range requests)

---

## 2. HOW: Common Commands

### Development Workflow

```bash
# Start development server
npm run dev                    # Next.js on http://0.0.0.0:3000
npm run dev:https              # HTTPS mode (for mobile testing)

# Database
docker-compose up -d           # Start PostgreSQL (port 5433)
docker-compose down            # Stop PostgreSQL
npm run db:studio              # Open Prisma Studio GUI
npm run db:migrate             # Run migrations
npm run db:generate            # Regenerate Prisma Client

# Testing & Quality
npm test                       # Run all Jest tests
npm run test:watch             # Watch mode
npm run test:coverage          # Coverage report
npm run test:contract          # Run OpenAPI contract tests (auto-starts server)
npm run type-check             # TypeScript validation
npm run lint                   # ESLint check
npm run lint:fix               # Auto-fix linting issues
npm run format                 # Prettier format
npm run validate               # Run all checks (format + lint + typecheck + test)
npm run validate:full          # Full validation including API contract checks

# Data Management
npm run import                 # Import books from Libation directory
npm run db:seed                # Seed test user (test@example.com / password123)
npm run user:create            # Interactive admin user creation

# Storybook
npm run storybook              # Start Storybook dev server (port 6006)
npm run build-storybook        # Build static Storybook site

# OpenAPI Spec
npm run api:validate           # Validate OpenAPI specification
npm run api:generate:ts        # Generate TypeScript types from OpenAPI
npm run api:generate:swift     # Generate Swift models (requires iOS project)
npm run api:generate           # Generate all types (TypeScript + Swift)
npm run api:docs               # Generate API documentation (HTML)
npm run docs:generate          # Generate everything (types + docs)
npm run api:watch              # Watch for changes and auto-regenerate
npm run api:check-drift        # Check if generated types are stale

# Build & Deploy
npm run build                  # Production build
npm start                      # Start production server
```

### Git Workflow

```bash
# Standard flow
git checkout -b feature/your-feature
git add .
git commit -m "feat: description"  # Conventional commits
npm run validate                   # Pre-push validation
git push -u origin feature/your-feature

# Pre-commit hooks (Husky)
# - Prettier auto-format
# - ESLint check
# - Runs automatically on commit
```

---

## 3. STYLE: Coding Patterns

### Mandatory Conventions

#### TypeScript

- **Always use TypeScript** - No `.js` or `.jsx` files
- **Strict mode enabled** - No `any` types (use `unknown` if needed)
- **Centralized types** - Import shared types from `lib/types.ts`
- **Import patterns**:

  ```typescript
  // Prefer: Module imports with shared types
  import { Book, Author, SeriesInfo } from '@/lib/types';
  import { PrismaClient } from '@prisma/client';

  // Avoid: CommonJS (except server.js for HTTPS)
  const prisma = require('@prisma/client');
  ```

#### React Components

- **Server Components by default** - Add `'use client'` only when needed
- **Functional components only** - No class components
- **Props interfaces**:

  ```typescript
  interface MyComponentProps {
    title: string;
    bookId: string;
    onSelect?: (id: string) => void; // Optional callbacks
  }

  export default function MyComponent({ title, bookId }: MyComponentProps) {
    // Component body
  }
  ```

#### Database Access

- **⚠️ CRITICAL: DO NOT create `new PrismaClient()` directly**
- **ALWAYS import from centralized singleton**:

  ```typescript
  // ❌ WRONG - Creates connection leak
  const prisma = new PrismaClient();

  // ✅ CORRECT - Use singleton from lib/db.ts
  import { prisma } from '@/lib/db';
  ```

- **Current state**: All files (37+) now use singleton pattern ✅

#### API Routes

- **RESTful conventions**:

  ```typescript
  // app/api/resource/route.ts
  export async function GET(request: NextRequest) {
    // Fetch logic
    return NextResponse.json({ data });
  }

  export async function POST(request: NextRequest) {
    const body = await request.json();
    // Create logic
    return NextResponse.json({ created });
  }
  ```

- **Error handling**:
  ```typescript
  try {
    // Database operation
  } catch (error) {
    console.error('Error:', error);
    return NextResponse.json({ error: 'Descriptive message' }, { status: 500 });
  }
  ```

#### API Development (OpenAPI-First)

- **⚠️ CRITICAL: Spec-first development** - Always update OpenAPI spec BEFORE implementing endpoints
- **Auto-generated types** - Use types from `lib/api-types.ts` (regenerated from spec)
- **Pre-commit hooks** - Automatically regenerate types when `openapi.yaml` changes
- **CI enforcement** - PRs fail if generated types are stale or contract tests fail

**Workflow**:

1. Update `docs/api/openapi.yaml` with new endpoint
2. Run `npm run api:generate:ts` (or rely on pre-commit hook)
3. Implement endpoint using generated types
4. Run `npm run test:contract` to verify spec compliance
5. Commit spec + implementation together

**Example**:

```typescript
// ✅ CORRECT - Use generated types
import { paths } from '@/lib/api-types';

type BookResponse =
  paths['/api/books/{id}']['get']['responses']['200']['content']['application/json'];

export async function GET(request: NextRequest) {
  const book: BookResponse = await fetchBook();
  return NextResponse.json(book);
}

// ❌ WRONG - Manual types that drift from spec
interface BookResponse {
  id: string;
  title: string;
  // ... manually maintained
}
```

#### Styling

- **Tailwind utility-first**:
  ```tsx
  <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
    <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Title</h1>
  </div>
  ```
- **Dark mode**: Always include `dark:` variants
- **Responsive**: Mobile-first (`sm:`, `md:`, `lg:` breakpoints)

#### File Organization

```
app/
├── page.tsx                      # Home page (Server Component)
├── books/[id]/
│   ├── page.tsx                  # Book detail (Server)
│   └── play/page.tsx             # Playback page (Server)
├── api/
│   ├── books/route.ts            # GET /api/books
│   └── progress/route.ts         # POST /api/progress
components/
├── AudioPlayer.tsx               # 'use client' (interactive)
├── BookCard.tsx                  # Server Component
lib/
├── types.ts                      # Shared TypeScript types
├── db.ts                         # Prisma Client singleton
├── s3.ts                         # S3 streaming helpers
├── media.ts                      # Media URL helpers
└── auth.ts                       # NextAuth config
```

### Code Quality Standards

- **No console.log in production** - Use proper logging (console.error for errors)
- **Async/await over .then()** - Cleaner error handling
- **Descriptive variable names** - `bookId` not `id`, `authorName` not `name`
- **Comments only when necessary** - Code should be self-documenting
- **Test coverage** - Add tests for new features (Jest + RTL)

---

## 3.5 DESIGN PRINCIPLES

### Core Philosophy

1. **Data Integrity** - Never modify source Libation files (read-only access)
2. **API-First Design** - All features as RESTful JSON endpoints (backend is mobile-ready)
3. **AI-First Development** - Clear documentation for continuity across sessions
4. **Simplicity First** - Start with core functionality, add features incrementally
5. **Performance Matters** - Fast load times and responsive interactions
6. **Maintainability** - Clean, self-documenting code
7. **User-Centric Design** - Intuitive and enjoyable, not just functional

### Performance Targets

- **Page Load**: < 2 seconds initial load
- **Search**: < 500ms for results
- **Audio Start**: < 1 second to playback
- **Navigation**: Instant feel for UI interactions

### Success Metrics

- Can find any book in < 10 seconds
- Can start listening in < 3 clicks
- Series books properly ordered
- Search returns relevant results
- Audio plays without interruption

---

## 4. REFS: Documentation Links

### Internal Documentation

**📍 START HERE**: Read [docs/INDEX.md](docs/INDEX.md) for complete documentation map

**Most Used** (read these for common tasks):

- [docs/component-guide.md](docs/component-guide.md) - Which component to use (decision tree)
- [docs/data-flows.md](docs/data-flows.md) - How data flows through the app
- [docs/data-validation-layers.md](docs/data-validation-layers.md) - How OpenAPI, TypeScript, Zod, Prisma, and Swift types work together
- [docs/api-quick-ref.md](docs/api-quick-ref.md) - API endpoints reference (copy-paste)
- [docs/STATUS.md](docs/STATUS.md) - Current status, recent work, next priorities

**Full Documentation List**: See [docs/INDEX.md](docs/INDEX.md) for organized index with token estimates

### External References

- **Next.js 14**: https://nextjs.org/docs
- **Prisma ORM**: https://www.prisma.io/docs
- **NextAuth.js**: https://next-auth.js.org/
- **Tailwind CSS**: https://tailwindcss.com/docs
- **Libation (source data)**: https://github.com/rmcrackan/Libation

### Libation Metadata Structure

Complete JSON structure reference:

```json
{
  "asin": "string",
  "title": "string",
  "authors": [{"name": "string", "asin": "string"}],
  "narrators": [{"name": "string", "asin": "string"}],
  "series": [
    {
      "title": "string",
      "sequence": "string",
      "asin": "string",
      "url": "string"
    }
  ],
  "publisher_summary": "string (HTML content)",
  "category_ladders": [
    {
      "root": "string",
      "ladder": [{"id": "string", "name": "string"}]
    }
  ],
  "runtime_length_min": number,
  "release_date": "string",
  "publisher": "string"
}
```

**Key Constraints**:

- `series.sequence` can be numeric ("1") or descriptive ("1.5", "Prequel")
- `publisher_summary` contains HTML and must be sanitized
- `category_ladders` creates hierarchical taxonomy (multiple paths per book)
- Each book folder contains: `.metadata.json`, `.mp3`, `.jpg`, `.cue` (chapters), `Icon?` (macOS metadata - ignore)

---

## 5. Critical Knowledge

### Database Schema (Prisma)

**Core Models**:

```prisma
Book {
  id, asin, title, description, runtimeMinutes
  authors[] → BookAuthor → Author
  narrators[] → BookNarrator → Narrator
  series[] → BookSeries → Series
  categories[] → BookCategory → Category
  chapters[] → Chapter
  progress[] → UserProgress
}

User {
  id, email, passwordHash
  progress[] → UserProgress
  lists[] → UserList
}
```

**Key Patterns**:

- Many-to-many: Books ↔ Authors (via `BookAuthor` join table)
- Cascade deletes: Deleting a book removes all related joins
- UUIDs everywhere: `@id @default(uuid())`
- Snake_case in DB, camelCase in code: `@map("created_at")`

### OpenAPI Contract & CI/CD

**Spec Location**: `docs/api/openapi.yaml` (single source of truth)

**Generated Artifacts**:

- `lib/api-types.ts` - TypeScript types (auto-generated, do not edit)
- `docs/api/api-reference.html` - HTML documentation

**CI Enforcement** (`.github/workflows/api.yml`):

1. **Spec validation** - Fails if `openapi.yaml` is invalid
2. **Drift detection** - Fails if `lib/api-types.ts` is stale (not regenerated)
3. **Contract tests** - Fails if API responses don't match spec (23 tests)

**Pre-commit Hooks**:

- Auto-regenerates `lib/api-types.ts` when `openapi.yaml` changes
- Validates spec before allowing commit

**Local Testing**:

```bash
# Quick contract test (one command)
npm run test:contract

# Full validation (pre-push check)
npm run validate:full
```

**Important**: Never manually edit `lib/api-types.ts` - it will be overwritten on next generation.

### Environment Variables

**Required** (`.env` or `.env.local`):

```bash
# Database
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/book_vault?schema=public"

# Auth
NEXTAUTH_SECRET="your-secret-key-here"
NEXTAUTH_URL="http://localhost:3000"

# Media paths
MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"  # or "test-data" for dev
LIBATION_PATH="/Volumes/BeeDrive/Libation"     # Import script

# Test user (seeded by db:seed)
TEST_USER_EMAIL="test@example.com"
TEST_USER_PASSWORD="password123"

# AWS S3 (production media storage - optional)
# Leave empty for development (uses local filesystem)
AWS_S3_BUCKET="book-vault-media"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="..."
AWS_SECRET_ACCESS_KEY="..."

# Data Strategy Decision (TBD)
# Current: Local filesystem for development
# Future: Evaluate S3 sync vs. direct access based on cost/accessibility tradeoff
```

### AWS Deployment Readiness

✅ **COMPLETED**:

1. **Prisma Client Singleton** - Centralized at `lib/db.ts`
   - Prevents connection pool exhaustion in serverless environments
   - All 37+ files now use singleton pattern

2. **S3 Streaming Support** - Implemented in `lib/s3.ts`
   - Images: Stream from S3 with caching headers
   - Audio: Stream from S3 with range request support for seeking
   - Automatic fallback to filesystem in development

3. **Environment Variables** - Standardized to AWS conventions
   - Uses `AWS_S3_BUCKET`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

⏳ **REMAINING** (Optional optimizations):

1. **Prisma Connection Pooling** - Configure for RDS
   - Add connection limits to DATABASE_URL
   - Tune for serverless environments

2. **CloudFront CDN** - Add CDN layer for static assets
   - Reduces S3 costs and latency
   - Not required for initial deployment

### Data Flow Example: Audio Playback

```typescript
// 1. User clicks "Play" on book detail page
app/books/[id]/page.tsx
  → Redirects to /books/[id]/play

// 2. Playback page loads
app/books/[id]/play/page.tsx (Server Component)
  → Fetches book data from Prisma
  → Passes audioUrl, coverUrl to <PlaybackClient>

// 3. Client component manages state
components/PlaybackClient.tsx ('use client')
  → Fetches user progress: GET /api/progress?bookId=...
  → Renders <AudioPlayer> with initialPosition

// 4. Audio player streams file
components/AudioPlayer.tsx ('use client')
  → <audio src={audioUrl}> → /api/audio/[...path]
  → Auto-saves progress: POST /api/progress every 10s
  → Updates Media Session API (lock screen controls)
```

---

## 6. Quick Start Checklist

When starting a new session:

- [ ] Read this file (CLAUDE.md)
- [ ] Read [docs/INDEX.md](docs/INDEX.md) for documentation navigation
- [ ] Check [docs/STATUS.md](docs/STATUS.md) for latest completed work
- [ ] Review [docs/development-roadmap.md](docs/development-roadmap.md) for priorities
- [ ] Start Docker: `docker-compose up -d`
- [ ] Start dev server: `npm run dev`
- [ ] Run tests if making changes: `npm test`
- [ ] (Optional) Install FFmpeg for chapter extraction: `brew install ffmpeg`

**Default credentials**:

- Email: `test@example.com`
- Password: `password123`

---

## 7. AI-Assisted Development (⭐ READ THIS FIRST)

**IMPORTANT**: Before exploring the codebase for any task, follow this workflow to save 50-80% of tokens:

### Efficient Documentation Navigation (CRITICAL)

**ALWAYS start here** (prevents wasting 10,000+ tokens on exploration):

1. **Read [docs/INDEX.md](docs/INDEX.md) FIRST** (~1,020 tokens)
   - Complete documentation map with token estimates
   - Tells you exactly which file to read for your task
   - Organized by use case ("I'm implementing a feature", "I'm debugging", etc.)

2. **Scan TL;DR sections** (~50 tokens each)
   - All large docs (architecture.md, mobile-ios-plan.md, etc.) have TL;DR at top
   - Decide if you need the full file before reading it
   - Look for "Jump to" links to skip to relevant sections

3. **Read overview docs, not detailed docs**
   - Use `architecture.md` (overview) not `architecture/*.md` (details)
   - Use `development-roadmap.md` (current focus) not archived plans
   - Detailed docs are created only when needed

### Recommended Workflow for Feature Implementation

1. **Read** [docs/INDEX.md](docs/INDEX.md) - Find which docs you need (~1,020 tokens)
2. **Read** [docs/component-guide.md](docs/component-guide.md) - Which component to use (~660 tokens)
3. **Read** [docs/data-flows.md](docs/data-flows.md) - How data flows (~1,170 tokens)
4. **Read** [docs/api-quick-ref.md](docs/api-quick-ref.md) - API request/response shapes (~1,000 tokens)
5. **Check** `ComponentName.stories.tsx` - Component usage examples in Storybook
6. **Implement** using documented patterns
7. **Update** stories for new functionality

**Total tokens**: ~3,850 (vs. ~15,000 without this workflow)

### Why This Workflow Works

- **Component guide** → No guessing which component to use
- **Data flows** → Understand full path without exploring files
- **API reference** → Exact endpoints without scanning routes
- **Stories** → See prop shapes without reading component files

**Token savings**: 90-95% reduction (5,000-8,000 tokens → 300-500 tokens per feature)

### What NOT to Do

- ❌ Scan entire codebase to understand component relationships
- ❌ Read multiple component files to find prop types
- ❌ Explore API routes to understand request/response shapes
- ❌ Grep through code to find usage examples

### Quick Reference Files

| File                                                             | Purpose                  | When to Use                                |
| ---------------------------------------------------------------- | ------------------------ | ------------------------------------------ |
| [docs/component-guide.md](docs/component-guide.md)               | Component selection      | "Which component should I use?"            |
| [docs/data-flows.md](docs/data-flows.md)                         | Data movement patterns   | "How does data flow here?"                 |
| [docs/data-validation-layers.md](docs/data-validation-layers.md) | Type safety architecture | "How do OpenAPI/Zod/Prisma work together?" |
| [docs/api-quick-ref.md](docs/api-quick-ref.md)                   | API endpoints            | "What's the request/response?"             |
| [docs/storybook.md](docs/storybook.md)                           | Storybook usage          | "How do I use Storybook?"                  |
| Component `.stories.tsx`                                         | Component examples       | "How do I use this component?"             |

---

## 8. Deployment & Mobile Plans

### AWS Deployment (Next Priority)

**Infrastructure** (ready to deploy):

- **Hosting**: ECS or Lambda
- **Database**: RDS PostgreSQL
- **Storage**: S3 (audio files + images) + CloudFront (CDN)
- **Auth**: JWT tokens (already mobile-compatible)

**Backend is mobile-ready**: See "AWS Deployment Readiness" section above.

### iOS Mobile App (Complete)

**Technology**: Native Swift + SwiftUI

**Status**: ✅ All 8 phases complete (December 2025)

**Completed Features**: Auth, Playback, Background Audio, Progress Sync, Chapters, Search, Offline Downloads, Offline Mode

**Deferred**: User Lists (post-launch, requires backend API development)

**Common Commands**:

```bash
# Generate Swift models from OpenAPI spec
npm run api:generate:swift

# Regenerate Xcode project (after adding/removing files)
cd ios && xcodegen generate

# Open Xcode project
open ios/BookVault.xcodeproj
```

**Documentation**: See [docs/mobile-ios-plan.md](docs/mobile-ios-plan.md) for:

- Development workflow & commands
- Maintenance notes
- Links to detailed guides

---

## 9. Common Gotchas

1. **Port conflict**: PostgreSQL runs on `5433` (not default `5432`)
2. **Media paths**: Development uses local files, production will use S3
3. **Server vs Client**: Most pages are Server Components - only use `'use client'` for interactivity
4. **Dark mode**: Always test both themes (`dark:` Tailwind classes)
   - Test theme persistence across navigation
   - Verify system preference detection
   - Check contrast for readability
   - Test theme toggle functionality
5. **Chapter extraction**: Lazy-loaded on first playback (not during import)
6. **Authentication**: Protected routes use middleware (`middleware.ts`)
7. **File formats**: Each book has `.metadata.json`, `.mp3`, `.jpg`, `.cue` (chapters), `Icon?` (ignore)
8. **Data integrity**: NEVER modify files in Libation directory - read-only access only

### Common Pitfalls to Avoid

- **Don't hard-code paths** - Use environment variables
- **Don't commit secrets** - Use .env files (gitignored)
- **Don't skip migrations** - Always use Prisma migration system
- **Don't modify Libation files** - Read-only constraint (see Design Principles)
- **Don't forget database indexes** - Performance matters

### Debugging Tips

**Import Issues**:

- Check file permissions on Libation directory
- Validate JSON format of metadata files
- Check for special characters in filenames

**Database Issues**:

- Verify connection string in .env
- Check migration status: `npx prisma migrate status`
- Review indexes in Prisma schema

**Authentication Issues**:

- Verify NEXTAUTH_SECRET is set in .env
- Check session configuration in [lib/auth.ts](lib/auth.ts)
- Review cookie settings (secure flag, domain)

---

## Questions or Issues?

1. Check `docs/` folder for detailed guides
2. Search existing tests in `**/*.test.ts` for examples
3. Check [docs/STATUS.md](docs/STATUS.md) for known issues
4. Review [docs/development-roadmap.md](docs/development-roadmap.md) for priorities

**Project Motto**: "Keep it simple, make it work, test thoroughly"
