# Book Vault API Specification

## Overview

This directory contains the OpenAPI 3.0 specification for Book Vault's REST API.

## Files

- `openapi.yaml` - Complete API specification (single source of truth)

## Usage

### Validate Spec

```bash
npm run api:validate
```

### Generate TypeScript Types

```bash
npm run api:generate:ts
# Output: lib/api-types.ts
```

### Generate Swift Models (when iOS project exists)

```bash
npm run api:generate:swift
# Output: ios/BookVault/Generated/Models/
```

### Watch for Changes

```bash
npm run api:watch
# Auto-regenerates types when openapi.yaml changes
```

### Contract Testing

Contract tests validate that API responses match the OpenAPI specification.

**Quick start** (recommended):

```bash
npm run test:contract
# Automatically starts server, waits for startup, runs tests, stops server
```

**Manual control** (for debugging):

```bash
# Terminal 1: Start dev server
npm run dev

# Terminal 2: Run contract tests
RUN_CONTRACT_TESTS=true npm test -- openapi-contract
```

**In CI**: Contract tests run automatically on every PR via `.github/workflows/api.yml`

**Environment Variables**:

- `RUN_CONTRACT_TESTS=true` - Enable contract tests (default: skipped)
- `TEST_API_URL` - API base URL (default: http://localhost:3000)
- `TEST_USER_EMAIL` - Test user email (default: test@example.com)
- `TEST_USER_PASSWORD` - Test user password (default: password123)

**Prerequisites**:

- Dev server running (`npm run dev`)
- Test database seeded (`npm run db:seed`)
- Test user exists (created by seed script)

**What Gets Tested**:

- Response structure matches OpenAPI schemas
- Required fields are present
- Field types match specification
- Status codes match documented responses
- Error responses have correct structure

## CI/CD Integration

### Automated Validation (GitHub Actions)

Every PR and push to `main` runs:

1. **Spec Validation** - Ensures `openapi.yaml` is syntactically correct
2. **Drift Detection** - Fails if `lib/api-types.ts` is stale
3. **Contract Tests** - Validates all 23 endpoints match spec

**Workflow**: `.github/workflows/api.yml`

**Status Badge**:

```markdown
[![API Contract](https://github.com/dlionikis/book_vault/actions/workflows/api.yml/badge.svg)](https://github.com/dlionikis/book_vault/actions/workflows/api.yml)
```

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

## Adding New Endpoints

1. Update `openapi.yaml` with new endpoint
2. Run `npm run api:validate` to check syntax
3. Run `npm run api:generate` to regenerate types
4. Implement backend using generated types
5. Run contract tests to verify spec compliance
6. Commit spec + implementation together

## Tools

- [Swagger Editor](https://editor.swagger.io/) - Visual editor
- [Swagger UI](https://swagger.io/tools/swagger-ui/) - Interactive docs (future)
- [openapi-typescript](https://github.com/drwpow/openapi-typescript) - TS type generation
- [OpenAPI Generator](https://openapi-generator.tech/) - Swift model generation
