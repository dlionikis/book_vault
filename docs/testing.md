# Testing Guide

> **TL;DR**: All testing commands and CI workflows in one place. Run `npm run validate` for quick checks, `npm run validate:full` for full validation, `npm run deploy --dry-run` to test deployment pipeline.

**Jump to**: [Quick Reference](#quick-reference) | [Web Testing](#web-testing-jest--rtl) | [API Contract Testing](#api-contract-testing) | [iOS Testing](#ios-testing-xctest) | [CI/CD Workflows](#cicd-workflows) | [Deployment Validation](#deployment-validation)

---

## Quick Reference

| Command                 | Purpose                                         |
| ----------------------- | ----------------------------------------------- |
| `npm test`              | Run Jest tests                                  |
| `npm run test:watch`    | Jest watch mode                                 |
| `npm run test:coverage` | Jest with coverage report                       |
| `npm run test:contract` | Run OpenAPI contract tests (auto-starts server) |
| `npm run validate`      | Format + lint + types + tests                   |
| `npm run validate:full` | Above + API validation + drift checks           |
| `npm run ios:validate`  | iOS drift check + lint + build + tests          |
| `npm run ios:lint`      | SwiftLint only                                  |
| `npm run ios:build`     | iOS build only                                  |
| `npm run ios:test`      | iOS tests only                                  |
| `npm run deploy`        | Full validation (web + iOS) + deploy            |
| `npm run deploy:web`    | Web validation + deploy                         |
| `npm run deploy:only`   | Deploy without checks                           |

---

## Web Testing (Jest + RTL)

### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage report
npm run test:coverage

# Run specific test file
npm test -- __tests__/api/openapi-contract.test.ts

# Run tests matching a pattern
npm test -- -t "book schema"

# Run a specific test by name
npm test -- --testNamePattern="validates book schema fields match OpenAPI spec"
```

### Test Structure

```
__tests__/
├── components/          # Component tests
│   ├── BackButton.test.tsx
│   ├── BookCard.test.tsx
│   ├── BookGrid.test.tsx
│   └── SortDropdown.test.tsx
├── lib/                 # Utility function tests
│   └── utils.test.ts
└── api/                 # API contract tests
    ├── openapi-contract.test.ts
    └── api-types-validation.test.ts
```

### Writing Tests

**Component Tests:**

```typescript
import { render, screen } from '@testing-library/react';
import MyComponent from '@/components/MyComponent';

describe('MyComponent', () => {
  it('renders correctly', () => {
    render(<MyComponent />);
    expect(screen.getByText('Hello')).toBeInTheDocument();
  });
});
```

**Testing User Interactions:**

```typescript
import { fireEvent } from '@testing-library/react';

it('handles click events', () => {
  const mockClick = jest.fn();
  render(<Button onClick={mockClick} />);

  fireEvent.click(screen.getByRole('button'));
  expect(mockClick).toHaveBeenCalledTimes(1);
});
```

**Mocking Next.js Hooks:**

```typescript
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
}));
```

**Mocking Prisma Client:**

```typescript
import { mockDeep } from 'jest-mock-extended';
import { PrismaClient } from '@prisma/client';

jest.mock('@/lib/db', () => ({
  prisma: mockDeep<PrismaClient>(),
}));

// In your test
import { prisma } from '@/lib/db';

it('fetches books from database', async () => {
  (prisma.book.findMany as jest.Mock).mockResolvedValue([
    { id: '1', title: 'Test Book' /* ... */ },
  ]);

  // Test code that uses prisma
});
```

### Coverage Goals

- **Components**: 80%+ coverage
- **Utilities**: 90%+ coverage
- **API Routes**: 70%+ coverage

### Configuration Files

- `jest.config.js` - Jest configuration
- `jest.setup.js` - Global test setup
- `__mocks__/**` - Mock implementations
- `lib/types.ts` - Shared TypeScript types for test data

---

## API Contract Testing

OpenAPI contract tests ensure API responses match the OpenAPI specification.

### Running Contract Tests

```bash
# Run contract tests (auto-starts server)
npm run test:contract

# Manual: Start server + run tests separately
npm run dev &
RUN_CONTRACT_TESTS=true npm test -- __tests__/api
```

### Type Drift Checks

Ensure generated types are in sync with OpenAPI spec:

```bash
# Check TypeScript types
npm run api:check-drift

# Check Swift models
npm run api:check-drift:swift

# Both are included in validate:full
npm run validate:full
```

### OpenAPI Validation

```bash
# Validate OpenAPI spec syntax
npm run api:validate

# Check endpoint coverage (routes vs spec)
npm run api:check-coverage

# Regenerate types from spec
npm run api:generate:ts      # TypeScript
npm run api:generate:swift   # Swift
npm run api:generate         # Both
```

### How Contract Tests Work

1. Tests use `jest-openapi` to validate responses against `docs/api/openapi.yaml`
2. Zod schemas validate response structure
3. CI runs these on every PR (see `api.yml` workflow)

**Example contract test:**

```typescript
import { createOpenAPIValidator } from '@/lib/test-utils';

const validator = createOpenAPIValidator();

it('GET /api/books returns valid response', async () => {
  const res = await fetch('http://localhost:3000/api/books');
  const data = await res.json();

  expect(res).toSatisfyApiSpec();
  expect(data).toMatchOpenAPISchema('BookListResponse');
});
```

---

## iOS Testing (XCTest)

### Running iOS Tests

```bash
# Full iOS validation (drift check + lint + build + test)
npm run ios:validate

# Skip drift check (useful if you've already run it)
./scripts/ios-validate.sh --skip-drift

# Individual steps
npm run ios:lint       # SwiftLint only
npm run ios:build      # Build only
npm run ios:test       # Tests only
```

### Or via Xcode

- **Run tests**: `Cmd+U` (Product > Test)
- **Run specific test**: Click play button next to test method
- **View coverage**: Product > Test > Show Test Navigator

### SwiftLint

Configuration: `ios/.swiftlint.yml`

```bash
# Run SwiftLint manually
cd ios && swiftlint lint --config .swiftlint.yml --strict
```

### iOS Test Structure

```
ios/BookVaultTests/
├── Services/
│   ├── APIServiceTests.swift
│   ├── AuthServiceTests.swift
│   └── AudioPlayerTests.swift
├── ViewModels/
│   ├── LibraryViewModelTests.swift
│   └── PlayerViewModelTests.swift
└── Mocks/
    └── MockServices.swift
```

### Coverage Threshold

- **iOS Tests**: 568+ tests
- Target: 70%+ code coverage

---

## CI/CD Workflows

### Workflow Summary

| Workflow  | File            | Triggers         | Purpose                                          |
| --------- | --------------- | ---------------- | ------------------------------------------------ |
| Main      | `main.yml`      | PR, push to main | Format, lint, types, tests                       |
| API       | `api.yml`       | PR, push to main | OpenAPI validation, drift checks, contract tests |
| iOS       | `ios-tests.yml` | PR, push to main | SwiftLint, build, tests                          |
| Storybook | `storybook.yml` | PR, push to main | Storybook build check                            |

### What Each Workflow Checks

**main.yml:**

- `npm run format:check`
- `npm run lint`
- `npm run type-check`
- `npm test`

**api.yml:**

- `npm run api:validate` - OpenAPI spec syntax
- `npm run api:check-drift` - TypeScript types in sync
- `npm run api:check-drift:swift` - Swift models in sync
- `npm run api:check-coverage` - Endpoint coverage
- `npm run test:contract` - Contract tests (live server)

**ios-tests.yml:**

- `swiftlint lint --strict`
- `xcodebuild build`
- `xcodebuild test`

### Local vs CI Parity

| Check          | Local Script                    | CI Workflow     |
| -------------- | ------------------------------- | --------------- |
| Format         | `npm run format:check`          | `main.yml`      |
| Lint           | `npm run lint`                  | `main.yml`      |
| Type check     | `npm run type-check`            | `main.yml`      |
| Tests          | `npm test`                      | `main.yml`      |
| API validate   | `npm run api:validate`          | `api.yml`       |
| TS drift       | `npm run api:check-drift`       | `api.yml`       |
| Swift drift    | `npm run api:check-drift:swift` | `api.yml`       |
| Contract tests | `npm run test:contract`         | `api.yml`       |
| iOS lint       | `npm run ios:lint`              | `ios-tests.yml` |
| iOS build      | `npm run ios:build`             | `ios-tests.yml` |
| iOS tests      | `npm run ios:test`              | `ios-tests.yml` |

---

## Deployment Validation

### Pre-Deployment Commands

```bash
# Full validation (web + iOS) + deploy
npm run deploy

# Web validation + deploy (skip iOS)
npm run deploy:web

# Deploy only (no validation - use cautiously)
npm run deploy:only

# Dry run (validate without deploying)
./scripts/deploy.sh --dry-run
./scripts/deploy.sh --web --dry-run
```

### What Validation Runs

| Command               | Web Checks      | iOS Checks              | Deploy |
| --------------------- | --------------- | ----------------------- | ------ |
| `npm run deploy`      | `validate:full` | drift + lint/build/test | Yes    |
| `npm run deploy:web`  | `validate:full` | None                    | Yes    |
| `npm run deploy:only` | None            | None                    | Yes    |

### Deploy Script Options

```bash
./scripts/deploy.sh              # Full validation + deploy
./scripts/deploy.sh --web        # Web only + deploy
./scripts/deploy.sh --deploy-only # Skip all validation
./scripts/deploy.sh --dry-run    # Validate only, no deploy
```

---

## Pre-commit Hooks

Husky runs on every commit:

1. `lint-staged` - Format & lint changed files
2. OpenAPI regeneration (if spec changed):
   - Regenerate TypeScript types
   - Regenerate Swift models
   - Validate OpenAPI spec

---

## Troubleshooting

### Test fails with "Cannot find module"

- Check module path aliases in `jest.config.js`
- Ensure `moduleNameMapper` is configured correctly

### "Request is not defined" error

- Next.js API routes require server runtime
- Use contract tests or E2E testing for API routes

### Component not rendering

- Check that all required props are provided
- Verify mocks are set up correctly
- Use `screen.debug()` to see rendered output

### Contract tests fail with connection refused

- Ensure dev server is running: `npm run dev`
- Check port 3000 is available: `lsof -i :3000`

### iOS tests fail in CI but pass locally

- Check Xcode/SDK version matches CI
- Verify simulator destination: `iPhone 15,OS=17.5`
- Run `cd ios && xcodegen generate` to sync project

### Swift drift check fails

```bash
# Regenerate Swift models
npm run api:generate:swift

# Commit the changes
git add ios/BookVault/Generated/Models/
git commit -m "chore: regenerate Swift models"
```

---

## Best Practices

1. **Test behavior, not implementation** - Focus on what users see and do
2. **Use semantic queries** - Prefer `getByRole`, `getByLabelText`, `getByText`
3. **Avoid testing styling** - Test functional behavior
4. **Mock external dependencies** - Keep tests isolated
5. **Write descriptive test names** - Make failures easy to understand
6. **Run `npm run validate` before committing** - Catch issues early
7. **Run `npm run deploy --dry-run` before actual deploy** - Verify full pipeline
