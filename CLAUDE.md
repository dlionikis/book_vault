# CLAUDE.md - Project Memory Anchor

> **Purpose**: Quick onboarding reference for Claude Code sessions. Read this first to understand the project instantly.

**Last Updated**: December 23, 2025
**Status**: Production-ready locally, preparing for AWS deployment
**Test Status**: 171 tests passing

---

## 1. WHAT: Project Overview

**Book Vault** is a personal audiobook library web application for managing and streaming audiobooks purchased from Audible, processed through [Libation](https://github.com/rmcrackan/Libation).

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
- **Production** (planned): AWS S3 + CloudFront CDN

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
npm run type-check             # TypeScript validation
npm run lint                   # ESLint check
npm run lint:fix               # Auto-fix linting issues
npm run format                 # Prettier format
npm run validate               # Run all checks (format + lint + typecheck + test)

# Data Management
npm run import                 # Import books from Libation directory
npm run db:seed                # Seed test user (test@example.com / password123)
npm run user:create            # Interactive admin user creation

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
- **Import patterns**:

  ```typescript
  // Prefer: Module imports
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
- **ALWAYS import from centralized module** (needs implementation):

  ```typescript
  // ❌ WRONG - Creates connection leak
  const prisma = new PrismaClient();

  // ✅ CORRECT - Will use singleton (after refactor)
  import { prisma } from '@/lib/db';
  ```

- **Current state**: Multiple instances exist (43+) - **needs refactoring before AWS**

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

## 4. REFS: Documentation Links

### Internal Documentation

**Primary Docs** (`docs/` folder):

- [Architecture & Tech Stack](docs/architecture.md) - Detailed system design
- [Project Status](docs/STATUS.md) - Current features, recent PRs, todo list
- [Development Roadmap](docs/development-roadmap.md) - Future plans, prioritization
- [Testing Guide](docs/testing.md) - Test patterns and examples
- [Security](docs/security.md) - Auth, API security, best practices
- [Media Configuration](docs/media-configuration.md) - S3 vs local file setup

**AI Agent Context** (`.ai/` folder):

- [Project Context](/.ai/PROJECT_CONTEXT.md) - Problem statement, data structure
- [Development Goals](/.ai/DEVELOPMENT_GOALS.md) - Phase-by-phase roadmap
- [AI Instructions](/.ai/AI_INSTRUCTIONS.md) - Guidelines for AI collaboration

### External References

- **Next.js 14**: https://nextjs.org/docs
- **Prisma ORM**: https://www.prisma.io/docs
- **NextAuth.js**: https://next-auth.js.org/
- **Tailwind CSS**: https://tailwindcss.com/docs
- **Libation (source data)**: https://github.com/rmcrackan/Libation

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

# AWS (production - not yet implemented)
AWS_S3_BUCKET="book-vault-media"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="..."
AWS_SECRET_ACCESS_KEY="..."
```

### Current Limitations (Pre-AWS Deployment)

⚠️ **MUST FIX BEFORE AWS**:

1. **PrismaClient instances** - 43+ separate instances (connection leak)
   - **Action**: Create `lib/db.ts` with singleton pattern
2. **S3 streaming not implemented** - Only local filesystem works
   - **Action**: Implement S3 SDK in `app/api/images` and `app/api/audio`
3. **Environment variable inconsistency** - `S3_BUCKET_NAME` vs `AWS_S3_BUCKET`
   - **Action**: Standardize to `AWS_S3_BUCKET`

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
- [ ] Check [docs/STATUS.md](docs/STATUS.md) for latest completed work
- [ ] Review [docs/development-roadmap.md](docs/development-roadmap.md) for priorities
- [ ] Start Docker: `docker-compose up -d`
- [ ] Start dev server: `npm run dev`
- [ ] Run tests if making changes: `npm test`

**Default credentials**:

- Email: `test@example.com`
- Password: `password123`

---

## 7. Deployment Notes (Future)

**AWS Infrastructure** (planned):

- **Hosting**: ECS or Lambda
- **Database**: RDS PostgreSQL
- **Storage**: S3 (audio files) + CloudFront (CDN)
- **Auth**: JWT tokens for mobile compatibility

**Pre-deployment checklist**: See "Current Limitations" section above.

---

## 8. Common Gotchas

1. **Port conflict**: PostgreSQL runs on `5433` (not default `5432`)
2. **Media paths**: Development uses local files, production will use S3
3. **Server vs Client**: Most pages are Server Components - only use `'use client'` for interactivity
4. **Dark mode**: Always test both themes (`dark:` Tailwind classes)
5. **Chapter extraction**: Lazy-loaded on first playback (not during import)
6. **Authentication**: Protected routes use middleware (`middleware.ts`)

---

## Questions or Issues?

1. Check `docs/` folder for detailed guides
2. Review `.ai/` folder for project context
3. Search existing tests in `**/*.test.ts` for examples
4. Check `docs/STATUS.md` for known issues

**Project Motto**: "Keep it simple, make it work, test thoroughly"
