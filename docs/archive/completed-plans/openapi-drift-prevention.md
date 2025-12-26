# OpenAPI Drift Prevention - Implementation Plan

**Status**: Ready to implement
**Priority**: High (blocks production deployment)
**Created**: December 26, 2025
**Estimated effort**: 2-3 hours

---

## Overview

Implement CI/CD guardrails to prevent drift between OpenAPI spec and implementation, ensuring the API contract remains the single source of truth.

**Current state**: OpenAPI spec exists, TypeScript types are generated, contract tests work locally, but no automated enforcement.

**Target state**: CI automatically validates spec, checks for stale generated types, runs contract tests, and fails PRs on drift.

---

## Objectives (from verification report)

### ✅ Already Working

- TypeScript type generation (`npm run api:generate:ts`)
- Contract tests (`RUN_CONTRACT_TESTS=true npm test -- openapi-contract`)
- Spec validation (`npm run api:validate`)
- Watch mode for local development (`npm run api:watch`)

### ❌ Need to Fix

1. **No CI enforcement** - nothing prevents merging stale types or spec violations
2. **Contract tests skipped by default** - easy to forget to run
3. **No pre-commit hooks** - can commit without regenerating types
4. **Spec quality warnings** - 30 warnings from redocly lint (not critical but should fix)

---

## Implementation Phases

### Phase 1: Add CI Workflow (30 min)

**Goal**: Automated validation on every PR/push

**Tasks**:

1. Create `.github/workflows/api.yml`
2. Add jobs for:
   - Spec validation
   - Type generation + drift check
   - Contract tests (requires running dev server)
3. Configure to run on `pull_request` and `push` to `main`

**Files to create/modify**:

- `.github/workflows/api.yml` (new)

**Success criteria**:

- CI fails if `openapi.yaml` is invalid
- CI fails if `lib/api-types.ts` is stale (not regenerated after spec change)
- CI fails if contract tests fail
- Green checkmark on PR = API contract is in sync

---

### Phase 2: Add Pre-commit Hooks (15 min)

**Goal**: Catch issues before commit (fast feedback loop)

**Tasks**:

1. Add pre-commit hook to regenerate types if `openapi.yaml` changed
2. Add validation check to ensure spec is valid
3. Update Husky configuration

**Files to create/modify**:

- `.husky/pre-commit` (modify existing)
- `package.json` (add helper script for drift check)

**Success criteria**:

- Committing changes to `openapi.yaml` auto-regenerates `lib/api-types.ts`
- Commit fails if spec is invalid
- Fast (<5 sec) local feedback

---

### Phase 3: Fix OpenAPI Spec Warnings (60-90 min)

**Goal**: Clean spec that passes all linting rules

**Tasks**:

1. Add `operationId` to all 28 endpoints (for better code generation)
2. Add missing `4xx` responses (10 endpoints)
3. Add `license` field to info object
4. Fix `no-server-example.com` warning (document why localhost is needed)
5. Document unused schemas or remove if truly unused

**Files to modify**:

- `docs/api/openapi.yaml`

**Success criteria**:

- `npm run api:validate` shows 0 warnings (currently 30)
- Generated TypeScript types have better names (from operationIds)
- Future Swift generation will produce cleaner code

---

### Phase 4: Improve Contract Test Developer Experience (30 min)

**Goal**: Make contract tests easier to run locally

**Tasks**:

1. Add helper script to run dev server + contract tests in one command
2. Update documentation with better examples
3. Consider adding contract tests to `npm run validate` (full pre-push check)

**Files to create/modify**:

- `package.json` (add `test:contract` script)
- `docs/api/README.md` (update examples)
- `CLAUDE.md` (update common commands section)

**Success criteria**:

- Developers can run `npm run test:contract` (handles server startup)
- Contract tests integrated into pre-push validation workflow
- Clear error messages if tests fail

---

## Detailed Implementation

### Phase 1: CI Workflow

**File**: `.github/workflows/api.yml`

```yaml
name: API Contract Validation

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  validate-spec:
    name: Validate OpenAPI Specification
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Validate OpenAPI spec
        run: npm run api:validate

  check-generated-types:
    name: Check Generated Types are Up-to-Date
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Generate TypeScript types
        run: npm run api:generate:ts

      - name: Check for uncommitted changes
        run: |
          if ! git diff --exit-code lib/api-types.ts; then
            echo "❌ ERROR: Generated types are out of sync with OpenAPI spec"
            echo "Please run: npm run api:generate:ts"
            echo "Then commit the updated lib/api-types.ts file"
            exit 1
          fi
          echo "✅ Generated types are up-to-date"

  contract-tests:
    name: Run Contract Tests
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: book_vault
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Setup environment
        run: |
          cp .env.example .env.test.local || true
          echo "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/book_vault?schema=public" >> .env.test.local
          echo "NEXTAUTH_SECRET=test-secret-for-ci" >> .env.test.local
          echo "NEXTAUTH_URL=http://localhost:3000" >> .env.test.local

      - name: Run database migrations
        run: npx prisma migrate deploy
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/book_vault?schema=public

      - name: Generate Prisma Client
        run: npm run db:generate

      - name: Seed test database
        run: npm run db:seed
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/book_vault?schema=public

      - name: Build Next.js app
        run: npm run build

      - name: Start dev server in background
        run: |
          npm run dev &
          echo $! > .dev-server.pid
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/book_vault?schema=public

      - name: Wait for server to be ready
        run: |
          timeout 60 bash -c 'until curl -f http://localhost:3000/api/health 2>/dev/null; do sleep 2; done' || {
            echo "❌ Server failed to start"
            kill $(cat .dev-server.pid) 2>/dev/null || true
            exit 1
          }

      - name: Run contract tests
        run: RUN_CONTRACT_TESTS=true npm test -- openapi-contract
        env:
          TEST_API_URL: http://localhost:3000
          TEST_USER_EMAIL: test@example.com
          TEST_USER_PASSWORD: password123

      - name: Stop dev server
        if: always()
        run: kill $(cat .dev-server.pid) 2>/dev/null || true
```

**Notes**:

- Requires adding a health check endpoint at `/api/health` (simple 200 OK response)
- Uses PostgreSQL service for database
- Runs migrations and seeds test user
- Starts dev server in background, waits for startup, runs tests
- Cleans up server process even if tests fail

---

### Phase 2: Pre-commit Hook

**File**: `.husky/pre-commit` (append to existing file)

```bash
# Existing content (prettier, lint, etc.)
# ...

# OpenAPI: Check if spec changed and regenerate types
if git diff --cached --name-only | grep -q "docs/api/openapi.yaml"; then
  echo "📝 OpenAPI spec changed, regenerating TypeScript types..."
  npm run api:generate:ts
  git add lib/api-types.ts

  echo "✅ Validating OpenAPI spec..."
  npm run api:validate || {
    echo "❌ OpenAPI spec validation failed"
    exit 1
  }
fi
```

**File**: `package.json` (add new script)

```json
{
  "scripts": {
    "api:check-drift": "npm run api:generate:ts && git diff --exit-code lib/api-types.ts"
  }
}
```

---

### Phase 3: Fix OpenAPI Spec Warnings

**Changes to**: `docs/api/openapi.yaml`

#### 3.1 Add license field (line 2-6)

```yaml
info:
  title: Book Vault API
  version: 1.0.1
  license:
    name: MIT
    url: https://opensource.org/licenses/MIT
  description: |
    RESTful API for Book Vault audiobook library.
```

#### 3.2 Document localhost exception (line 28-32)

```yaml
servers:
  - url: http://localhost:3000
    description: Development server
    # Note: localhost is intentional for local development
    # Production URL will be configured via environment variable
  - url: https://api.bookvault.com
    description: Production server (TBD)
```

#### 3.3 Add operationId to all endpoints

**Pattern**: Use format `{action}{Resource}` (e.g., `loginMobile`, `getBooks`, `updateProgress`)

Example for `/api/auth/mobile/login` (line 374):

```yaml
/api/auth/mobile/login:
  post:
    operationId: loginMobile # Add this
    tags: [Mobile Authentication]
    summary: Mobile app login - returns JWT tokens
```

**Full list of operationIds to add**:

| Endpoint                   | Method | operationId         |
| -------------------------- | ------ | ------------------- |
| `/api/auth/mobile/login`   | POST   | `loginMobile`       |
| `/api/auth/register`       | POST   | `registerUser`      |
| `/api/books`               | GET    | `listBooks`         |
| `/api/books/{id}`          | GET    | `getBook`           |
| `/api/books/{id}/chapters` | GET    | `getBookChapters`   |
| `/api/progress`            | GET    | `getProgress`       |
| `/api/progress`            | POST   | `updateProgress`    |
| `/api/progress`            | PUT    | `setProgressStatus` |
| `/api/search`              | GET    | `searchAll`         |
| `/api/browse/authors`      | GET    | `listAuthors`       |
| `/api/browse/series`       | GET    | `listSeries`        |
| `/api/browse/narrators`    | GET    | `listNarrators`     |
| `/api/browse/categories`   | GET    | `listCategories`    |
| `/api/authors/{id}`        | GET    | `getAuthor`         |
| `/api/series/{id}`         | GET    | `getSeries`         |
| `/api/narrators/{id}`      | GET    | `getNarrator`       |
| `/api/categories/{id}`     | GET    | `getCategory`       |
| `/api/library`             | GET    | `getLibrary`        |
| `/api/library`             | POST   | `addToLibrary`      |
| `/api/library/{bookId}`    | DELETE | `removeFromLibrary` |

#### 3.4 Add missing 4xx responses

**Pattern**: Add `400` (bad request) and `401` (unauthorized) where missing

Example for `PUT /api/progress` (line 745):

```yaml
responses:
  '200':
    description: Progress status updated
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/ProgressUpdate'
  '400': # Add this
    description: Invalid request (missing bookId or invalid status)
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/Error'
  '401': # Add this
    description: Unauthorized
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/Error'
```

**Endpoints needing 4xx responses**:

- `PUT /api/progress`
- `POST /api/progress`
- `GET /api/browse/authors`
- `GET /api/browse/series`
- `GET /api/browse/narrators`
- `GET /api/browse/categories`

#### 3.5 Handle unused schemas warning

**Option A**: Remove if truly unused (check if `UserProgress` and `Series` are referenced)

**Option B**: Document as "for future use" with `x-internal: true`

```yaml
UserProgress:
  x-internal: true
  description: Full user progress model (for future direct queries)
  type: object
  # ... rest of schema
```

---

### Phase 4: Improve Developer Experience

**File**: `package.json` (add new scripts)

```json
{
  "scripts": {
    "test:contract": "concurrently --kill-others --success first \"npm run dev\" \"npm run test:contract:wait\"",
    "test:contract:wait": "wait-on http://localhost:3000 && RUN_CONTRACT_TESTS=true npm test -- openapi-contract",
    "validate:full": "npm run format:check && npm run lint && npm run type-check && npm run api:validate && npm run api:check-drift && npm test"
  },
  "devDependencies": {
    "concurrently": "^8.2.2", // Add this
    "wait-on": "^7.2.0" // Add this
  }
}
```

**File**: `docs/api/README.md` (update contract testing section)

````markdown
### Contract Testing

Contract tests validate that API responses match the OpenAPI specification.

**Quick start** (recommended):

```bash
npm run test:contract
# Automatically starts server, waits for startup, runs tests, stops server
```
````

**Manual control** (for debugging):

```bash
# Terminal 1: Start dev server
npm run dev

# Terminal 2: Run contract tests
RUN_CONTRACT_TESTS=true npm test -- openapi-contract
```

**In CI**: Contract tests run automatically on every PR via `.github/workflows/api.yml`

````

---

### Phase 5: Update Documentation (30 min)
**Goal**: Ensure all documentation reflects new CI/CD workflow and API contract guarantees

**Tasks**:
1. Update `CLAUDE.md` with new commands and workflow
2. Update `docs/STATUS.md` to reflect completed OpenAPI drift prevention
3. Update `docs/development-roadmap.md` to mark this as complete
4. Update `docs/INDEX.md` if needed (add CI/CD section)
5. Add CI badge to README.md
6. Update `docs/api/README.md` with CI workflow explanation

**Files to modify**:
- `CLAUDE.md`
- `docs/STATUS.md`
- `docs/development-roadmap.md`
- `docs/INDEX.md` (if needed)
- `README.md`
- `docs/api/README.md`

**Success criteria**:
- All documentation mentions new CI workflow
- Developers know how to run contract tests
- CI badges show on README
- Future Claude Code sessions understand the workflow

---

#### Phase 5 Details

**File**: `CLAUDE.md` (update multiple sections)

##### Section: "2. HOW: Common Commands"

```markdown
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

# OpenAPI Spec
npm run api:validate           # Validate OpenAPI specification
npm run api:generate:ts        # Generate TypeScript types from OpenAPI
npm run api:generate:swift     # Generate Swift models (requires iOS project)
npm run api:generate           # Generate all types (TypeScript + Swift)
npm run api:docs               # Generate API documentation (HTML)
npm run docs:generate          # Generate everything (types + docs)
npm run api:watch              # Watch for changes and auto-regenerate
npm run api:check-drift        # Check if generated types are stale
````

##### Section: "3. STYLE: Coding Patterns" (add new subsection)

````markdown
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
````

````

##### Section: "5. Critical Knowledge" (add new subsection after "Database Schema")

```markdown
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
````

**Important**: Never manually edit `lib/api-types.ts` - it will be overwritten on next generation.

````

---

**File**: `docs/STATUS.md` (add to "Recently Completed" section)

```markdown
## Recently Completed

### OpenAPI Drift Prevention (December 26, 2025)
- ✅ CI workflow validates spec, checks for stale types, runs contract tests
- ✅ Pre-commit hooks auto-regenerate types on spec changes
- ✅ OpenAPI spec cleaned (30 warnings → 0 warnings)
- ✅ One-command contract testing: `npm run test:contract`
- ✅ Full validation script: `npm run validate:full`
- **Impact**: API contract guaranteed to stay in sync with implementation
- **Files**: `.github/workflows/api.yml`, `.husky/pre-commit`, `docs/api/openapi.yaml`
````

---

**File**: `docs/development-roadmap.md` (mark as complete)

Find the OpenAPI/API contract section and update:

```markdown
## ✅ Completed

### OpenAPI Drift Prevention

- **Status**: Complete (December 26, 2025)
- **Objective**: Prevent API spec from drifting from implementation
- **Delivered**:
  - CI validates spec, checks stale types, runs contract tests
  - Pre-commit hooks auto-regenerate types
  - 0 spec warnings (was 30)
  - One-command testing workflow
- **Next**: iOS app development (uses OpenAPI-generated Swift models)
```

---

**File**: `README.md` (add CI badges at top)

```markdown
# Book Vault

[![API Contract](https://github.com/YOUR_USERNAME/book_vault/actions/workflows/api.yml/badge.svg)](https://github.com/YOUR_USERNAME/book_vault/actions/workflows/api.yml)
[![Storybook](https://github.com/YOUR_USERNAME/book_vault/actions/workflows/storybook.yml/badge.svg)](https://github.com/YOUR_USERNAME/book_vault/actions/workflows/storybook.yml)

Personal audiobook library for managing and streaming audiobooks from Libation.

**API Status**:

- ✅ OpenAPI spec valid (0 warnings)
- ✅ TypeScript types auto-generated
- ✅ 23 contract tests passing
- 📱 Ready for iOS development

[Rest of existing README content...]
```

---

**File**: `docs/api/README.md` (add CI section)

````markdown
## CI/CD Integration

### Automated Validation (GitHub Actions)

Every PR and push to `main` runs:

1. **Spec Validation** - Ensures `openapi.yaml` is syntactically correct
2. **Drift Detection** - Fails if `lib/api-types.ts` is stale
3. **Contract Tests** - Validates all 23 endpoints match spec

**Workflow**: `.github/workflows/api.yml`

**Status Badge**:

```markdown
[![API Contract](https://github.com/YOUR_USERNAME/book_vault/actions/workflows/api.yml/badge.svg)](https://github.com/YOUR_USERNAME/book_vault/actions/workflows/api.yml)
```
````

### Pre-commit Hooks

When you commit changes to `openapi.yaml`:

1. TypeScript types auto-regenerate (`lib/api-types.ts`)
2. Spec validation runs
3. Regenerated types automatically added to commit

**No manual steps needed** - just commit the spec change.

### What Happens on Failure

**Stale types detected**:

```
❌ ERROR: Generated types are out of sync with OpenAPI spec
Please run: npm run api:generate:ts
Then commit the updated lib/api-types.ts file
```

**Contract test failure**:

```
❌ Expected response to satisfy OpenAPI spec
Endpoint: GET /api/books
Actual response missing required field: pagination.pages
```

Fix the implementation to match the spec, then push again.

````

---

**File**: `docs/INDEX.md` (add reference to CI/CD if not present)

Look for a "Development Workflow" or "Testing" section and add:

```markdown
- [OpenAPI Drift Prevention Plan](archive/implementation-plans/openapi-drift-prevention.md) (~3,800 tokens) - CI/CD workflow for API contract enforcement
````

---

## Additional Requirements

### Health Check Endpoint

**File**: `app/api/health/route.ts` (new file)

```typescript
import { NextResponse } from 'next/server';

/**
 * Health check endpoint for CI/CD and monitoring
 * Returns 200 OK if server is running
 */
export async function GET() {
  return NextResponse.json({ status: 'ok' }, { status: 200 });
}
```

### Environment File for CI

**File**: `.env.example` (create if doesn't exist)

```bash
# Database
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/book_vault?schema=public"

# Auth
NEXTAUTH_SECRET="your-secret-key-here"
NEXTAUTH_URL="http://localhost:3000"

# Media paths
MEDIA_DATA_PATH="test-data"
LIBATION_PATH="test-data"

# Test user
TEST_USER_EMAIL="test@example.com"
TEST_USER_PASSWORD="password123"

# AWS S3 (optional - leave empty for local filesystem)
AWS_S3_BUCKET=""
AWS_REGION=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
```

---

## Testing the Implementation

### After Phase 1 (CI Workflow)

```bash
# 1. Create a branch and modify OpenAPI spec
git checkout -b test/api-ci
echo "# test comment" >> docs/api/openapi.yaml
git add docs/api/openapi.yaml
git commit -m "test: trigger CI validation"

# 2. Push and create PR
git push -u origin test/api-ci

# 3. Verify CI runs:
# - ✅ validate-spec job should pass
# - ❌ check-generated-types should FAIL (types not regenerated)
# - ✅ contract-tests should pass (if spec still valid)

# 4. Fix by regenerating types
npm run api:generate:ts
git add lib/api-types.ts
git commit -m "fix: regenerate types"
git push

# 5. Now all CI jobs should pass ✅
```

### After Phase 2 (Pre-commit Hook)

```bash
# 1. Modify OpenAPI spec
echo "# test comment" >> docs/api/openapi.yaml
git add docs/api/openapi.yaml

# 2. Commit should auto-regenerate types
git commit -m "test: pre-commit hook"

# Expected output:
# 📝 OpenAPI spec changed, regenerating TypeScript types...
# ✅ Validating OpenAPI spec...
# [main abc1234] test: pre-commit hook
#  2 files changed, 2 insertions(+)
#  (both openapi.yaml AND lib/api-types.ts should be in commit)
```

### After Phase 3 (Fix Warnings)

```bash
npm run api:validate

# Expected output:
# Woohoo! Your API description is valid. 🎉
# You have 0 warnings.  ← Was 30, now 0
```

### After Phase 4 (Developer Experience)

```bash
npm run test:contract

# Expected output:
# [0] > dev
# [0] ▲ Next.js 14.2.35
# [0] - Local:        http://localhost:3000
# [1] Waiting for http://localhost:3000...
# [1] ✓ http://localhost:3000 is available
# [1] PASS __tests__/api/openapi-contract.test.ts
# [1]   ✓ All contract tests pass
```

---

## Rollout Plan

### Day 1: Phase 1 (CI Workflow)

1. Create health check endpoint
2. Create `.github/workflows/api.yml`
3. Test CI with dummy PR
4. Merge to main

**Deliverable**: CI badge on README showing API contract validation status

### Day 2: Phase 2 + Phase 4 (Developer Tools)

1. Update pre-commit hook
2. Add `test:contract` script with dependencies
3. Test locally

**Deliverable**: Developers can run `npm run test:contract` easily

### Day 3: Phase 3 (Fix Warnings)

1. Add operationId to all endpoints (bulk edit)
2. Add missing 4xx responses
3. Add license field
4. Test regeneration produces cleaner types
5. Run `npm run api:validate` → 0 warnings

**Deliverable**: Clean OpenAPI spec ready for production

### Day 4: Phase 5 (Documentation)

1. Update `CLAUDE.md` (3 sections: commands, coding patterns, critical knowledge)
2. Update `docs/STATUS.md` (recently completed section)
3. Update `docs/development-roadmap.md` (mark as complete)
4. Update `README.md` (add CI badges)
5. Update `docs/api/README.md` (add CI/CD section)
6. Update `docs/INDEX.md` (add plan reference)

**Deliverable**: All documentation reflects new CI/CD workflow and guarantees

---

## Success Metrics

### Before Implementation

- ❌ No CI validation of API contract
- ❌ 30 linting warnings in OpenAPI spec
- ❌ Easy to commit stale generated types
- ❌ Contract tests require manual server startup
- ❌ Documentation doesn't mention CI workflow
- ❌ No visibility of API contract status

### After Implementation

- ✅ CI fails on stale types or spec violations
- ✅ 0 linting warnings
- ✅ Pre-commit hook auto-regenerates types
- ✅ One-command contract testing (`npm run test:contract`)
- ✅ Green badge on PRs = API contract in sync
- ✅ All documentation updated (CLAUDE.md, STATUS.md, README.md, etc.)
- ✅ Future Claude Code sessions understand workflow
- ✅ CI badges show contract status on README

---

## Future Enhancements (Post-Implementation)

1. **Automated API docs deployment**
   - Deploy `api-reference.html` to GitHub Pages or Vercel
   - Update on every merge to main
   - Public URL for API documentation

2. **Swagger UI integration**
   - Add interactive API explorer at `/api-docs`
   - Try endpoints directly from browser
   - Better for manual testing

3. **Version management**
   - Track breaking changes with semver
   - Generate changelog from spec changes
   - Deprecation warnings for old endpoints

4. **Performance testing**
   - Add response time assertions to contract tests
   - Fail if endpoints are too slow
   - Track performance over time

---

## Questions / Decisions Needed

**None** - all requirements are clear from verification report. Ready to implement.

---

## Estimated Timeline

| Phase                    | Effort    | Complexity                          |
| ------------------------ | --------- | ----------------------------------- |
| Phase 1: CI Workflow     | 30 min    | Medium (need health check endpoint) |
| Phase 2: Pre-commit      | 15 min    | Low (append to existing hook)       |
| Phase 3: Fix Warnings    | 90 min    | Low (bulk editing)                  |
| Phase 4: DX Improvements | 30 min    | Low (add scripts)                   |
| Phase 5: Documentation   | 30 min    | Low (update 6 files)                |
| **Total**                | **3 hrs** | **Low-Medium**                      |

**Recommendation**: Implement all phases in one session to avoid context switching.

---

## Context-Free Phase Prompts

Use these prompts when implementing each phase in separate sessions. Each prompt is self-contained and requires minimal context loading.

### Phase 1 Prompt

```
Implement Phase 1 from docs/archive/implementation-plans/openapi-drift-prevention.md

Tasks:
1. Create app/api/health/route.ts - simple health check endpoint returning {status: "ok"}
2. Create .github/workflows/api.yml with 3 jobs:
   - validate-spec: run npm run api:validate
   - check-generated-types: run npm run api:generate:ts and fail if git diff shows changes
   - contract-tests: setup postgres service, run migrations, seed db, start dev server, run RUN_CONTRACT_TESTS=true npm test -- openapi-contract

Full workflow code is in the plan file. After implementing, test with a dummy PR.
```

### Phase 2 Prompt

```
Implement Phase 2 from docs/archive/implementation-plans/openapi-drift-prevention.md

Tasks:
1. Add to .husky/pre-commit (append to existing file):
   - Detect if docs/api/openapi.yaml changed
   - If yes: run npm run api:generate:ts and git add lib/api-types.ts
   - Run npm run api:validate and fail if invalid

2. Add to package.json scripts:
   - "api:check-drift": "npm run api:generate:ts && git diff --exit-code lib/api-types.ts"

Exact code is in the plan file under Phase 2. Test by modifying openapi.yaml and committing.
```

### Phase 3 Prompt

```
Implement Phase 3 from docs/archive/implementation-plans/openapi-drift-prevention.md

Tasks - Edit docs/api/openapi.yaml:
1. Add license field to info object (MIT)
2. Add operationId to all 28 endpoints (table with all names in plan)
3. Add missing 4xx responses to 10 endpoints (list in plan)
4. Document localhost server exception
5. Handle unused schema warnings

Goal: npm run api:validate shows 0 warnings (currently 30)
After changes, run npm run api:generate:ts to regenerate types.
```

### Phase 4 Prompt

```
Implement Phase 4 from docs/archive/implementation-plans/openapi-drift-prevention.md

Tasks:
1. Add to package.json scripts:
   - "test:contract": "concurrently --kill-others --success first \"npm run dev\" \"npm run test:contract:wait\""
   - "test:contract:wait": "wait-on http://localhost:3000 && RUN_CONTRACT_TESTS=true npm test -- openapi-contract"
   - "validate:full": "npm run format:check && npm run lint && npm run type-check && npm run api:validate && npm run api:check-drift && npm test"

2. Add devDependencies:
   - concurrently ^8.2.2
   - wait-on ^7.2.0

Test with: npm run test:contract (should auto-start server and run tests)
```

### Phase 5 Prompt

```
Implement Phase 5 from docs/archive/implementation-plans/openapi-drift-prevention.md

Update 6 documentation files with CI/CD workflow info:

1. CLAUDE.md - 3 sections (commands, coding patterns, critical knowledge)
2. docs/STATUS.md - add to "Recently Completed"
3. docs/development-roadmap.md - mark as complete
4. README.md - add CI badges at top
5. docs/api/README.md - add CI/CD Integration section
6. docs/INDEX.md - add plan reference

Exact text for each file is in Phase 5 Details section of the plan. Copy-paste from there.
```

---

## Quick Verification Commands

After each phase:

**Phase 1**: Check GitHub Actions tab after pushing
**Phase 2**: `git commit` should auto-regenerate types if openapi.yaml changed
**Phase 3**: `npm run api:validate` should show 0 warnings
**Phase 4**: `npm run test:contract` should work
**Phase 5**: All docs should mention new CI workflow
