# Testing Guide

## Overview

Book Vault uses **Jest** and **React Testing Library** for unit and component testing.

## Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage report
npm run test:coverage
```

## Test Structure

```
__tests__/
├── components/          # Component tests
│   ├── BackButton.test.tsx
│   ├── BookCard.test.tsx
│   ├── BookGrid.test.tsx
│   └── SortDropdown.test.tsx
├── lib/                 # Utility function tests
│   └── utils.test.ts
└── api/                 # API route tests (currently skipped)
    ├── books.test.ts
    └── books-id.test.ts
```

## Current Test Coverage

✅ **Components**

- BackButton - Navigation functionality
- BookCard - Book display and metadata
- BookGrid - Responsive grid layout
- SortDropdown - Sort selection and routing

✅ **Utilities**

- formatRuntime - Time formatting
- calculateRating - Review rating calculations

⚠️ **API Routes** (Skipped)

- API route tests require Next.js runtime environment
- Will be implemented with integration testing setup

## Writing Tests

### Component Tests

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

### Testing User Interactions

```typescript
import { fireEvent } from '@testing-library/react';

it('handles click events', () => {
  const mockClick = jest.fn();
  render(<Button onClick={mockClick} />);

  fireEvent.click(screen.getByRole('button'));
  expect(mockClick).toHaveBeenCalledTimes(1);
});
```

### Mocking Next.js Hooks

```typescript
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
}));
```

### Mocking Prisma Client

For tests that interact with the database, mock the centralized Prisma client singleton:

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

**Note**: The project uses `jest-mock-extended` for type-safe Prisma mocking. This provides better TypeScript support than manual `jest.fn()` mocks.

## Test Configuration

- **jest.config.js** - Jest configuration
- **jest.setup.js** - Global test setup
- \***\*mocks**/\*\* - Mock implementations
- **lib/types.ts** - Shared TypeScript types for test data

## Best Practices

1. **Test behavior, not implementation** - Focus on what users see and do
2. **Use semantic queries** - Prefer `getByRole`, `getByLabelText`, `getByText`
3. **Avoid testing styling** - Test functional behavior
4. **Mock external dependencies** - Keep tests isolated
5. **Write descriptive test names** - Make failures easy to understand

## Coverage Goals

- **Components**: 80%+ coverage
- **Utilities**: 90%+ coverage
- **API Routes**: 70%+ coverage (when implemented)

## CI/CD Integration

Tests are included in the `validate` script and run on pre-commit:

```bash
npm run validate  # Runs format check, lint, type-check, and tests
```

## Troubleshooting

### Test fails with "Cannot find module"

- Check module path aliases in `jest.config.js`
- Ensure `moduleNameMapper` is configured correctly

### "Request is not defined" error

- Next.js API routes require server runtime
- Consider using integration tests or E2E testing

### Component not rendering

- Check that all required props are provided
- Verify mocks are set up correctly
- Use `screen.debug()` to see rendered output

## Future Improvements

- [ ] Add integration tests with test database
- [ ] Set up E2E testing with Playwright
- [ ] Increase API route test coverage
- [ ] Add visual regression testing
- [ ] Set up CI/CD test automation
