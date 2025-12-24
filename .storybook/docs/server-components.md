# Server Component Story Patterns

Server Components cannot render in Storybook (client-side environment). This document outlines strategies for handling Server Components in stories.

## The Challenge

Next.js App Router introduces Server Components by default. These components:

- Run only on the server
- Cannot use React hooks (useState, useEffect, etc.)
- Cannot access browser APIs
- Cannot be imported into client-side environments (like Storybook)

## Solutions

### Option 1: Extract Client Logic (Recommended)

Move interactive parts to separate Client Components:

**Example**:

```tsx
// BookCard.tsx (Server Component)
export function BookCard({ book }: BookCardProps) {
  return (
    <div>
      <BookCardClient book={book} />
    </div>
  );
}

// BookCardClient.tsx ('use client')
('use client');
export function BookCardClient({ book }: BookCardProps) {
  // Interactive logic here
}
```

Then create stories for `BookCardClient.tsx` only.

### Option 2: Mock as Client Component

Create a story-only client version with the same props interface:

**Example**:

```tsx
// BookCard.stories.tsx
'use client';
import type { BookCardProps } from './BookCard';

// Mock client version for Storybook only
function BookCardMock(props: BookCardProps) {
  // Simplified client implementation
}

export default {
  component: BookCardMock,
  // ...
};
```

### Option 3: Skip Stories

For components that are purely server-side (no UI logic worth testing in isolation):

- Document in README instead
- Add integration tests in Jest
- Focus Storybook on reusable UI components

## Component Classification

### Already Client Components ✅

These can have stories directly:

- `AudioPlayer.tsx` - Uses audio element state
- `PlaybackClient.tsx` - Manages playback state
- `SearchBar.tsx` - Form input with debouncing
- `ThemeToggle.tsx` - Theme switching
- `AddToLibraryButton.tsx` - Button interactions
- `ContinueListeningButton.tsx` - Navigation
- `UserMenu.tsx` - Dropdown state

### Likely Client Components (Check for 'use client')

May already be client components or need to be:

- `BookCard.tsx` - Check if it has interactive elements
- `Pagination.tsx` - Check if it manages page state
- `SortDropdown.tsx` - Dropdown likely needs client state

### Pure Server Components

These don't need stories (no UI logic to test):

- Page components (`app/*/page.tsx`)
- Layout components (`app/*/layout.tsx`)
- Server-side data fetching utilities

## Best Practices

1. **Prefer Option 1**: Separating client logic makes components more testable and reusable
2. **Use Mock Data**: Import from `.storybook/mocks/` for consistent test data
3. **Document Server Props**: If a component needs server-fetched data, document the expected shape in stories
4. **Focus on UI**: Storybook is for visual component testing, not business logic

## Examples in This Project

### PlaybackClient (Already Client Component)

```tsx
// components/PlaybackClient.tsx
'use client';

export default function PlaybackClient({ book, audioUrl }: Props) {
  // Can create stories directly
}
```

### BookCard (Check Implementation)

If `BookCard` is a Server Component but needs interactivity:

- Extract click handlers to `BookCardClient`
- Keep server-side data fetching in `BookCard`
- Create stories for `BookCardClient` only

## When in Doubt

Ask: "Does this component use hooks or browser APIs?"

- **Yes** → Mark as 'use client', create stories
- **No** → Keep as Server Component, skip stories or use Option 2
