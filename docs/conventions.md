# Coding Conventions

> Standards and patterns for consistent code across the Book Vault project.

**Last Updated**: January 6, 2026

---

## File Naming

### Components

- **Format**: PascalCase with `.tsx` extension
- **Examples**: `AudioPlayer.tsx`, `BookCard.tsx`, `UserMenu.tsx`
- **Location**: `/components` directory (flat structure, no subdirectories)
- **Stories**: Matching `.stories.tsx` file for Storybook (e.g., `AudioPlayer.stories.tsx`)

### API Routes

- **Format**: `route.ts` inside feature directories
- **Structure**: `/app/api/[feature]/[...nested]/route.ts`
- **Examples**:
  - `app/api/books/route.ts`
  - `app/api/books/[id]/route.ts`
  - `app/api/books/[id]/chapters/route.ts`
- **HTTP Methods**: Export named functions `GET`, `POST`, `PUT`, `DELETE`

### Pages

- **Format**: `page.tsx` inside route directories
- **Examples**:
  - `app/books/[id]/page.tsx`
  - `app/library/page.tsx`
  - `app/search/page.tsx`

### Utilities

- **Format**: kebab-case with `.ts` extension
- **Examples**: `book-transformer.ts`, `api-helpers.ts`, `rate-limit.ts`
- **Location**: `/lib` directory
- **Pattern**: One module per concern, export multiple related functions

### Types

- **Format**: kebab-case with `.ts` extension
- **Examples**: `api-types.ts`, `api-schemas.ts`, `types.ts`
- **Location**: `/lib` or `/types` directory

---

## Import Order

Organize imports in this order with blank lines between groups:

```typescript
// 1. External packages (React, Next.js, third-party)
import { useState, useEffect } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { getServerSession } from 'next-auth';

// 2. Internal utilities and types
import { prisma } from '@/lib/db';
import { transformBook, BOOK_INCLUDE } from '@/lib/book-transformer';
import { Book, Author } from '@/lib/types';

// 3. Components
import BookCard from '@/components/BookCard';
import AudioPlayer from '@/components/AudioPlayer';

// 4. Styles (if any)
import styles from './Component.module.css';
```

**Use `@/` alias** for all internal imports:

- ✅ `import { prisma } from '@/lib/db';`
- ❌ `import { prisma } from '../../../lib/db';`

---

## Component Structure

### Client Components

```typescript
'use client';

import { useState, useEffect } from 'react';
import { ComponentProps } from '@/lib/types';

/**
 * [Component description]
 *
 * [Detailed behavior]
 *
 * @param prop - Description
 * @returns Description
 */
export default function ComponentName({ prop1, prop2 }: ComponentProps) {
  // 1. State declarations
  const [state, setState] = useState(initialValue);

  // 2. Refs
  const ref = useRef<HTMLElement>(null);

  // 3. Effects
  useEffect(() => {
    // Effect logic
  }, [dependencies]);

  // 4. Event handlers and helper functions
  const handleClick = () => {
    // Handler logic
  };

  const helperFunction = () => {
    // Helper logic
  };

  // 5. Early returns (loading, error states)
  if (loading) return <LoadingSpinner />;
  if (error) return <ErrorMessage />;

  // 6. Main render
  return (
    <div>
      {/* Component JSX */}
    </div>
  );
}
```

### Server Components

```typescript
import { prisma } from '@/lib/db';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import ComponentName from '@/components/ComponentName';

/**
 * [Page description]
 *
 * Server component that fetches data and renders UI
 */
export default async function PageName() {
  // 1. Fetch authentication
  const session = await getServerSession(authOptions);

  // 2. Fetch data (parallel when possible)
  const [data1, data2] = await Promise.all([
    prisma.model.findMany(),
    prisma.otherModel.findMany(),
  ]);

  // 3. Transform data if needed
  const transformed = data1.map(transformFunction);

  // 4. Render
  return (
    <div>
      <ComponentName data={transformed} />
    </div>
  );
}
```

---

## API Route Patterns

### Standard Structure

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions, getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { withLogging } from '@/lib/logger';

/**
 * [METHOD] /api/path
 *
 * [Description]
 *
 * Auth: Required/Optional/Public
 * Request: [Body/query param description]
 * Returns: [Response structure]
 */
export const GET = withLogging(async (request: NextRequest) => {
  // 1. Authentication (dual support)
  const session = await getServerSession(authOptions);
  const mobileUser = await getAuthUserFromRequest(request);
  const user = session?.user || mobileUser;

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    // 2. Parse and validate input
    const searchParams = request.nextUrl.searchParams;
    const id = searchParams.get('id');

    if (!id) {
      return NextResponse.json({ error: 'ID is required' }, { status: 400 });
    }

    // 3. Database operations
    const data = await prisma.model.findUnique({
      where: { id },
    });

    if (!data) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }

    // 4. Transform response
    const response = transformData(data);

    // 5. Return success
    return NextResponse.json(response);
  } catch (error) {
    console.error('Error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
});
```

### Error Response Format

Always return errors with this structure:

```typescript
return NextResponse.json({ error: 'Error message' }, { status: statusCode });
```

Common status codes:

- `400` - Bad request (validation failed)
- `401` - Unauthorized
- `404` - Not found
- `429` - Rate limited
- `500` - Server error

---

## Database Patterns

### Querying with Prisma

```typescript
// Standard book query with relations
const book = await prisma.book.findUnique({
  where: { id },
  include: BOOK_INCLUDE, // Use constant for consistency
});

// Pagination pattern
const page = parseInt(searchParams.get('page') || '1');
const limit = parseInt(searchParams.get('limit') || '20');
const skip = (page - 1) * limit;

const [items, total] = await Promise.all([
  prisma.model.findMany({
    skip,
    take: limit,
    orderBy: { field: 'asc' },
  }),
  prisma.model.count(),
]);

// Use buildPagination() helper
const pagination = buildPagination(total, page, limit);
```

### Connection Management

- Use the singleton Prisma client from `@/lib/db`
- Never create multiple Prisma instances
- Connection pooling is handled automatically

---

## State Management

### Client-Side State

```typescript
// Local component state
const [value, setValue] = useState(initialValue);

// URL state (for filters, pagination)
const searchParams = useSearchParams();
const router = useRouter();

const updateUrl = (key: string, value: string) => {
  const params = new URLSearchParams(searchParams.toString());
  params.set(key, value);
  router.push(`?${params.toString()}`);
};
```

### Server-Side State

- Fetch data in server components
- Pass as props to client components
- Re-fetch via API routes when client needs updates

---

## Error Handling

### Client Components

```typescript
const [error, setError] = useState<string | null>(null);

try {
  const response = await fetch('/api/endpoint');
  if (!response.ok) {
    const data = await response.json();
    throw new Error(data.error || 'Request failed');
  }
  const data = await response.json();
  // Handle success
} catch (err) {
  setError(err instanceof Error ? err.message : 'An error occurred');
}

// Display error
{error && (
  <div className="text-red-600 dark:text-red-400">
    {error}
  </div>
)}
```

### Server Components

```typescript
try {
  const data = await fetchData();
  return <Component data={data} />;
} catch (error) {
  console.error('Error:', error);
  return <ErrorComponent message="Failed to load data" />;
}
```

---

## Where to Put New Code

### Adding a New Feature

1. **Component**: Create in `/components/FeatureName.tsx`
2. **API Route**: Create in `/app/api/feature/route.ts`
3. **Page**: Create in `/app/feature/page.tsx`
4. **Types**: Add to `/lib/api-types.ts` or `/lib/types.ts`
5. **Utilities**: Create in `/lib/feature-helper.ts`
6. **Tests**: Create in `/__tests__/[matching-path]/`
7. **Stories**: Create in `/components/FeatureName.stories.tsx`

### Modifying Existing Features

1. **Check existing patterns** in similar features
2. **Update JSDoc comments** when changing behavior
3. **Update related tests** in `__tests__`
4. **Update related documentation** - Update comments, README files, and relevant docs in `docs/`

### Utility Functions

**Create new utility file** when:

- Function is used by 3+ different components/routes
- Logic is complex enough to test independently
- Function has no component-specific dependencies

**Keep inline** when:

- Function is used in only 1-2 places
- Logic is simple (< 10 lines)
- Function is tightly coupled to component

---

## Code Style

### TypeScript

- **Use explicit types** for function parameters and return values
- **Use interfaces** for object shapes that might be extended
- **Use types** for unions, intersections, or mapped types
- **Avoid `any`** - use `unknown` if type is truly unknown

```typescript
// Good
interface UserData {
  id: string;
  name: string;
  email: string;
}

async function getUser(id: string): Promise<UserData | null> {
  // Implementation
}

// Avoid
async function getUser(id: any): Promise<any> {
  // Implementation
}
```

### Async/Await

- **Prefer async/await** over `.then()` chains
- **Use Promise.all()** for parallel operations
- **Handle errors** with try/catch

```typescript
// Good - parallel fetches
const [books, progress] = await Promise.all([fetchBooks(), fetchProgress()]);

// Avoid - sequential when parallel is possible
const books = await fetchBooks();
const progress = await fetchProgress(); // Waits unnecessarily
```

### Tailwind CSS

- **Use dark mode variants**: `dark:bg-gray-800`
- **Group by purpose**: positioning → sizing → colors
- **Use custom classes** for repeated patterns (in globals.css)

```typescript
// Good organization
<div className="flex items-center justify-between p-4 bg-white dark:bg-gray-800 rounded-lg shadow-md">

// Avoid random order
<div className="shadow-md rounded-lg dark:bg-gray-800 flex bg-white items-center p-4 justify-between">
```

---

## Testing Patterns

### Component Tests

```typescript
import { render, screen } from '@testing-library/react';
import Component from '@/components/Component';

describe('Component', () => {
  it('renders with props', () => {
    render(<Component prop="value" />);
    expect(screen.getByText('value')).toBeInTheDocument();
  });

  it('handles user interaction', async () => {
    const handleClick = jest.fn();
    render(<Component onClick={handleClick} />);

    await userEvent.click(screen.getByRole('button'));
    expect(handleClick).toHaveBeenCalled();
  });
});
```

### API Route Tests

```typescript
import { GET } from '@/app/api/endpoint/route';
import { NextRequest } from 'next/server';

jest.mock('next-auth', () => ({
  getServerSession: jest.fn(() => ({
    user: { id: 'user-123', email: 'test@example.com' },
  })),
}));

describe('GET /api/endpoint', () => {
  it('returns data for authenticated user', async () => {
    const request = new NextRequest('http://localhost:3000/api/endpoint');
    const response = await GET(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toHaveProperty('expectedField');
  });
});
```

---

## Performance Considerations

### Server Components

- Default to server components (no 'use client')
- Fetch data close to where it's used
- Use streaming with Suspense boundaries for slow queries

### Client Components

- Only use 'use client' when needed (interactivity, hooks)
- Memoize expensive calculations with `useMemo`
- Debounce rapid user input (search, resize)

### Images

- Use Next.js `<Image>` component for optimization
- Specify appropriate `sizes` for responsive images
- Use `priority` for above-the-fold images

---

## Related Documentation

- [Code Map](code-map.md) - Feature relationships
- [Architecture](architecture.md) - System design
- [Testing](testing.md) - Test commands and patterns
