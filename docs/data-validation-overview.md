# Data Validation & Type Safety - Quick Overview

> **TL;DR**: OpenAPI is the single source of truth. TypeScript provides compile-time safety, Zod validates in contract tests, Prisma handles database types, and iOS uses auto-generated Swift models.

**For detailed explanations and examples**: See [data-validation-layers.md](data-validation-layers.md)

---

## How Everything Connects

```
┌─────────────────────────────────────────────────────────────────┐
│                    SINGLE SOURCE OF TRUTH                       │
│              docs/api/openapi.yaml (OpenAPI Spec)               │
└───────┬───────────────────┬─────────────────────┬───────────────┘
        │                   │                     │
        ▼                   ▼                     ▼
┌────────────────┐  ┌────────────────┐  ┌───────────────────────┐
│  TypeScript    │  │ Zod Schemas    │  │  Swift Generation     │
│  lib/api-types │  │ lib/api-       │  │  ios/.../Models/      │
│  .ts (auto)    │  │ schemas.ts     │  │  (auto-generated)     │
└───────┬────────┘  └────┬───────────┘  └──────────┬────────────┘
        │                │                         │
        │                ▼                         │
        │       ┌────────────────┐                 │
        │       │ Contract Tests │                 │
        │       │ (validates API)│                 │
        │       └────────────────┘                 │
        ▼                                          ▼
┌────────────────────────┐         ┌──────────────────────┐
│   Backend API Routes   │         │    iOS Application   │
│  app/api/**/route.ts   │◄────────┤  Swift API Client    │
└───────────┬────────────┘  HTTP   └──────────────────────┘
            │
            ▼
┌────────────────────────┐
│   Prisma ORM Layer     │
│  prisma/schema.prisma  │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│   PostgreSQL Database  │
└────────────────────────┘
```

---

## Validation Layers

| Layer          | File                      | What It Validates          | When        |
| -------------- | ------------------------- | -------------------------- | ----------- |
| **OpenAPI**    | `docs/api/openapi.yaml`   | API contract definition    | Design time |
| **TypeScript** | `lib/api-types.ts` (auto) | Compile-time type safety   | Build time  |
| **Zod**        | `lib/api-schemas.ts`      | Runtime structure in tests | Test time   |
| **Prisma**     | `prisma/schema.prisma`    | Database constraints       | Runtime     |
| **Swift**      | `ios/.../Models/` (auto)  | iOS type safety            | Build time  |

---

## Key Commands

```bash
# Regenerate types
npm run api:generate:ts      # TypeScript
npm run api:generate:swift   # Swift
npm run api:generate         # Both

# Validate contract
npm run test:contract        # Run contract tests
npm run api:check-drift      # Check if types are stale
```

---

## Adding a New Field

1. Update `docs/api/openapi.yaml` with new field
2. Run `npm run api:generate` (regenerates TypeScript + Swift)
3. Update Prisma schema if database storage needed
4. Run `npx prisma migrate dev` (updates database)
5. Update API route to include new field
6. Run `npm run test:contract` (verifies compliance)

---

## Why This Architecture?

- **Single source of truth**: OpenAPI spec defines the contract
- **Type safety everywhere**: Compile-time errors in TypeScript AND Swift
- **No manual sync**: Types auto-generate from spec
- **Contract enforcement**: CI fails if implementation drifts from spec

**Need more detail?** See [data-validation-layers.md](data-validation-layers.md) for full examples, request flows, and FAQs.
