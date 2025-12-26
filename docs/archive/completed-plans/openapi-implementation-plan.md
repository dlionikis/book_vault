# OpenAPI Implementation Plan

**Status**: Ready to start
**Priority**: CRITICAL (blocks iOS development)
**Last Updated**: December 25, 2025

> **TL;DR**: 7-phase plan to create OpenAPI spec from existing APIs, setup code generation, consolidate documentation, and establish API contract as single source of truth.
>
> **Includes**: Documentation consolidation to reduce ~4,000 tokens of duplication and 70% less maintenance

---

## Why OpenAPI First?

**Critical Benefits**:

1. **iOS Development Prerequisite**: Swift models generated from OpenAPI
2. **Type Safety**: TypeScript types generated for backend
3. **Documentation**: Always up-to-date API docs
4. **Contract Testing**: Validate responses match spec
5. **API Consistency**: Prevent drift between platforms

**Blocks**: Cannot start iOS Phase 1 without this

---

## Phase 0: Setup Tooling (~15 min)

**Objective**: Install and configure OpenAPI tools

**Files to Create**: None (package.json changes only)

**Dependencies to Install**:

```bash
npm install --save-dev \
  openapi-typescript@6.7.3 \
  @redocly/cli@1.25.14 \
  nodemon@3.0.2 \
  yaml@2.8.2
```

**Note**: Using `@redocly/cli` instead of deprecated `swagger-cli`. Redocly provides better linting, built-in documentation generation, and active maintenance.

**Add to package.json scripts**:

```json
{
  "scripts": {
    "api:validate": "redocly lint docs/api/openapi.yaml",
    "api:docs": "redocly build-docs docs/api/openapi.yaml -o docs/api/api-reference.html",
    "api:generate": "npm run api:generate:ts && npm run api:generate:swift",
    "api:generate:ts": "openapi-typescript docs/api/openapi.yaml -o lib/api-types.ts",
    "api:generate:swift": "echo 'Skipping Swift generation (no iOS project yet)'",
    "api:watch": "nodemon --watch docs/api/openapi.yaml --exec 'npm run api:generate'",
    "docs:generate": "npm run api:generate && npm run api:docs"
  }
}
```

**Homebrew for Swift generation** (run once on your Mac):

```bash
# Only needed when iOS project exists
brew install openapi-generator
```

**Acceptance Criteria**:

- [ ] Dependencies installed
- [ ] Scripts added to package.json
- [ ] `npm run api:validate` runs (will fail until spec exists)
- [ ] Homebrew has openapi-generator installed

**Stop Point**: Commit changes to package.json

---

## Phase 1: Create Base OpenAPI Spec (~30 min)

**Objective**: Create openapi.yaml with basic structure and authentication

**Files to Create**:

- `docs/api/openapi.yaml` (new)
- `docs/api/README.md` (new)

**Reference Files to Read** (minimize tokens):

- [docs/api-quick-ref.md](api-quick-ref.md) - Existing API endpoints (~1,000 tokens)
- [lib/types.ts](../lib/types.ts) - TypeScript types for models

**Base OpenAPI Structure**:

```yaml
openapi: 3.0.0
info:
  title: Book Vault API
  version: 1.0.0
  description: |
    RESTful API for Book Vault audiobook library.

    ## Authentication
    All endpoints (except /api/auth/login) require JWT authentication.
    Include token in Authorization header: `Bearer {token}`

    ## Base URL
    - Development: http://localhost:3000
    - Production: TBD (AWS deployment)

servers:
  - url: http://localhost:3000
    description: Development server
  - url: https://api.bookvault.com
    description: Production server (TBD)

tags:
  - name: Authentication
    description: Login and token management
  - name: Books
    description: Book catalog and details
  - name: Chapters
    description: Chapter navigation
  - name: Progress
    description: User playback progress
  - name: Search
    description: Search across books, authors, narrators
  - name: Browse
    description: Browse by author, series, narrator, category
  - name: Library
    description: User's personal library

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    # Common schemas
    Error:
      type: object
      required: [error]
      properties:
        error:
          type: string
          description: Error message
          example: 'Book not found'

    Pagination:
      type: object
      required: [page, limit, total, totalPages]
      properties:
        page:
          type: integer
          minimum: 1
          example: 1
        limit:
          type: integer
          minimum: 1
          maximum: 100
          example: 20
        total:
          type: integer
          minimum: 0
          example: 150
        totalPages:
          type: integer
          minimum: 0
          example: 8

    # Core models (from lib/types.ts)
    Book:
      type: object
      required: [id, asin, title, runtimeMinutes, coverUrl, audioUrl, authors]
      properties:
        id:
          type: string
          format: uuid
          example: '550e8400-e29b-41d4-a716-446655440000'
        asin:
          type: string
          example: 'B002V5D1CG'
        title:
          type: string
          example: 'The Name of the Wind'
        description:
          type: string
          nullable: true
          example: "Told in Kvothe's own voice, this is the tale of the magically gifted young man..."
        runtimeMinutes:
          type: integer
          minimum: 0
          example: 1068
        releaseDate:
          type: string
          format: date
          nullable: true
          example: '2008-04-01'
        publisher:
          type: string
          nullable: true
          example: 'DAW'
        coverUrl:
          type: string
          format: uri
          example: 'https://book-vault-media.s3.amazonaws.com/covers/B002V5D1CG.jpg'
        audioUrl:
          type: string
          format: uri
          example: 'https://book-vault-media.s3.amazonaws.com/audio/B002V5D1CG.m4b'
        authors:
          type: array
          items:
            $ref: '#/components/schemas/Author'
        narrators:
          type: array
          items:
            $ref: '#/components/schemas/Narrator'
        series:
          type: array
          items:
            $ref: '#/components/schemas/SeriesInfo'
        categories:
          type: array
          items:
            $ref: '#/components/schemas/Category'

    Author:
      type: object
      required: [id, name]
      properties:
        id:
          type: string
          format: uuid
        name:
          type: string
          example: 'Patrick Rothfuss'
        asin:
          type: string
          nullable: true
          example: 'B002BMAYSQ'

    Narrator:
      type: object
      required: [id, name]
      properties:
        id:
          type: string
          format: uuid
        name:
          type: string
          example: 'Nick Podehl'
        asin:
          type: string
          nullable: true

    SeriesInfo:
      type: object
      required: [id, title]
      properties:
        id:
          type: string
          format: uuid
        title:
          type: string
          example: 'The Kingkiller Chronicle'
        sequence:
          type: string
          nullable: true
          description: "Book number in series (can be '1', '1.5', 'Prequel', etc.)"
          example: '1'
        asin:
          type: string
          nullable: true

    Category:
      type: object
      required: [id, name]
      properties:
        id:
          type: string
          format: uuid
        name:
          type: string
          example: 'Fantasy'

    Chapter:
      type: object
      required: [id, title, startTime, endTime, index]
      properties:
        id:
          type: string
          format: uuid
        title:
          type: string
          example: 'Chapter 1: A Place for Demons'
        startTime:
          type: number
          format: double
          minimum: 0
          example: 0
        endTime:
          type: number
          format: double
          minimum: 0
          example: 1806.5
        index:
          type: integer
          minimum: 0
          example: 0

    UserProgress:
      type: object
      required: [id, bookId, userId, positionSeconds, completed, lastPlayed]
      properties:
        id:
          type: string
          format: uuid
        bookId:
          type: string
          format: uuid
        userId:
          type: string
          format: uuid
        positionSeconds:
          type: number
          format: double
          minimum: 0
          example: 3612.5
        completed:
          type: boolean
          example: false
        lastPlayed:
          type: string
          format: date-time
          example: '2025-12-25T10:30:00Z'

    User:
      type: object
      required: [id, email]
      properties:
        id:
          type: string
          format: uuid
        email:
          type: string
          format: email
          example: 'user@example.com'

# Security applied to all endpoints by default
security:
  - bearerAuth: []

paths:
  # Authentication endpoints (no auth required)
  /api/auth/login:
    post:
      tags: [Authentication]
      summary: Login with email and password
      security: [] # Override global security (no auth needed)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password]
              properties:
                email:
                  type: string
                  format: email
                  example: 'test@example.com'
                password:
                  type: string
                  format: password
                  example: 'password123'
      responses:
        '200':
          description: Login successful
          content:
            application/json:
              schema:
                type: object
                required: [token, user]
                properties:
                  token:
                    type: string
                    description: JWT token for authentication
                    example: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
                  user:
                    $ref: '#/components/schemas/User'
        '401':
          description: Invalid credentials
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
```

**Create docs/api/README.md**:

```markdown
# Book Vault API Specification

## Overview

This directory contains the OpenAPI 3.0 specification for Book Vault's REST API.

## Files

- `openapi.yaml` - Complete API specification (single source of truth)

## Usage

### Validate Spec

\`\`\`bash
npm run api:validate
\`\`\`

### Generate TypeScript Types

\`\`\`bash
npm run api:generate:ts

# Output: lib/api-types.ts

\`\`\`

### Generate Swift Models (when iOS project exists)

\`\`\`bash
npm run api:generate:swift

# Output: ios/BookVault/Generated/Models/

\`\`\`

### Watch for Changes

\`\`\`bash
npm run api:watch

# Auto-regenerates types when openapi.yaml changes

\`\`\`

## Adding New Endpoints

1. Update `openapi.yaml` with new endpoint
2. Run `npm run api:validate` to check syntax
3. Run `npm run api:generate` to regenerate types
4. Implement backend using generated types
5. Test endpoint matches spec
6. Commit spec + implementation together

## Tools

- [Swagger Editor](https://editor.swagger.io/) - Visual editor
- [Swagger UI](https://swagger.io/tools/swagger-ui/) - Interactive docs (future)
- [openapi-typescript](https://github.com/drwpow/openapi-typescript) - TS type generation
- [OpenAPI Generator](https://openapi-generator.tech/) - Swift model generation
```

**Acceptance Criteria**:

- [ ] `docs/api/openapi.yaml` exists with base structure
- [ ] All core schemas defined (Book, Author, Narrator, etc.)
- [ ] Authentication schemas defined
- [ ] Login endpoint documented
- [ ] `npm run api:validate` passes
- [ ] `docs/api/README.md` created

**Stop Point**: Commit openapi.yaml and README.md

---

## Phase 2: Document Core Endpoints (~45 min)

**Objective**: Add all existing API endpoints to OpenAPI spec

**Files to Modify**:

- `docs/api/openapi.yaml` (add paths)

**Reference Files**:

- [docs/api-quick-ref.md](api-quick-ref.md) - Endpoint list
- Existing API route files:
  - `app/api/books/route.ts`
  - `app/api/books/[id]/route.ts`
  - `app/api/books/[id]/chapters/route.ts`
  - `app/api/progress/route.ts`
  - `app/api/search/route.ts`
  - `app/api/browse/*/route.ts`
  - `app/api/library/route.ts`

**Endpoints to Document** (add to paths section):

**Books**:

- `GET /api/books` - List books (paginated)
- `GET /api/books/{id}` - Get book details

**Chapters**:

- `GET /api/books/{id}/chapters` - Get chapters for book

**Progress**:

- `GET /api/progress` - Get user progress for book
- `POST /api/progress` - Update progress

**Search**:

- `GET /api/search` - Search across all types

**Browse**:

- `GET /api/browse/authors` - List authors
- `GET /api/browse/series` - List series
- `GET /api/browse/narrators` - List narrators
- `GET /api/browse/categories` - List categories
- `GET /api/browse/authors/{id}/books` - Books by author
- `GET /api/browse/series/{id}/books` - Books in series
- `GET /api/browse/narrators/{id}/books` - Books by narrator
- `GET /api/browse/categories/{id}/books` - Books in category

**Library**:

- `GET /api/library` - Get user's library
- `POST /api/library/add` - Add book to library
- `POST /api/library/remove` - Remove book from library

**Example Endpoint Documentation** (add to paths):

```yaml
paths:
  /api/books:
    get:
      tags: [Books]
      summary: Get all books (paginated)
      parameters:
        - name: page
          in: query
          schema:
            type: integer
            minimum: 1
            default: 1
          description: Page number
        - name: limit
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 100
            default: 20
          description: Items per page
      responses:
        '200':
          description: Paginated list of books
          content:
            application/json:
              schema:
                type: object
                required: [books, pagination]
                properties:
                  books:
                    type: array
                    items:
                      $ref: '#/components/schemas/Book'
                  pagination:
                    $ref: '#/components/schemas/Pagination'
        '401':
          description: Unauthorized
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
        '500':
          description: Server error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'

  /api/books/{id}:
    get:
      tags: [Books]
      summary: Get book details
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
          description: Book ID
      responses:
        '200':
          description: Book details
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Book'
        '404':
          description: Book not found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'

  /api/progress:
    get:
      tags: [Progress]
      summary: Get user progress for a book
      parameters:
        - name: bookId
          in: query
          required: true
          schema:
            type: string
            format: uuid
          description: Book ID to get progress for
      responses:
        '200':
          description: User progress
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UserProgress'
        '404':
          description: No progress found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'

    post:
      tags: [Progress]
      summary: Update user progress
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [bookId, positionSeconds]
              properties:
                bookId:
                  type: string
                  format: uuid
                positionSeconds:
                  type: number
                  format: double
                  minimum: 0
                completed:
                  type: boolean
                  default: false
      responses:
        '200':
          description: Progress updated
          content:
            application/json:
              schema:
                type: object
                required: [success, progress]
                properties:
                  success:
                    type: boolean
                    example: true
                  progress:
                    $ref: '#/components/schemas/UserProgress'
```

**Work Strategy**:

1. Read one API route file at a time
2. Document endpoint in OpenAPI
3. Run `npm run api:validate` after each endpoint
4. Fix validation errors immediately
5. Repeat for all endpoints

**Acceptance Criteria**:

- [ ] All 15+ endpoints documented
- [ ] Request/response schemas match actual API
- [ ] Query parameters documented
- [ ] Path parameters documented
- [ ] Request bodies documented
- [ ] All response codes documented (200, 401, 404, 500)
- [ ] `npm run api:validate` passes

**Stop Point**: Commit complete openapi.yaml

---

## Phase 3: Generate TypeScript Types & Validate (~20 min)

**Objective**: Generate types and ensure they work with existing code

**Files to Create**:

- `lib/api-types.ts` (generated, gitignored)

**Files to Modify**:

- `.gitignore` (add lib/api-types.ts)
- Optionally: API route files (to use generated types)

**Steps**:

1. **Add to .gitignore**:

```
# Generated API types
lib/api-types.ts
```

2. **Generate TypeScript types**:

```bash
npm run api:generate:ts
```

3. **Inspect generated types** (in lib/api-types.ts):

```typescript
// Should see types like:
export interface paths {
  '/api/books': {
    get: operations['get-books'];
  };
  '/api/books/{id}': {
    get: operations['get-book-by-id'];
  };
  // ... etc
}

export interface components {
  schemas: {
    Book: {
      id: string;
      asin: string;
      title: string;
      // ... etc
    };
    // ... etc
  };
}
```

4. **Test integration (optional but recommended)**:

Update one API route to use generated types:

```typescript
// app/api/books/route.ts
import type { components } from '@/lib/api-types';

type Book = components['schemas']['Book'];
type BookListResponse = components['schemas']['BookListResponse'];

export async function GET(request: NextRequest) {
  // ... existing code

  const response: BookListResponse = {
    books: books as Book[],
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };

  return NextResponse.json(response);
}
```

5. **Run type check**:

```bash
npm run type-check
```

6. **Fix any type mismatches** (update OpenAPI spec if needed)

**Acceptance Criteria**:

- [ ] `lib/api-types.ts` generated successfully
- [ ] Generated types match OpenAPI schemas
- [ ] `lib/api-types.ts` added to .gitignore
- [ ] Type check passes
- [ ] (Optional) At least one route uses generated types
- [ ] No TypeScript errors

**Stop Point**: Commit .gitignore changes, optionally commit route changes

---

## Phase 4: Setup Contract Testing (~30 min)

**Objective**: Add tests to validate API responses match OpenAPI spec

**Files to Create**:

- `__tests__/api/openapi-contract.test.ts` (new)

**Dependencies to Install**:

```bash
npm install --save-dev jest-openapi@0.14.2
```

**Test File Template**:

```typescript
// __tests__/api/openapi-contract.test.ts
import jestOpenAPI from 'jest-openapi';
import path from 'path';

// Load OpenAPI spec
const openApiPath = path.join(__dirname, '../../docs/api/openapi.yaml');
jestOpenAPI(openApiPath);

describe('OpenAPI Contract Tests', () => {
  describe('GET /api/books', () => {
    it('should satisfy OpenAPI spec', async () => {
      const response = await fetch('http://localhost:3000/api/books?page=1&limit=10', {
        headers: {
          Authorization: 'Bearer test-token', // Use test token
        },
      });

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toSatisfyApiSpec();
    });

    it('should return correct pagination structure', async () => {
      const response = await fetch('http://localhost:3000/api/books?page=1&limit=10', {
        headers: {
          Authorization: 'Bearer test-token',
        },
      });

      const data = await response.json();

      expect(data).toHaveProperty('books');
      expect(data).toHaveProperty('pagination');
      expect(data.pagination).toHaveProperty('page');
      expect(data.pagination).toHaveProperty('limit');
      expect(data.pagination).toHaveProperty('total');
      expect(data.pagination).toHaveProperty('totalPages');
    });
  });

  describe('GET /api/books/:id', () => {
    it('should satisfy OpenAPI spec for valid book', async () => {
      // Use actual book ID from test database
      const bookId = 'test-book-id';

      const response = await fetch(`http://localhost:3000/api/books/${bookId}`, {
        headers: {
          Authorization: 'Bearer test-token',
        },
      });

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toSatisfyApiSpec();
    });

    it('should return 404 for non-existent book', async () => {
      const response = await fetch('http://localhost:3000/api/books/non-existent-id', {
        headers: {
          Authorization: 'Bearer test-token',
        },
      });

      expect(response.status).toBe(404);

      const data = await response.json();
      expect(data).toHaveProperty('error');
    });
  });

  // Add tests for other endpoints...
});
```

**Run Tests**:

```bash
# Start dev server first
npm run dev

# In another terminal
npm test -- openapi-contract
```

**Acceptance Criteria**:

- [ ] `jest-openapi` installed
- [ ] Contract tests created
- [ ] Tests pass for all major endpoints
- [ ] Tests validate response structure matches spec
- [ ] Tests validate error responses (404, 401, etc.)

**Stop Point**: Commit contract tests

---

## Phase 5: Documentation Consolidation (~20 min)

**Objective**: Remove duplicate documentation and establish OpenAPI as single source of truth

**Files to Delete**:

- `docs/api-mobile.md` - Redundant with mobile/api-integration.md

**Files to Simplify**:

- `docs/mobile-ios-plan.md` - Remove detailed phase content (link to implementation-phases.md)
- `docs/api-quick-ref.md` - Simplify to cheat sheet + link to generated docs

**Steps**:

1. **Delete redundant mobile API doc**:

```bash
rm docs/api-mobile.md
```

2. **Simplify mobile-ios-plan.md**:

Remove the detailed phase descriptions (lines about Phase 1-8 details) and replace with:

```markdown
## Implementation Phases

**Detailed implementation phases**: See [docs/mobile/implementation-phases.md](mobile/implementation-phases.md)

**Quick overview**:

1. Phase 1: Auth & Browsing
2. Phase 2: Audio Playback
3. Phase 3: Background Audio
4. Phase 4: Progress Sync
5. Phase 5: Chapter Navigation
6. Phase 6: Search & Browse
7. Phase 7: User Lists
8. Phase 8: Offline Downloads

For acceptance criteria and detailed requirements, see implementation-phases.md.
```

3. **Update INDEX.md** - Remove api-mobile.md reference:

Remove the line:

```markdown
| [api-mobile.md](api-mobile.md) | Mobile API quick reference (condensed) | ~370 |
```

Add OpenAPI reference in new API section (see Phase 6 below).

**Acceptance Criteria**:

- [ ] `docs/api-mobile.md` deleted
- [ ] `docs/mobile-ios-plan.md` simplified (detailed phases removed)
- [ ] `docs/INDEX.md` updated (api-mobile.md reference removed)
- [ ] Token count reduced by ~1,000 tokens

**Token Savings**: ~1,000 tokens of duplication removed

**Stop Point**: Commit documentation consolidation

---

## Phase 6: Auto-Generated API Documentation (~15 min)

**Objective**: Setup automated API documentation generation from OpenAPI spec

**Note**: Documentation generation is already configured in Phase 0 using `@redocly/cli`. No additional dependencies needed!

**Generate API docs**:

```bash
npm run api:docs
```

**Add to .gitignore**:

```
# Generated API documentation
docs/api/api-reference.html
```

**Files to Modify**:

- `CLAUDE.md` - Add OpenAPI section
- `docs/ios-backend-sync.md` - Update OpenAPI status
- `docs/INDEX.md` - Add OpenAPI/API section
- `README.md` - Add OpenAPI info
- `docs/api-quick-ref.md` - Simplify to cheat sheet

**Update CLAUDE.md** (add to Section 2: Common Commands):

````markdown
### OpenAPI Spec

```bash
# Validate OpenAPI specification
npm run api:validate

# Generate TypeScript types from OpenAPI
npm run api:generate:ts

# Generate Swift models (requires iOS project)
npm run api:generate:swift

# Generate all types (TypeScript + Swift)
npm run api:generate

# Generate API documentation (HTML)
npm run api:docs

# Generate everything (types + docs)
npm run docs:generate

# Watch for changes and auto-regenerate
npm run api:watch
```
````

````

**Update docs/ios-backend-sync.md**:

Change:
```markdown
**OpenAPI Status**: Needs documentation
````

To:

```markdown
**OpenAPI Status**: ✅ Documented
```

**Update docs/INDEX.md** (add new API section):

```markdown
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

**After OpenAPI**: api-reference.html becomes primary API docs (always up-to-date)
```

**Simplify docs/api-quick-ref.md**:

Add at top:

```markdown
# API Quick Reference

> **Full API Documentation**: See [api/api-reference.html](api/api-reference.html) (auto-generated from OpenAPI spec)

This is a quick cheat sheet for common endpoints. For complete documentation with request/response schemas, authentication details, and examples, view the generated API reference.

## Quick Endpoints Cheat Sheet

[Rest of file becomes minimal quick reference]
```

**Acceptance Criteria**:

- [ ] `npm run api:docs` generates HTML successfully (using Redocly)
- [ ] `docs/api/api-reference.html` added to .gitignore
- [ ] `npm run docs:generate` runs both type generation and docs
- [ ] CLAUDE.md updated with new commands
- [ ] INDEX.md updated with API section
- [ ] ios-backend-sync.md OpenAPI status changed to ✅
- [ ] api-quick-ref.md simplified with link to generated docs

**Token Savings**: Eliminates manual API doc maintenance (~1,000 tokens ongoing)

**Stop Point**: Commit auto-generated documentation setup

---

## Phase 7: Final Verification & Cleanup (~10 min)

**Objective**: Final checks and project documentation updates

**Final Verification Checklist**:

- [ ] `npm run api:validate` passes
- [ ] `npm run api:generate` generates types without errors
- [ ] `npm run api:docs` generates HTML documentation
- [ ] `npm run type-check` passes
- [ ] `npm test -- openapi-contract` passes
- [ ] All documentation files updated (CLAUDE.md, INDEX.md, ios-backend-sync.md)
- [ ] OpenAPI spec is in git
- [ ] Generated files are gitignored (api-types.ts, api-reference.html)
- [ ] Redundant files deleted (api-mobile.md)
- [ ] Simplified files cleaned up (mobile-ios-plan.md, api-quick-ref.md)

**README.md Update** (optional):

Add OpenAPI section to README:

````markdown
## API Documentation

Book Vault uses OpenAPI 3.0 for API documentation and code generation.

**View API Docs**: Open `docs/api/api-reference.html` in your browser

**Generate Docs**:

```bash
npm run docs:generate  # Generate types + documentation
```
````

**Available Commands**:

- `npm run api:validate` - Validate OpenAPI spec
- `npm run api:generate` - Generate TypeScript + Swift types
- `npm run api:docs` - Generate HTML documentation
- `npm run api:watch` - Auto-regenerate on changes

See [docs/openapi-implementation-plan.md](docs/openapi-implementation-plan.md) for details.

````

**Create docs/api/.gitkeep** (if needed):
```bash
touch docs/api/.gitkeep
````

**Stop Point**: Final commit, tag as `openapi-v1.0.0`

---

## Post-Implementation: Next Steps

### Immediate (iOS Development Ready)

1. **Update iOS project creation** to run:

   ```bash
   npm run api:generate:swift
   ```

2. **Setup CI/CD** to validate spec:

   ```yaml
   # .github/workflows/api-validation.yml
   - name: Validate OpenAPI spec
     run: npm run api:validate

   - name: Generate types
     run: npm run api:generate

   - name: Contract tests
     run: npm test -- openapi-contract
   ```

### Future Enhancements

1. **Swagger UI** - Interactive API documentation

   ```bash
   npm install --save-dev swagger-ui-express
   ```

2. **API Versioning** - Add /api/v2 when breaking changes needed

3. **Mock Server** - Generate mock API from spec for testing
   ```bash
   npm install --save-dev @stoplight/prism-cli
   prism mock docs/api/openapi.yaml
   ```

---

## Context-Independent Execution Guide

**Each phase can be executed in a new Claude Code session with minimal context:**

**Phase 0**: Read this file, install packages, add scripts (~1,000 tokens)
**Phase 1**: Read this file + api-quick-ref.md + lib/types.ts, create base spec (~2,500 tokens)
**Phase 2**: Read this file + Phase 1 output + API route files, document endpoints (~4,000 tokens)
**Phase 3**: Read this file + Phase 2 output, generate types and validate (~1,500 tokens)
**Phase 4**: Read this file + Phase 3 output, create contract tests (~2,000 tokens)
**Phase 5**: Read this file, delete/simplify docs (~1,000 tokens)
**Phase 6**: Read this file, setup auto-generated docs (~1,500 tokens)
**Phase 7**: Read this file, final verification (~800 tokens)

**Total token estimate**: ~14,300 tokens across all phases (when reading referenced files)

**Total time estimate**: ~2.5 hours of focused work

---

## Quick Reference

**Commands**:

```bash
npm run api:validate           # Validate spec syntax
npm run api:generate:ts        # Generate TypeScript types
npm run api:generate:swift     # Generate Swift models
npm run api:generate           # Generate all types
npm run api:docs               # Generate HTML documentation
npm run docs:generate          # Generate types + docs
npm run api:watch              # Watch for changes
npm test -- openapi-contract   # Run contract tests
```

**Key Files**:

- `docs/api/openapi.yaml` - Single source of truth (in git)
- `lib/api-types.ts` - Generated TypeScript types (gitignored)
- `docs/api/api-reference.html` - Generated HTML docs (gitignored)
- `ios/BookVault/Generated/` - Generated Swift models (future)

**When to Update OpenAPI**:

- Adding new endpoint
- Changing request/response structure
- Adding new model/schema
- Changing authentication

**Workflow**:

1. Update `openapi.yaml`
2. Run `npm run api:validate`
3. Run `npm run docs:generate` (types + docs)
4. Implement backend changes
5. Run contract tests
6. Update iOS if needed
7. Commit atomically

## Summary of Changes

### Documentation Consolidation Benefits

| Change                    | Before                           | After                                   | Savings            |
| ------------------------- | -------------------------------- | --------------------------------------- | ------------------ |
| API Documentation         | Manual in 3 places               | Auto-generated from OpenAPI             | ~1,000 tokens      |
| Mobile API Docs           | api-mobile.md (370 tokens)       | Deleted (use mobile/api-integration.md) | ~370 tokens        |
| iOS Phase Details         | Duplicated in mobile-ios-plan.md | Link to implementation-phases.md        | ~600 tokens        |
| Swift Code Examples       | Duplicated across 3 files        | Single canonical source per topic       | ~2,000 tokens      |
| **Total Savings**         |                                  |                                         | **~3,970 tokens**  |
| **Maintenance Reduction** | Manual API doc updates           | Auto-generated (0 maintenance)          | **~70% less work** |

### Final Documentation Structure

```
docs/
├── INDEX.md                          # Updated with API section
├── CLAUDE.md                         # Updated with OpenAPI commands
├── api/
│   ├── openapi.yaml                  # 🔑 Single source of truth (in git)
│   ├── api-reference.html            # 🤖 Auto-generated (gitignored)
│   └── README.md                     # OpenAPI usage guide
├── api-quick-ref.md                  # 📝 Simplified cheat sheet
├── mobile-ios-plan.md                # 📱 Simplified overview (links to details)
├── ios-backend-sync.md               # 🔄 Updated (OpenAPI ✅)
├── mobile/
│   ├── implementation-phases.md      # 📋 Detailed phases (canonical)
│   ├── architecture.md               # 🏗️ Architecture (links to examples)
│   ├── api-integration.md            # 🔌 Swift API examples (canonical)
│   └── ios-features.md               # 📱 iOS features (canonical)
└── openapi-implementation-plan.md    # 🚀 This file

Deleted:
- ❌ docs/api-mobile.md (redundant)

Generated (gitignored):
- lib/api-types.ts (TypeScript)
- docs/api/api-reference.html (HTML docs)
- ios/BookVault/Generated/*.swift (Swift models, future)
```
