# Testing Guide

> **TL;DR**: Commands and how-to for writing/running tests. For the _authoritative_ picture
> of the gates, what CI enforces, the deploy pipeline, and the hardening invariants that
> must not regress, see **[development-process.md](development-process.md)** — this guide is
> the day-to-day cheat-sheet and does not duplicate that detail.
>
> Everyday: `npm run validate:web` (web + DB, no Xcode). Full gate: `npm run validate:full`
> (web + DB + iOS). Pre-deploy: `npm run deploy:dry-run`.

**Jump to**: [Quick Reference](#quick-reference) | [Web Testing](#web-testing-jest--rtl) | [API Contract Testing](#api-contract-testing) | [iOS Testing](#ios-testing-xctest) | [CI/CD Workflows](#cicd-workflows) | [Deployment Validation](#deployment-validation)

---

## Quick Reference

| Command                    | Purpose                                                        |
| -------------------------- | -------------------------------------------------------------- |
| `npm test`                 | Unit tests only (node + jsdom projects, no DB needed)          |
| `npm run test:watch`       | Jest watch mode (unit projects)                                |
| `npm run test:coverage`    | Unit tests with coverage report (ratchet enforced)             |
| `npm run test:integration` | Real-DB tests — requires `docker-compose up -d`                |
| `npm run test:all`         | Every Jest project including integration                       |
| `npm run test:contract`    | OpenAPI contract tests (auto-starts server, needs DB)          |
| `npm run test:e2e`         | Playwright web smoke (auto-starts server + seeds, needs DB)    |
| `npm run validate`         | Fast inner loop: format + lint + types + unit tests            |
| `npm run validate:web`     | Web gate + DB suites (integration + contract + E2E). No Xcode. |
| `npm run validate:ios`     | iOS gate (Swift drift + SwiftLint + build + tests)             |
| `npm run validate:full`    | Everything: web + DB suites + iOS. Needs Docker **and** Xcode. |
| `npm run ios:validate`     | Same iOS gate as `validate:ios` (iOS-focused entry point)      |
| `npm run ios:lint`         | SwiftLint only                                                 |
| `npm run ios:build`        | iOS build only                                                 |
| `npm run ios:test`         | iOS tests only                                                 |
| `npm run deploy`           | `validate:full` + push (web + DB + iOS, then AWS)              |
| `npm run deploy:dry-run`   | `validate:full` only (no push) — best pre-deploy check         |
| `npm run deploy:web`       | Web gate + DB suites + push (no iOS)                           |
| `npm run deploy:only`      | Push without any validation                                    |

> Full detail on what each gate runs and how deploy relates to validate lives in
> [development-process.md §2 + §8](development-process.md).

---

## Web Testing (Jest + RTL)

### Running Tests

Jest is split into three projects (`jest.config.js`): `unit-node` (API routes, lib,
scripts), `unit-dom` (components, pages), and `integration` (tests that hit the real
Postgres — kept out of `npm test` so a fresh clone is always green without Docker).

```bash
# Run all unit tests (no DB required)
npm test

# Run integration tests (start the DB first: docker-compose up -d)
npm run test:integration

# Run tests in watch mode
npm run test:watch

# Run tests with coverage report (enforces the coverage ratchet)
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

# TS drift is in the web gate (validate:web / validate:full).
# Swift drift is in the iOS gate (validate:ios / validate:full) — NOT validate:web.
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

## CarPlay Testing

CarPlay has two layers, and only one is automated.

### Automated (part of the normal gate)

Unit tests in `ios/BookVaultTests/CarPlay/` cover the row mapping, empty/error/
offline states, auth-state template switching, and the chapter-step logic. They
run with `npm run validate:ios` like any other iOS test — no CarPlay required,
which is exactly why the logic lives in `CarPlayLibraryProvider`,
`CarPlayCoordinator` and `CarPlayNowPlaying` rather than in the scene delegate.

### Manual (CarPlay Simulator)

**The CarPlay UI itself cannot be tested automatically.** There is no XCUITest
equivalent for CarPlay templates.

```
1. Run the app on a simulator from Xcode
2. Xcode ▸ I/O ▸ External Displays ▸ CarPlay
3. A CarPlay head-unit window opens alongside the phone simulator
```

The manual matrix lives in §5 of
[plans/carplay-implementation-plan.md](plans/carplay-implementation-plan.md).
The cases most worth running, because unit tests structurally cannot reach them:

- Cold launch **mid session-restore** — must show a neutral state, not a false
  "signed out" flash.
- Phone and CarPlay both visible — play/pause/seek must stay in sync in both
  directions.
- Logout on the phone while CarPlay is open — the root template must swap.
- Airplane mode with and without downloads.
- Disconnect/reconnect — the scene must rebuild without duplicating templates.

### Hardware

One pass on a real head unit or dock before shipping. The Simulator does not
reproduce head-unit scroll throttling, image scaling at real trait collections,
or Siri interactions. Requires the approved CarPlay entitlement.

## CI/CD Workflows

### Workflow Summary

| Workflow  | File            | Triggers                 | Purpose                                           |
| --------- | --------------- | ------------------------ | ------------------------------------------------- |
| Main      | `main.yml`      | PR, push to main         | Format, lint, types, tests (live Postgres), audit |
| API       | `api.yml`       | PR, push to main         | OpenAPI validation, drift checks, contract tests  |
| E2E       | `e2e.yml`       | PR, push (path-filtered) | Playwright web smoke                              |
| iOS       | `ios-tests.yml` | PR, push (path-filtered) | SwiftLint, build, tests                           |
| Storybook | `storybook.yml` | PR, push to main         | Storybook build check                             |

### What Each Workflow Checks

**main.yml:** (runs against a live Postgres service, so the integration project runs too)

- `npm run format:check`
- `npm run lint`
- `npm run type-check`
- `npm test`
- `npm audit` — **non-blocking** (`continue-on-error`)

**api.yml:**

- `npm run api:validate` - OpenAPI spec syntax
- `npm run api:check-drift` - TypeScript types in sync
- `npm run api:check-drift:swift` - Swift models in sync
- `npm run api:check-coverage` - Endpoint coverage
- `npm run test:contract` - Contract tests (builds + boots the app)

**e2e.yml:** (path-filtered to `app/`, `components/`, `lib/`, `e2e/`, `prisma/`, config)

- `npm run test:e2e` - Playwright web smoke (globalSetup seeds fixtures)

**ios-tests.yml:** (path-filtered to `ios/**`)

- `swiftlint lint --strict` — **non-blocking** in CI (`continue-on-error`); the deploy /
  `validate:ios` gate treats it as a hard failure. See
  [development-process.md §4](development-process.md).
- `xcodebuild build`
- `xcodebuild test`

### Local vs CI Parity

| Check          | Local Script                    | CI Workflow     |
| -------------- | ------------------------------- | --------------- |
| Format         | `npm run format:check`          | `main.yml`      |
| Lint           | `npm run lint`                  | `main.yml`      |
| Type check     | `npm run type-check`            | `main.yml`      |
| Tests (unit)   | `npm test`                      | `main.yml`      |
| API validate   | `npm run api:validate`          | `api.yml`       |
| TS drift       | `npm run api:check-drift`       | `api.yml`       |
| Swift drift    | `npm run api:check-drift:swift` | `api.yml`       |
| Contract tests | `npm run test:contract`         | `api.yml`       |
| E2E smoke      | `npm run test:e2e`              | `e2e.yml`       |
| iOS lint       | `npm run ios:lint`              | `ios-tests.yml` |
| iOS build      | `npm run ios:build`             | `ios-tests.yml` |
| iOS tests      | `npm run ios:test`              | `ios-tests.yml` |

---

## Deployment Validation

### Pre-Deployment Commands

```bash
# Full gate (web + DB suites + iOS) + deploy
npm run deploy

# Web gate + DB suites + deploy (skip iOS)
npm run deploy:web

# Deploy only (no validation - use cautiously)
npm run deploy:only

# Dry run: full gate, no deploy — best pre-deploy check
npm run deploy:dry-run
```

### What Validation Runs

`deploy.sh` and `validate.sh` share one step library, so deploy runs the **same** gates as
the `validate:*` family (`deploy` = `validate:full` + AWS push). Because it runs the DB
suites, deploy needs Postgres up (`docker-compose up -d`).

| Command                  | Web gate + DB suites | iOS gate | Push |
| ------------------------ | -------------------- | -------- | ---- |
| `npm run deploy`         | yes                  | yes      | yes  |
| `npm run deploy:web`     | yes                  | no       | yes  |
| `npm run deploy:only`    | no                   | no       | yes  |
| `npm run deploy:dry-run` | yes                  | yes      | no   |

For the exact step order, the AWS-side requirements (profile, ECR/ECS, buildx, health
check), and why a green CI can still block deploy, see
[development-process.md §8](development-process.md).

### Log Files

All validation and deploy scripts log output to files in `logs/` (gitignored):

| Script                  | Log File                |
| ----------------------- | ----------------------- |
| `npm run validate:full` | `logs/validate.log`     |
| `npm run ios:validate`  | `logs/ios-validate.log` |
| `npm run deploy`        | `logs/deploy.log`       |

Logs are appended with timestamps, making it easy to review failures without re-running commands.

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
6. **Run `npm run validate:full` before opening a PR** - the complete gate (§ dev-process). `npm run validate` is a faster inner-loop check while iterating.
7. **Run `npm run deploy:dry-run` before an actual deploy** - verifies the full pipeline without pushing

---

## Security & Code Quality

### Security Auditing

```bash
# Check for known vulnerabilities in dependencies
npm run security:audit

# Attempt automatic fixes
npm run security:fix
```

### ESLint Security Plugin

Detects common security issues in code. Runs automatically with `npm run lint`.

### Configuration Files

| File                 | Purpose                                        |
| -------------------- | ---------------------------------------------- |
| `.eslintrc.json`     | ESLint configuration (includes security rules) |
| `.prettierrc.json`   | Prettier formatting                            |
| `.prettierignore`    | Files excluded from formatting                 |
| `.lintstagedrc.json` | Pre-commit hook configuration                  |
| `.husky/pre-commit`  | Git pre-commit hook                            |
