---
description: Primary agent for Book Vault — a Next.js 14 + TypeScript audiobook library app with PostgreSQL, Prisma, NextAuth, AWS S3, and a Swift/SwiftUI iOS client. Use for all feature development, bug fixes, API changes, and iOS work.
mode: primary
---

# Book Vault Agent

You are working on **Book Vault**, a personal audiobook library web and iOS application. The app is live in production at https://bookvault.lionikis.com.

## Tech Stack

| Layer     | Technology                                                     |
| --------- | -------------------------------------------------------------- |
| Framework | Next.js 14 (App Router, React Server Components)               |
| Language  | TypeScript (strict mode)                                       |
| Database  | PostgreSQL 15 (port **5433**) + Prisma ORM                     |
| Auth      | NextAuth.js (web sessions) + custom JWT via `jose` (mobile)    |
| Styling   | Tailwind CSS with `dark:` variants throughout                  |
| Testing   | Jest + React Testing Library + `jest-openapi` (contract tests) |
| iOS       | Swift + SwiftUI (XcodeGen, SwiftLint)                          |
| Hosting   | AWS ECS Fargate + RDS PostgreSQL + S3 (514 GB, 691 books)      |

## Critical Rules

1. **Prisma singleton** — Never write `new PrismaClient()`. Always:

   ```typescript
   import { prisma } from '@/lib/db';
   ```

2. **OpenAPI-first** — Update `docs/api/openapi.yaml` BEFORE implementing new or changed endpoints, then regenerate types:

   ```bash
   npm run api:generate:ts    # regenerate lib/api-types.ts
   npm run test:contract      # verify compliance
   ```

   Never manually edit `lib/api-types.ts` — it is auto-generated.

3. **Server components by default** — Only add `'use client'` when the component needs hooks or browser interactivity.

4. **Read-only media** — Never modify source audiobook files under `MEDIA_DATA_PATH`.

5. **Dark mode always** — Every Tailwind color class needs a `dark:` variant.

6. **`@/` imports** — Use the path alias for all internal imports, never relative `../` paths.

## File Organization

```
app/api/          RESTful JSON endpoints (one directory per resource)
components/       React components (flat, PascalCase .tsx)
lib/
├── db.ts        Prisma singleton — import from here
├── types.ts     Shared TypeScript types
├── api-types.ts Auto-generated from OpenAPI (never edit directly)
├── api-schemas.ts Zod validation schemas
├── book-transformer.ts  transformBook() + BOOK_INCLUDE constant
└── auth.ts      NextAuth config + getAuthUserFromRequest()
prisma/schema.prisma  Database schema
docs/api/openapi.yaml  OpenAPI spec (source of truth for API shape)
ios/BookVault/    Swift/SwiftUI source
ios/BookVault/Generated/Models/  Auto-generated Swift models (never edit)
__tests__/        Jest test suite (mirrors app/ and lib/ structure)
```

## Key Patterns

### API Routes

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { withLogging } from '@/lib/logger';

export const GET = withLogging(async (request: NextRequest) => {
  // Dual auth: web session + mobile JWT
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    // ... prisma query, transform, return
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
});
```

### Book Queries

Always use `BOOK_INCLUDE` from `lib/book-transformer.ts` and pass results through `transformBook()` to normalize the Prisma shape into the API response format.

### Pagination

Use `buildPagination()` from `lib/api-utils.ts`. Standard query params: `page` (default 1), `limit` (default 20).

### Import Order

1. External packages (React, Next.js, third-party)
2. Internal utilities and types (`@/lib/...`)
3. Components (`@/components/...`)
4. Styles

## Database Schema (abbreviated)

```
Book { id, asin, title, description, runtimeMinutes, authors[], narrators[], series[], chapters[] }
User { id, username, passwordHash, progress[], lists[] }
Chapter { id, bookId, title, startTime, endTime }
UserProgress { userId, bookId, position, completed }
```

Many-to-many via join tables (`BookAuthor`, `BookNarrator`, `BookSeries`). UUIDs everywhere. DB columns are `snake_case` via `@map()`.

## Environment Variables

```bash
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/book_vault"
NEXTAUTH_SECRET="your-secret"
NEXTAUTH_URL="http://localhost:3000"
MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"  # or "test-data" in dev
# Production only
AWS_S3_BUCKET="book-vault-media"
AWS_REGION="us-east-1"
```

Default dev credentials: `testuser` / `password123`

## Common Gotchas

- **Port 5433** — PostgreSQL runs on 5433, not 5432
- **Chapter extraction** — Lazy-loaded on first playback; requires FFmpeg
- **Media paths** — Dev uses local files; production uses S3 presigned URLs
- **iOS Swift models** — Auto-generated from OpenAPI via `npm run api:generate:swift`; edit the spec, not the generated files

## Essential Commands

```bash
npm run dev                    # Start dev server (http://localhost:3000)
docker-compose up -d           # Start PostgreSQL

npm run validate               # format + lint + typecheck + test (run before commits)
npm run validate:full          # + API contract tests + drift checks
npm test                       # Jest tests only
npm run test:contract          # OpenAPI contract tests

npm run api:generate:ts        # Regenerate lib/api-types.ts from openapi.yaml
npm run api:generate:swift     # Regenerate iOS Swift models

cd ios && xcodegen generate    # Rebuild Xcode project

npm run deploy                 # Full validation + deploy to AWS
```

## Adding a New Feature — Checklist

1. Update `docs/api/openapi.yaml` for any new/changed endpoints
2. Run `npm run api:generate:ts` to update `lib/api-types.ts`
3. Add Zod schema to `lib/api-schemas.ts`
4. Implement API route in `app/api/<feature>/route.ts`
5. Create component in `components/FeatureName.tsx` (+ `.stories.tsx`)
6. Add page in `app/<feature>/page.tsx`
7. Write tests in `__tests__/` mirroring the source path
8. Run `npm run validate` before committing
9. If iOS needs the feature: update Swift models with `npm run api:generate:swift`
