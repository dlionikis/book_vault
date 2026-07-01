# Book Vault - Architecture Overview

**Last Updated**: December 29, 2025
**Status**: Production-ready (Web + iOS apps complete)

> **TL;DR (30 seconds)**
>
> - **Stack**: Next.js 14 (TypeScript) + PostgreSQL + Prisma ORM + S3/CloudFront
> - **Pattern**: API-first design (serves web + iOS app)
> - **Auth**: NextAuth.js with JWT tokens (mobile-compatible)
> - **Data**: 14 Prisma models with many-to-many relationships
> - **Media**: S3 streaming with range request support (AVPlayer-ready)
> - **Key principle**: Read-only access to Libation files, all data in database

---

## System Architecture

### High-Level Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   Web Browser   │         │   iOS App       │
│   (Frontend)    │         │   (Complete)    │
└────────┬────────┘         └────────┬────────┘
         │ HTTPS                     │ HTTPS
         └───────────┬───────────────┘
                     ▼
         ┌─────────────────┐
         │  Load Balancer  │
         │   (AWS ALB)     │
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐       ┌──────────────┐
         │  API Server     │◄─────►│   Database   │
         │  + Web App      │       │  (Metadata)  │
         │   (ECS/EC2)     │       └──────────────┘
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐
         │   File Storage  │
         │  (S3 or Local)  │
         │  Audio + Images │
         └─────────────────┘
```

---

## Quick Reference

### Core Technologies

- **Framework**: Next.js 14 (React + API Routes)
- **Language**: TypeScript (strict mode)
- **Database**: PostgreSQL 15 (via Docker, port 5433)
- **ORM**: Prisma 5.22
- **Auth**: NextAuth.js with JWT
- **Styling**: Tailwind CSS
- **Testing**: Jest + React Testing Library

### Project Structure

```
book_vault/
├── app/                  # Next.js pages & API routes
│   ├── api/             # RESTful JSON endpoints
│   ├── books/[id]/      # Book detail & playback
│   ├── browse/          # Browse pages
│   └── auth/            # Authentication pages
├── components/          # React components
├── lib/                 # Core utilities
│   ├── db.ts           # Prisma singleton
│   ├── auth.ts         # NextAuth config
│   ├── s3.ts           # S3 streaming
│   └── types.ts        # Shared types
├── prisma/             # Database schema
├── docs/               # Documentation
└── scripts/            # Utility scripts
```

---

## Key Architectural Decisions

### 1. API-First Design

**Decision**: All data access through RESTful JSON APIs

**Rationale**:

- Supports both web and future iOS app
- Clear separation of concerns
- Easy to test and document
- Mobile-ready from day one

**Implementation**: See [api-quick-ref.md](api-quick-ref.md) for endpoint reference

---

### 2. Prisma Singleton Pattern

**Decision**: Centralized Prisma Client at `lib/db.ts`

**Rationale**:

- Prevents connection pool exhaustion (critical for serverless)
- All 37+ files use the same pattern
- Required for AWS Lambda/ECS deployment

**Pattern**:

```typescript
// ❌ WRONG
const prisma = new PrismaClient();

// ✅ CORRECT
import { prisma } from '@/lib/db';
```

---

### 3. S3 Streaming with Range Requests

**Decision**: Support HTTP range requests for audio streaming

**Rationale**:

- iOS AVPlayer requires range request support for seeking
- Enables efficient streaming without buffering entire files
- Compatible with all modern players

**Implementation**: Audio streaming uses S3 presigned URLs with range request support

---

### 4. Read-Only Libation Access

**Decision**: Never modify source Libation files

**Rationale**:

- Preserve data integrity
- Libation is source of truth
- Import script can be re-run safely
- All user data stored in database

**Implementation**: Import script at `scripts/import-libation.ts`

---

## Core Workflows

### 1. Audio Playback Flow

```
User clicks "Play"
  → /books/[id]/play page loads (Server Component)
  → Fetches book + chapters from DB
  → <PlaybackClient> renders (Client Component)
  → Fetches user progress: GET /api/progress?bookId=...
  → <AudioPlayer> streams: GET /api/audio/[...path]
  → Auto-saves progress: POST /api/progress (every 10s)
  → Updates Media Session API (lock screen controls)
```

### 2. Import Workflow

```
Run: npm run import
  → Scans /Volumes/BeeDrive/Libation/
  → For each book folder:
    - Reads .metadata.json
    - Extracts authors, narrators, series, categories
    - Stores book, relationships in DB
    - Records cover/audio file paths
  → Reports success/errors
```

### 3. Search Flow

```
User types query
  → Debounced input (300ms)
  → GET /api/search?q=query&page=1
  → PostgreSQL full-text search
  → Returns: { results: Book[], pagination }
  → Renders <BookGrid> with results
```

---

## Mobile App Support

### iOS App Complete ✅

Native Swift + SwiftUI app with all 8 phases implemented:

1. ✅ Auth & Browsing
2. ✅ Audio Playback
3. ✅ Background Audio & Lock Screen
4. ✅ Progress Sync
5. ✅ Chapter Navigation
6. ✅ Search & Browse
7. ✅ Offline Downloads
8. ✅ Offline Mode

**See**: [mobile/architecture.md](mobile/architecture.md) for iOS maintenance docs

---

## Performance Targets

- **Page Load**: < 2s initial load
- **Search**: < 500ms for results
- **Audio Start**: < 1s to playback
- **API Response**: < 200ms for simple queries

**Achieved**:

- ✅ All targets met in development
- ✅ All tests passing
- ✅ No performance regressions

---

## Next Steps

**See**: [STATUS.md](STATUS.md) for current roadmap

---

## Related Docs

- [API Quick Reference](api-quick-ref.md) - Endpoint reference
- [Data Flows](data-flows.md) - How data moves through the app
- [Data Validation Overview](data-validation-overview.md) - Type safety architecture
- [Testing Guide](testing.md) - Test patterns
- [Mobile iOS](mobile/architecture.md) - iOS app architecture & patterns
- [AWS Deployment](aws-deployment-reference.md) - Infrastructure & deploy guide
