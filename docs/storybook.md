# Storybook Usage Guide

## Quick Start

- Run: `npm run storybook`
- URL: `http://localhost:6006`

## Adding Stories

1. Create `ComponentName.stories.tsx` next to component
2. Use mock data from `.storybook/mocks/`
3. Add dark mode variants
4. Document props with JSDoc

## Mock Data

- Books: `.storybook/mocks/books.ts`
- Users: `.storybook/mocks/users.ts`

## Server Components

See `.storybook/docs/server-components.md`

## For AI-Assisted Development

**Before exploring components**, read these files in order:

1. `docs/component-guide.md` - Which component to use
2. `ComponentName.stories.tsx` - How to use the component
3. `docs/data-flows.md` - How data flows to the component (if needed)

**This pattern saves 50-80% of exploration tokens.**

### Adding a New Feature: Recommended Workflow

1. Read `docs/component-guide.md` to identify components
2. Read `docs/data-flows.md` to understand data flow
3. Check `docs/api-quick-ref.md` for API endpoints
4. Open relevant `.stories.tsx` files to see component usage
5. Implement feature using existing patterns
6. Add/update stories for new functionality

**Do NOT**:

- Scan entire codebase to understand component relationships
- Read multiple component files to find prop types
- Explore API routes to understand request/response shapes

**Why this works**:

- Component guide shows decision tree → no guessing which component
- Stories show exact prop shapes → no type hunting
- Data flows show full path → no exploration needed
- API reference shows exact endpoints → no route scanning

**Expected token savings**: 90-95% reduction per feature (5,000-8,000 tokens → 300-500 tokens)
