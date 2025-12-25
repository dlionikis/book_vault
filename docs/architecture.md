# Book Vault - Architecture & Technical Design

## Architecture Overview

This document outlines the technical architecture for the Book Vault audiobook library application.

## System Architecture

### High-Level Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   Web Browser   │         │   iOS App       │
│   (Frontend)    │         │   (Future)      │
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

## Technology Stack Recommendations

### JavaScript Stack (Recommended)

**Frontend**

- **Framework**: Next.js 14+ (React)
  - Server-side rendering for fast initial loads
  - API routes for backend logic
  - Built-in optimization
  - Great developer experience
  - **Mobile-ready**: API routes can serve both web and future iOS app

**Backend**

- **Runtime**: Node.js 20+
- **Framework**: Next.js API Routes (API-first design)
- **Language**: TypeScript
  - Type safety
  - Better tooling
  - Easier maintenance
  - Shared types can be used in future Swift/React Native client
- **API Design**: RESTful JSON API that serves both web and mobile clients

**Database**

- **Primary**: PostgreSQL (AWS RDS)
  - Robust full-text search
  - JSON support for metadata
  - ACID compliance
  - Proven scalability

**Storage**

- **Media**: AWS S3
  - Audio files
  - Cover images
- **CDN**: CloudFront for fast delivery

**Authentication**

- **Library**: NextAuth.js with JWT tokens (mobile-compatible)
- **Web**: Secure cookies for session management
- **Mobile**: JWT tokens in Authorization headers
- **Storage**: Database sessions + token refresh mechanism

**Search**

- **Engine**: PostgreSQL full-text search or Elasticsearch
  - Initially PostgreSQL (simpler)
  - Upgrade to Elasticsearch if needed

**Pros**:

- Modern, widely-supported stack
- Excellent ecosystem and tooling
- Great for AI-assisted development
- Single language (TypeScript) across stack
- Next.js handles many concerns out-of-the-box

**Cons**:

- Node.js can be memory-intensive for large file operations
- May need worker processes for background jobs

### Reasoning

1. **Unified Development**: Single TypeScript codebase
2. **AI-Friendly**: Well-documented, AI tools excel at JavaScript/TypeScript
3. **Fast Development**: Next.js handles routing, API, optimization
4. **AWS Integration**: Easy deployment via ECS or Amplify
5. **Strong Search**: PostgreSQL full-text search is sufficient
6. **Community**: Large community, extensive resources

## Data Architecture

### Database Schema (Prisma)

The application uses Prisma ORM with PostgreSQL. See [prisma/schema.prisma](../prisma/schema.prisma) for the complete schema.

**Core Models:**

- **User**: Authentication and user data
  - Relations: `progress[]`, `lists[]`

- **Book**: Audiobook metadata
  - Fields: `asin`, `title`, `description`, `publisherSummary`, `runtimeMinutes`, `releaseDate`, `publisher`, `coverUrl`, `audioUrl`, `metadata` (JSON)
  - Relations: `authors[]`, `narrators[]`, `series[]`, `categories[]`, `chapters[]`, `progress[]`
  - Indexes: `title`

- **Chapter**: Audiobook chapters (extracted from .cue files)
  - Fields: `chapterNumber`, `title`, `startTime`, `endTime`, `duration`
  - Relations: `book`
  - Unique constraint: `[bookId, chapterNumber]`

- **Author**, **Narrator**, **Series**: People and series metadata
  - Fields: `asin`, `name`/`title`
  - Relations: Many-to-many with Books

- **Category**: Hierarchical taxonomy
  - Fields: `name`, `parentId`, `level`
  - Self-referential: `parent`, `children[]`

**User Features:**

- **UserProgress**: Track playback position
  - Fields: `userId`, `bookId`, `positionSeconds`, `completed`, `lastPlayed`
  - Unique constraint: `[userId, bookId]`

- **UserList** & **UserListBook**: Custom user collections
  - User can create multiple lists (e.g., "Want to Listen", "Favorites")
  - Books can be added with custom ordering

**Join Tables:**

- `BookAuthor`, `BookNarrator`, `BookSeries`, `BookCategory` handle many-to-many relationships
- All use cascade deletes for data integrity

## Application Structure

### Directory Structure

```
book_vault/
├── .github/                    # GitHub Actions CI/CD
│   └── workflows/
├── public/                     # Static assets
├── app/                        # Next.js 14 app directory
│   ├── api/                   # API routes
│   │   ├── auth/
│   │   ├── audio/             # Audio streaming
│   │   ├── books/
│   │   ├── browse/
│   │   ├── images/            # Image serving
│   │   ├── library/           # User library management
│   │   ├── progress/          # Playback progress
│   │   ├── search/
│   │   └── user/
│   ├── auth/                  # Auth pages
│   │   ├── login/
│   │   └── register/
│   ├── books/[id]/            # Book detail & playback
│   │   ├── page.tsx
│   │   └── play/
│   ├── browse/                # Browse pages
│   │   ├── authors/
│   │   ├── series/
│   │   ├── narrators/
│   │   └── categories/
│   ├── authors/[id]/
│   ├── series/[id]/
│   ├── narrators/[id]/
│   ├── categories/[id]/
│   ├── library/               # User library page
│   ├── search/                # Search page
│   ├── settings/              # User settings
│   ├── layout.tsx
│   └── page.tsx
├── components/                # React components
│   ├── AudioPlayer.tsx
│   ├── BookCard.tsx
│   ├── BookGrid.tsx
│   ├── ChapterList.tsx
│   ├── PlaybackClient.tsx
│   ├── SearchBar.tsx
│   ├── ThemeToggle.tsx
│   └── ...
├── lib/                       # Core business logic
│   ├── auth.ts               # NextAuth configuration
│   ├── db.ts                 # Prisma singleton
│   ├── media.ts              # Media URL helpers
│   ├── s3.ts                 # S3 streaming
│   ├── types.ts              # TypeScript types
│   └── audio-metadata.ts     # Chapter extraction
├── prisma/                    # Database schema
│   └── schema.prisma
├── scripts/                   # Utility scripts
│   ├── import-libation.ts    # Import script
│   ├── seed-test-user.ts
│   └── create-user.ts
├── docs/                      # Documentation
├── .env.example
├── .gitignore
├── docker-compose.yml         # PostgreSQL container
├── next.config.js
├── package.json
├── tsconfig.json
└── README.md
```

## Key Components

### 1. Import/Indexing System

**Purpose**: Parse Libation directory and populate database

**Process**:

1. Scan `/Volumes/BeeDrive/Libation/` directory
2. For each folder:
   - Read `.metadata.json` file
   - Extract authors, narrators, series, categories
   - Store cover image URL (S3 or local path)
   - Store audio file URL (S3 or local path)
   - Insert/update database records
3. Handle duplicates and updates gracefully

**Implementation**: CLI script or admin API endpoint

### 2. Audio Streaming

**Approach**: Range-request support for seeking

```typescript
// Pseudo-code
export async function GET(request: Request) {
  const range = request.headers.get('range');
  const fileSize = await getFileSize(audioPath);

  if (range) {
    const [start, end] = parseRange(range, fileSize);
    return new Response(createReadStream(audioPath, { start, end }), {
      status: 206,
      headers: {
        'Content-Range': `bytes ${start}-${end}/${fileSize}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': end - start + 1,
        'Content-Type': 'audio/mpeg',
      },
    });
  }

  return streamFullFile(audioPath);
}
```

### 3. Search Implementation

**PostgreSQL Full-Text Search**:

```sql
SELECT
  b.*,
  ts_rank(to_tsvector('english', b.title || ' ' || b.description),
          to_tsquery('english', $1)) as rank
FROM books b
WHERE
  to_tsvector('english', b.title || ' ' || b.description)
  @@ to_tsquery('english', $1)
ORDER BY rank DESC
LIMIT 50;
```

**With Filters**:

```typescript
// Combine full-text search with joins for multi-faceted search
SELECT DISTINCT b.* FROM books b
LEFT JOIN book_authors ba ON b.id = ba.book_id
LEFT JOIN authors a ON ba.author_id = a.id
LEFT JOIN book_narrators bn ON b.id = bn.book_id
LEFT JOIN narrators n ON bn.narrator_id = n.id
WHERE
  to_tsvector('english', b.title || ' ' || b.description || ' ' ||
              a.name || ' ' || n.name) @@ to_tsquery('english', $1)
ORDER BY ts_rank(...) DESC;
```

### 4. Authentication

**NextAuth.js Configuration with JWT for Mobile**:

```typescript
// src/app/api/auth/[...nextauth]/route.ts
import NextAuth from 'next-auth';
import CredentialsProvider from 'next-auth/providers/credentials';

export const authOptions = {
  providers: [
    CredentialsProvider({
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        // Verify against database
        const user = await verifyUser(credentials);
        return user || null;
      },
    }),
  ],
  session: {
    strategy: 'jwt', // JWT for mobile compatibility
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  jwt: {
    secret: process.env.NEXTAUTH_SECRET,
  },
  // ... additional config
};
```

### 5. API Endpoints (Mobile-Ready)

**Core API routes (implemented):**

```typescript
// API structure
/api/
  auth/
    [...nextauth]          # NextAuth.js authentication
    register/              # User registration
  audio/[...path]/         # Stream audio files (range requests)
  images/[...path]/        # Serve cover images
  books/
    GET    /               # List books with pagination
    GET    /:id            # Get single book
    GET    /:id/chapters   # Get book chapters
  search/
    GET    /               # Full-text search
  browse/
    GET    /authors        # List all authors
    GET    /series         # List all series
    GET    /narrators      # List all narrators
    GET    /categories     # List all categories
  authors/:id              # Author detail & books
  series/:id               # Series detail & books
  narrators/:id            # Narrator detail & books
  categories/:id           # Category detail & books
  library/
    GET    /               # User's library (added books)
    POST   /               # Add book to library
    DELETE /:bookId        # Remove book from library
    GET    /check          # Check if book in library
    GET    /series/:seriesId  # Library books by series
  progress/
    GET    /               # Get user's progress (all or by bookId)
    POST   /               # Update playback position
  user/
    PUT    /password       # Change password
```

## AWS Deployment Architecture

### Infrastructure Components

1. **Compute**: ECS Fargate
   - Container-based deployment
   - Auto-scaling
   - Managed infrastructure

2. **Database**: RDS PostgreSQL
   - Multi-AZ for high availability
   - Automated backups
   - Read replicas if needed

3. **Storage**: S3
   - Bucket for audio files
   - Bucket for cover images
   - Lifecycle policies

4. **CDN**: CloudFront
   - Fast content delivery
   - HTTPS enforcement
   - Origin access identity for S3

5. **Load Balancer**: Application Load Balancer
   - SSL termination
   - Health checks
   - Path-based routing

6. **DNS**: Route 53
   - Domain management
   - Health checks

7. **Monitoring**: CloudWatch
   - Application logs
   - Performance metrics
   - Alarms

### Deployment Strategy

**Development**:

- Local Docker environment
- Local PostgreSQL
- Files on external drive

**Staging** (optional):

- Smaller ECS instance
- Smaller RDS instance
- Subset of data for testing

**Production**:

- ECS Fargate with auto-scaling
- RDS Multi-AZ
- Full data set on S3
- CloudFront distribution

## Security Considerations

1. **Authentication**
   - Bcrypt password hashing
   - Secure session management
   - HTTPS only

2. **API Security**
   - Rate limiting
   - CORS configuration
   - Input validation

3. **Data Protection**
   - Encrypted database (RDS encryption)
   - S3 encryption at rest
   - Secure environment variables

4. **Network Security**
   - VPC with private subnets
   - Security groups
   - WAF for additional protection

## Performance Optimization

1. **Caching**
   - Redis for session storage (optional)
   - CloudFront for static assets
   - Database query caching

2. **Database**
   - Proper indexes
   - Connection pooling
   - Query optimization

3. **Frontend**
   - Image optimization (Next.js Image)
   - Code splitting
   - Lazy loading
   - Service worker for offline (future)

## Monitoring & Observability

1. **Logging**
   - Application logs to CloudWatch
   - Error tracking (Sentry optional)
   - Audit logs for authentication

2. **Metrics**
   - Response times
   - Error rates
   - User activity
   - Resource utilization

3. **Alerts**
   - High error rates
   - Slow response times
   - Resource exhaustion

## Development Workflow

1. **Local Development**
   - Docker Compose for database
   - Next.js dev server
   - Access to Libation directory

2. **Testing**
   - Jest for unit tests
   - React Testing Library for component tests
   - 184+ tests passing

3. **CI/CD**
   - GitHub Actions
   - Automated tests on PR
   - Deploy on merge to main

## Mobile App Support

### Backend is Mobile-Ready ✅

The backend architecture is designed API-first for future mobile clients:

1. **RESTful JSON API**: All endpoints return JSON, consumable by any client
2. **JWT Authentication**: Mobile-friendly token-based auth (already implemented)
3. **Range Request Support**: HTTP range requests for iOS AVPlayer audio streaming
4. **S3 Streaming**: Images and audio served from S3 with proper headers
5. **CORS Configuration**: Ready for mobile app origins
6. **Pagination**: All list endpoints support efficient pagination
7. **Progress Sync**: User progress tracking with automatic position saving

### iOS App Plan

**Technology**: Native Swift + SwiftUI

**Status**: Planning complete, implementation post-deployment

**Full implementation details**: See [mobile-ios-plan.md](mobile-ios-plan.md) for:

- 8 phased implementation steps (Auth → Playback → Offline)
- Technical architecture and service patterns
- API integration examples
- Background audio and lock screen controls
- Testing strategy and App Store deployment

**Key iOS Features** (from plan):

- Native audio playback with AVPlayer
- Background audio and lock screen controls
- Chapter navigation with real-time highlighting
- Progress sync with backend
- Search and browse (authors, series, narrators, categories)
- Custom user lists (Want to Listen, Favorites)
- Offline downloads (optional phase)
- CarPlay integration (future)

## Next Steps

1. **Deploy to AWS** (next priority)
   - See "AWS Deployment Architecture" section above
   - Backend is production-ready with S3 streaming support

2. **iOS App Development** (post-deployment)
   - See [mobile-ios-plan.md](mobile-ios-plan.md) for full plan
   - Backend API is already mobile-ready

---

**Last Updated**: December 24, 2025
**Status**: Production-ready with S3 streaming support, mobile-ready API
**Version**: 2.1
