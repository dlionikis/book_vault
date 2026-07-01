# Architectural Decision Records

> Key technology choices and design decisions with rationale and consequences.

**Last Updated**: January 6, 2026

---

## ADR-001: Next.js 14 with App Router

**Date**: Initial project setup (2024)

**Context**:
Needed a modern React framework for building a full-stack audiobook library application with server-side rendering, API routes, and good developer experience.

**Decision**:
Use Next.js 14 with the App Router architecture.

**Rationale**:

- **Server Components**: Default server-side rendering reduces client bundle size
- **File-based routing**: Intuitive routing structure in `/app` directory
- **API Routes**: Built-in API support eliminates need for separate backend
- **Image optimization**: Automatic image optimization with `<Image>` component
- **Streaming**: React 18 streaming for better UX with slow queries
- **TypeScript support**: First-class TypeScript integration
- **Production ready**: Battle-tested framework with strong ecosystem

**Consequences**:

- ✅ Simplified deployment (single application)
- ✅ Fast development with hot module replacement
- ✅ Excellent performance with server components
- ⚠️ Learning curve for App Router vs Pages Router
- ⚠️ Some third-party libraries not yet compatible with Server Components

**Status**: Active

---

## ADR-002: Prisma ORM for Database Access

**Date**: Initial project setup (2024)

**Context**:
Needed a type-safe way to interact with PostgreSQL database for storing audiobook metadata, user data, and progress tracking.

**Decision**:
Use Prisma as the ORM layer.

**Rationale**:

- **Type safety**: Auto-generated TypeScript types from schema
- **Developer experience**: Intuitive query API with autocomplete
- **Migrations**: Built-in migration system with version control
- **Schema-first**: Single source of truth in `schema.prisma`
- **Relation management**: Handles complex many-to-many relationships well
- **Studio**: Visual database browser for debugging
- **Connection pooling**: Efficient connection management

**Consequences**:

- ✅ Eliminated entire class of type errors at compile time
- ✅ Fast development with generated types
- ✅ Easy database migrations with `prisma migrate`
- ⚠️ Additional build step (prisma generate)
- ⚠️ Learning curve for Prisma query syntax
- ⚠️ Connection limit considerations in serverless environments

**Status**: Active

---

## ADR-003: Dual Authentication (Session + JWT)

**Date**: Mobile app planning (Q4 2024)

**Context**:
Initially built with NextAuth session-based authentication for web. Needed to support iOS mobile app with token-based auth while maintaining web compatibility.

**Decision**:
Implement dual authentication support: NextAuth sessions for web, JWT tokens for mobile.

**Rationale**:

- **Web**: Session cookies provide security and automatic refresh
- **Mobile**: JWT tokens work better in native apps (no cookie management)
- **Flexibility**: Can support both web and mobile from same API
- **Gradual migration**: Can add mobile without breaking web
- **Standards**: JWT is industry standard for mobile authentication

**Consequences**:

- ✅ Single API supports both web and mobile clients
- ✅ Each platform uses appropriate auth method
- ✅ Mobile apps can work offline with cached tokens
- ⚠️ More complex auth logic in API routes (check both methods)
- ⚠️ Two token management systems to maintain
- ⚠️ Need to keep both systems in sync for security updates

**Implementation**:

- Web: NextAuth with credentials provider
- Mobile: JWT access tokens (15min) + refresh tokens (7 days)
- Helper: `getAuthUserFromRequest()` checks both methods

**Status**: Active

---

## ADR-004: S3 for Production Media Storage

**Date**: Production deployment planning (Q4 2024)

**Context**:
Audiobook files and cover images are large (100MB-1GB per book). Local filesystem works in development but doesn't scale in containerized production environments.

**Decision**:
Use AWS S3 for media storage in production, local filesystem in development.

**Rationale**:

- **Scalability**: S3 can handle unlimited storage
- **Cost**: Pay only for storage used (~$0.023/GB/month)
- **Performance**: CloudFront CDN integration for fast global access
- **Durability**: 99.999999999% durability (11 nines)
- **Security**: Presigned URLs for time-limited access control
- **Container-friendly**: No local storage needed in containers

**Consequences**:

- ✅ Production can scale to thousands of books
- ✅ Fast media delivery via CDN
- ✅ No storage limits on ECS Fargate
- ⚠️ Additional AWS service to manage
- ⚠️ Local development needs file mounts
- ⚠️ Presigned URLs expire (requires refresh logic)
- 💰 Ongoing S3 storage costs

**Implementation**:

- Environment variable `AWS_S3_BUCKET` controls S3 vs local
- `lib/media.ts` abstracts URL generation
- `lib/s3.ts` handles streaming and presigned URLs
- 1-hour expiry on presigned URLs (configurable)

**Status**: Active

---

## ADR-005: OpenAPI-First API Design

**Date**: iOS development kickoff (Q4 2024)

**Context**:
Building iOS app requires clear API contract. Manual API documentation gets stale quickly. Need type safety for both TypeScript and Swift clients.

**Decision**:
Define APIs in OpenAPI 3.0 spec, generate TypeScript and Swift types, validate with contract tests.

**Rationale**:

- **Single source of truth**: OpenAPI spec defines exact API contract
- **Type generation**: Auto-generate client types for TS and Swift
- **Documentation**: Auto-generate API docs with Redocly
- **Validation**: Contract tests catch drift between spec and implementation
- **Tooling**: Industry-standard format with excellent tool support
- **Client generation**: Could auto-generate client SDKs if needed

**Consequences**:

- ✅ API changes require spec update (prevents drift)
- ✅ Both web and iOS use same validated types
- ✅ Automated validation in CI/CD pipeline
- ✅ Beautiful API documentation for free
- ⚠️ Extra work to keep spec in sync
- ⚠️ Build-time code generation step required
- ⚠️ Learning curve for OpenAPI syntax

**Workflow**:

1. Update `docs/api/openapi.yaml`
2. Run `npm run api:generate` (TS + Swift types)
3. Contract tests validate implementation matches spec
4. CI fails if spec and implementation drift

**Status**: Active

---

## ADR-006: Tailwind CSS for Styling

**Date**: Initial project setup (2024)

**Context**:
Needed styling solution that works well with React, provides consistency, supports dark mode, and doesn't require separate CSS files.

**Decision**:
Use Tailwind CSS utility-first framework.

**Rationale**:

- **Utility-first**: Build layouts without leaving JSX
- **Consistency**: Predefined spacing/color scales prevent ad-hoc values
- **Dark mode**: Built-in dark mode support with `dark:` prefix
- **Performance**: Only ships CSS that's actually used (tree-shaking)
- **Responsive**: Intuitive responsive prefixes (`sm:`, `lg:`, etc.)
- **No naming**: Eliminates bikeshedding over class names
- **Ecosystem**: Huge plugin ecosystem (forms, typography, etc.)

**Consequences**:

- ✅ Rapid UI development
- ✅ Consistent design system
- ✅ Small production CSS bundles
- ✅ Built-in dark mode that "just works"
- ⚠️ Long className strings in JSX
- ⚠️ Learning curve for utility classes
- ⚠️ Can be verbose for complex components

**Configuration**:

- Custom colors for brand identity
- Custom font family (system fonts)
- Custom container max-widths
- Dark mode: `class` strategy (user-controlled)

**Status**: Active

---

## ADR-007: Storybook for Component Development

**Date**: Component library expansion (Q4 2024)

**Context**:
Building reusable components for web. Need way to develop and test components in isolation.

**Decision**:
Use Storybook for component development and documentation.

**Rationale**:

- **Isolation**: Develop components without running full app
- **Documentation**: Visual documentation for component library
- **Testing**: Test different props/states easily
- **Design handoff**: Designers can see all component variations
- **Reusability**: Encourages building truly reusable components
- **Accessibility**: Built-in a11y testing addon

**Consequences**:

- ✅ Faster component development
- ✅ Better component reusability
- ✅ Living component documentation
- ✅ Easier QA (view all states at once)
- ⚠️ Additional maintenance (keep stories updated)
- ⚠️ Another build process to manage

**Coverage**:
Currently have stories for:

- AudioPlayer, BookCard, BookGrid, ChapterList
- ContinueListening, Pagination, ProgressBadge
- BackButton, SearchBar, ThemeToggle

**Status**: Active

---

## ADR-008: Server-Side Audio Streaming

**Date**: Initial audio playback implementation (2024)

**Context**:
Need to serve large audio files (100MB-1GB) to browser for playback. Direct S3 links would expose storage URLs.

**Decision**:
Stream audio through API route with range request support.

**Rationale**:

- **Security**: Hides actual storage location (S3 or local)
- **Authorization**: Verify user authentication before streaming
- **Range requests**: Support seeking without downloading entire file
- **Flexibility**: Can switch between S3/local without client changes
- **Caching**: Can add caching layer in future
- **Analytics**: Can track playback in future

**Consequences**:

- ✅ User auth required for audio access
- ✅ Works with both S3 and local storage
- ✅ Efficient seeking with HTTP range requests
- ⚠️ Server bandwidth usage (vs direct S3 links)
- ⚠️ Additional latency vs direct S3 access
- ⚠️ Need to handle large file streaming efficiently

**Implementation**:

- Route: `/api/audio/[...path]`
- Supports `Range` headers for seeking
- Validates user authentication
- Streams from S3 or local filesystem
- Returns appropriate `Content-Type` and `Content-Length`

**Status**: Active

---

## ADR-009: Automatic Progress Tracking

**Date**: Progress tracking feature (Q3 2024)

**Context**:
Users need to resume audiobooks where they left off. Manual "mark as finished" is tedious.

**Decision**:
Auto-save playback position every 10 seconds, auto-complete at >95% progress.

**Rationale**:

- **User experience**: Seamless resume without user action
- **Completion detection**: Automatically mark books finished
- **No manual work**: Users don't need to remember to save
- **Cross-device**: Resume on any device
- **Privacy**: Progress stored per user

**Consequences**:

- ✅ Excellent user experience (just works)
- ✅ Accurate "Continue Listening" feature
- ✅ No manual progress management needed
- ⚠️ API calls during playback (rate limited)
- ⚠️ 10-second auto-save may lose some progress
- ⚠️ 95% threshold may complete before actual end

**Implementation**:

- POST /api/progress every 10 seconds while playing
- Rate limited to 100 requests/minute per user
- Auto-complete when position > 95% of runtime
- Save on pause and unmount
- Skip save if position hasn't changed by >5 seconds

**Tuning**:

- 10-second interval balances accuracy vs API load
- 95% threshold catches nearly-finished books
- 5-second change threshold prevents redundant saves

**Status**: Active

---

## ADR-010: Type-Safe API with Zod Validation

**Date**: API security hardening (Q4 2024)

**Context**:
TypeScript types are compile-time only. Need runtime validation to prevent invalid data from reaching database.

**Decision**:
Use Zod schemas for runtime validation of API inputs, transform to TypeScript types.

**Rationale**:

- **Runtime safety**: Validate data at API boundary
- **Type inference**: Generate TypeScript types from Zod schemas
- **Detailed errors**: Zod provides helpful validation error messages
- **Transformation**: Can transform/sanitize data during validation
- **Single source**: Schema definition also generates types
- **Composable**: Build complex schemas from simple ones

**Consequences**:

- ✅ Prevents invalid data from reaching database
- ✅ Clear error messages for API consumers
- ✅ Type safety at both compile and runtime
- ⚠️ Additional validation code in routes
- ⚠️ Learning curve for Zod syntax
- ⚠️ Performance overhead (minimal in practice)

**Pattern**:

```typescript
// Define schema
const schema = z.object({
  bookId: z.string().uuid(),
  positionSeconds: z.number().int().min(0),
});

// Validate and transform
const validated = schema.parse(await request.json());
// validated is now typed as { bookId: string, positionSeconds: number }
```

**Status**: Active

---

## Related Documentation

- [Architecture Overview](architecture.md) - System design and components
- [Code Map](code-map.md) - How features connect
- [Conventions](conventions.md) - Coding standards
- [Data Flows](data-flows.md) - Request/response patterns
