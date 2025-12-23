# PR: Add Dark Mode Support

## Overview

Adds dark mode support to Book Vault with a theme toggle in the header.

## Changes

### New Features

- 🌙 Theme toggle button in top right of header with sun/moon icons
- 🎨 Full dark mode support across all pages and components
- 💾 Theme preference persists using next-themes library
- 🖥️ Respects system theme preference by default

### New Components

- **ThemeProvider** (`components/ThemeProvider.tsx`): Wrapper for next-themes provider
- **ThemeToggle** (`components/ThemeToggle.tsx`): Interactive toggle button with sun/moon icons

### Components Updated

- **Home page** (`app/page.tsx`): Dark backgrounds, navigation buttons, headings
- **BookCard** (`components/BookCard.tsx`): Card backgrounds, text colors for all metadata
- **SearchBar** (`components/SearchBar.tsx`): Input field, placeholder, background colors
- **Pagination** (`components/Pagination.tsx`): Borders, buttons, text colors, ellipsis
- **SortDropdown** (`components/SortDropdown.tsx`): Label and select dropdown styling
- **Header** (`app/layout.tsx`): Background, text colors, flex layout for toggle placement

### Technical Details

- Added `next-themes` package for theme management
- Enabled Tailwind dark mode with `class` strategy in `tailwind.config.ts`
- Fixed TypeScript interface for `FFProbeFormat` in audio metadata
- All dark mode styles use Tailwind's `dark:` prefix
- Theme toggle includes hydration mismatch protection with `suppressHydrationWarning`

## Testing

- ✅ Build completes successfully
- ✅ All components render correctly in light mode
- ✅ All components render correctly in dark mode
- ✅ Theme toggle switches between light/dark modes
- ✅ Theme preference persists across page reloads
- ✅ System preference detection works correctly

## Implementation Details

### Theme Toggle

Located in top right of header, shows:

- 🌙 Moon icon in light mode (click to switch to dark)
- ☀️ Sun icon in dark mode (click to switch to light)

### Color Palette

Dark mode uses:

- Background: `dark:bg-gray-950` (main), `dark:bg-gray-900` (header), `dark:bg-gray-800` (cards)
- Text: `dark:text-white` (primary), `dark:text-gray-300` (secondary), `dark:text-gray-400` (tertiary)
- Borders: `dark:border-gray-700`
- Hover states: `dark:hover:bg-gray-700`, `dark:hover:text-blue-400`

### Package Dependencies

```json
{
  "next-themes": "^0.4.4"
}
```

## Files Changed

- `app/layout.tsx` (MODIFIED) - Added ThemeProvider wrapper and ThemeToggle
- `app/page.tsx` (MODIFIED) - Dark mode styles for home page
- `components/BookCard.tsx` (MODIFIED) - Dark mode styles for book cards
- `components/Pagination.tsx` (MODIFIED) - Dark mode styles for pagination
- `components/SearchBar.tsx` (MODIFIED) - Dark mode styles for search input
- `components/SortDropdown.tsx` (MODIFIED) - Dark mode styles for dropdown
- `components/ThemeProvider.tsx` (NEW) - Theme provider wrapper
- `components/ThemeToggle.tsx` (NEW) - Theme toggle button component
- `tailwind.config.ts` (MODIFIED) - Enabled dark mode with class strategy
- `lib/audio-metadata.ts` (MODIFIED) - Fixed TypeScript interface
- `package.json` (MODIFIED) - Added next-themes dependency

## PR Link

Create PR at: https://github.com/dlionikis/book_vault/compare/main...feature/dark-mode
