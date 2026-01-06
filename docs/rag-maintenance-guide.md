# RAG Maintenance Guide

**Purpose**: Instructions for AI assistants to maintain documentation as code evolves.

**Audience**: Future AI assistants (Claude, etc.) helping with this codebase.

---

## When to Update Documentation

### Automatic Triggers

When you (AI assistant) are asked to or complete any of these actions, **automatically update relevant documentation**:

#### New Features

- ✅ **Added a component** → Update `components/README.md`
- ✅ **Added an API route** → Update `app/api/README.md`
- ✅ **Added a utility function** → Update `lib/README.md`
- ✅ **Changed data flow** → Update `docs/data-flows.md` and `docs/code-map.md`
- ✅ **Made architectural decision** → Add entry to `docs/decisions.md`

#### File Changes

- ✅ **Moved/renamed files** → Update all README indexes
- ✅ **Refactored major component** → Update JSDoc and `docs/code-map.md`
- ✅ **Changed API contract** → Update route JSDoc and `app/api/README.md`
- ✅ **Added new pattern** → Document in `docs/conventions.md`

#### Bulk Changes

- ✅ **Migration or major refactor** → Review and update all Phase 1 documentation
- ✅ **New developer onboarding feedback** → Update `docs/conventions.md`

---

## User Phrases That Trigger Updates

If the user says any of these, update docs **before confirming task completion**:

- "Let's add a new [component/API/feature]..."
- "Refactor the [component/system]..."
- "Move [file] to [location]..."
- "Change how [feature] works..."
- "Why did we decide to [architectural choice]?"
- "We're doing a major update to..."

---

## Update Checklist

When updating documentation, follow this checklist:

### For New Components

- [ ] Add entry to `components/README.md` with one-line description
- [ ] Add JSDoc to component with props, purpose, example
- [ ] Update `docs/code-map.md` if component calls APIs or manages state
- [ ] Update `docs/data-flows.md` if component is part of a user flow

### For New API Routes

- [ ] Add entry to `app/api/README.md` with method and purpose
- [ ] Add route-level JSDoc with auth requirements and response format
- [ ] Update `docs/code-map.md` with database models accessed
- [ ] Update `docs/api-quick-ref.md` if it exists

### For New Utilities

- [ ] Add entry to `lib/README.md`
- [ ] Add comprehensive JSDoc with params, returns, examples
- [ ] Update `docs/code-map.md` if utility is called from multiple features

### For Architectural Changes

- [ ] Add decision to `docs/decisions.md` with context and rationale
- [ ] Update affected sections in `docs/code-map.md`
- [ ] Update `docs/data-flows.md` if flows changed
- [ ] Update `docs/architecture.md` if major system design changed

### For New Patterns/Conventions

- [ ] Document pattern in `docs/conventions.md`
- [ ] Add example of good implementation
- [ ] Note which existing code follows this pattern

---

## Documentation Standards

### JSDoc Template for Components

```typescript
/**
 * [One-line description of what component does]
 *
 * [Detailed description including:
 *  - Main responsibility
 *  - State management approach
 *  - Side effects (API calls, etc.)
 *  - Important behaviors]
 *
 * @param propName - Description of prop and its purpose
 * @param anotherProp - Description
 * @returns Description of what is rendered
 *
 * @example
 * <ComponentName
 *   prop1={value}
 *   prop2={otherValue}
 * />
 */
```

### JSDoc Template for API Routes

```typescript
/**
 * [METHOD] /api/full/path
 *
 * [Purpose and main behavior]
 * [Any important side effects]
 *
 * Auth: Required | Optional | Public
 * Request: [Description of query params, body, headers]
 * Returns: [Response structure and status codes]
 * Errors: [Common error scenarios]
 *
 * @example
 * // Request example
 * fetch('/api/books/123', {
 *   headers: { Authorization: 'Bearer token' }
 * })
 */
```

### JSDoc Template for Utility Functions

```typescript
/**
 * [One-line description of function purpose]
 *
 * [Detailed description including:
 *  - Algorithm or approach
 *  - Edge cases handled
 *  - Performance considerations]
 *
 * @param paramName - Description and valid values/types
 * @param optionalParam - Description (optional)
 * @returns Description of return value and shape
 * @throws Error type and when it's thrown
 *
 * @example
 * const result = functionName(arg1, arg2);
 * // result is ...
 */
```

### Component README Entry Format

```markdown
- **ComponentName** - One-line description. Key props: `prop1`, `prop2`. Used in: feature context.
```

### API README Entry Format

```markdown
- `METHOD /api/path` - Purpose. Auth: Required/Optional. Returns: brief description.
```

### Code Map Entry Format

```markdown
## Feature: Feature Name

**User Flow**: High-level user action
**Components**:

- ComponentName.tsx → Responsibility
- AnotherComponent.tsx → Responsibility
  **APIs**:
- METHOD /api/path → What it does
  **Database**:
- ModelName → What's stored/retrieved
  **Files**:
- lib/utility.ts → Specific function used
```

---

## Proactive Documentation

### When Writing New Code

As you generate new code, **simultaneously generate its documentation**:

1. **Write the component** → Immediately add JSDoc
2. **Create the API route** → Immediately add route documentation
3. **Add utility function** → Immediately add comprehensive JSDoc

Don't wait to be asked - documentation is part of the deliverable.

### Multi-File Updates

When making changes across multiple files, use `multi_replace_string_in_file` to update:

- The code files
- The README indexes
- The relevant docs/ files

All in a single operation.

---

## Quality Checklist

Before marking documentation updates complete, verify:

- [ ] JSDoc includes all required sections (description, params, returns, example)
- [ ] Examples are realistic and copy-paste ready
- [ ] README indexes are alphabetically or logically ordered
- [ ] Links between docs are valid and use relative paths
- [ ] No stale information (removed code referenced)
- [ ] Terminology is consistent across all docs

---

## How to Use This Guide

### For AI Assistants (You!)

**At start of conversation**:

1. Read `docs/INDEX.md` for overall structure
2. Check `docs/STATUS.md` for recent changes
3. Reference this guide when making code changes

**During work**:

1. Before confirming task completion, check trigger conditions
2. Update relevant documentation automatically
3. Mention documentation updates in your response

**For complex changes**:

1. Create todo list including documentation steps
2. Mark documentation updates as separate tasks
3. Complete before marking feature complete

### For Humans

**When asking AI to add features**:

1. Don't worry about reminding AI to update docs
2. If docs seem stale, reference this guide: "Please follow the RAG maintenance guide to update documentation"
3. Review AI-generated docs for accuracy

**Monthly review**:

1. Check that README indexes match actual files
2. Verify JSDoc examples still work
3. Update `docs/STATUS.md` with current state

---

## Special Cases

### Experimental Code

- Add `@experimental` tag to JSDoc
- Note in `docs/STATUS.md` under "Experimental Features"
- Don't add to README indexes yet

### Deprecated Code

- Add `@deprecated` tag to JSDoc with reason
- Keep in README indexes with "(deprecated)" suffix
- Add entry to `docs/decisions.md` explaining deprecation

### Generated Code

- Add `@generated` tag to JSDoc
- Link to generator source in comment
- Don't manually edit - update generator instead

---

## Examples of Good Maintenance

### Example 1: Adding a New Component

**Code change**: Created `components/RatingBadge.tsx`

**Documentation updates**:

1. Added to `components/README.md`:

   ```markdown
   - **RatingBadge** - Displays book rating with stars. Props: `rating` (1-5), `size`. Used in: BookCard, BookDetail.
   ```

2. Added JSDoc to component:

   ```typescript
   /**
    * Displays a book rating as a visual star indicator
    *
    * Renders 1-5 stars based on rating value. Supports responsive sizing
    * and theme-aware colors. Half-stars not supported.
    *
    * @param rating - Numeric rating between 1 and 5
    * @param size - Visual size: 'sm', 'md', 'lg'
    * @returns Star rating display component
    *
    * @example
    * <RatingBadge rating={4.5} size="md" />
    */
   ```

3. Updated `docs/code-map.md`:

   ```markdown
   ## Feature: Book Display

   **Components**:

   - BookCard.tsx → Shows book with cover, uses RatingBadge
   - RatingBadge.tsx → Renders star rating
   ```

### Example 2: Refactoring API Route

**Code change**: Split `app/api/books/route.ts` into separate files for GET/POST

**Documentation updates**:

1. Updated `app/api/README.md`:

   ```markdown
   - `GET /api/books` - List books with filters → books/list/route.ts
   - `POST /api/books` - Create new book → books/create/route.ts
   ```

2. Updated route JSDoc in new files

3. Added decision to `docs/decisions.md`:

   ```markdown
   ## ADR-012: Split API Routes by HTTP Method

   **Date**: January 6, 2026
   **Decision**: Separate GET/POST/PUT/DELETE into individual route.ts files
   **Rationale**: Improves code organization, makes testing easier
   ```

---

## Questions?

If you encounter a situation not covered by this guide:

1. Use best judgment based on the spirit of these guidelines
2. Document your decision in `docs/decisions.md`
3. Update this guide with the new pattern

**This guide should evolve with the project.**
