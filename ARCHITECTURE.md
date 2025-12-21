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

### Option 1: Modern JavaScript Stack (Recommended)

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

---

### Option 2: Python Stack

**Frontend**: React + Vite
**Backend**: FastAPI
**Database**: PostgreSQL
**ORM**: SQLAlchemy

**Pros**:
- Excellent for data processing
- Great ML/AI integration if needed
- Fast API development with FastAPI
- Strong typing with Pydantic

**Cons**:
- Two languages to maintain
- Slightly more complex deployment

---

### Option 3: Go Stack

**Frontend**: React + Vite
**Backend**: Go (Gin or Fiber framework)
**Database**: PostgreSQL

**Pros**:
- Extremely fast and efficient
- Excellent for file streaming
- Small binary size
- Great concurrency

**Cons**:
- Smaller ecosystem
- Steeper learning curve
- Less familiar for web development

---

## Recommended: Next.js + PostgreSQL Stack

### Reasoning

1. **Unified Development**: Single TypeScript codebase
2. **AI-Friendly**: Well-documented, AI tools excel at JavaScript/TypeScript
3. **Fast Development**: Next.js handles routing, API, optimization
4. **AWS Integration**: Easy deployment via ECS or Amplify
5. **Strong Search**: PostgreSQL full-text search is sufficient
6. **Community**: Large community, extensive resources

## Data Architecture

### Database Schema

#### Users Table
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Books Table
```sql
CREATE TABLE books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asin VARCHAR(50) UNIQUE NOT NULL,
  title VARCHAR(500) NOT NULL,
  description TEXT,
  publisher_summary TEXT,
  runtime_minutes INTEGER,
  release_date DATE,
  publisher VARCHAR(255),
  cover_url VARCHAR(500),
  audio_url VARCHAR(500),
  metadata JSONB, -- Store full metadata JSON
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_books_title ON books USING GIN (to_tsvector('english', title));
CREATE INDEX idx_books_description ON books USING GIN (to_tsvector('english', description));
CREATE INDEX idx_books_metadata ON books USING GIN (metadata);
```

#### Authors Table
```sql
CREATE TABLE authors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asin VARCHAR(50) UNIQUE,
  name VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_authors_name ON authors (name);
```

#### Narrators Table
```sql
CREATE TABLE narrators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asin VARCHAR(50) UNIQUE,
  name VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_narrators_name ON narrators (name);
```

#### Series Table
```sql
CREATE TABLE series (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asin VARCHAR(50) UNIQUE,
  title VARCHAR(500) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_series_title ON series (title);
```

#### Categories Table
```sql
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  parent_id UUID REFERENCES categories(id),
  level INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(name, parent_id)
);

CREATE INDEX idx_categories_name ON categories (name);
CREATE INDEX idx_categories_parent ON categories (parent_id);
```

#### Join Tables

```sql
-- Books to Authors (many-to-many)
CREATE TABLE book_authors (
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  author_id UUID REFERENCES authors(id) ON DELETE CASCADE,
  PRIMARY KEY (book_id, author_id)
);

-- Books to Narrators (many-to-many)
CREATE TABLE book_narrators (
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  narrator_id UUID REFERENCES narrators(id) ON DELETE CASCADE,
  PRIMARY KEY (book_id, narrator_id)
);

-- Books to Series (many-to-many with sequence)
CREATE TABLE book_series (
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  series_id UUID REFERENCES series(id) ON DELETE CASCADE,
  sequence VARCHAR(50),
  PRIMARY KEY (book_id, series_id)
);

CREATE INDEX idx_book_series_sequence ON book_series (series_id, sequence);

-- Books to Categories (many-to-many)
CREATE TABLE book_categories (
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  category_id UUID REFERENCES categories(id) ON DELETE CASCADE,
  PRIMARY KEY (book_id, category_id)
);
```

#### User Progress Table (Future)
```sql
CREATE TABLE user_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  position_seconds INTEGER DEFAULT 0,
  completed BOOLEAN DEFAULT FALSE,
  last_played TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, book_id)
);

CREATE INDEX idx_user_progress_user ON user_progress (user_id, last_played DESC);
```

#### User Lists Table (For iOS App - Future)
```sql
-- User's custom lists ("Want to Listen", "Favorites", etc.)
CREATE TABLE user_lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Books in user lists
CREATE TABLE user_list_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id UUID REFERENCES user_lists(id) ON DELETE CASCADE,
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  position INTEGER, -- For custom ordering
  UNIQUE(list_id, book_id)
);

CREATE INDEX idx_user_lists_user ON user_lists (user_id);
CREATE INDEX idx_user_list_books_list ON user_list_books (list_id, position);
```

## Application Structure

### Directory Structure

```
book_vault/
├── .ai/                        # AI context files
│   ├── PROJECT_CONTEXT.md
│   └── DEVELOPMENT_GOALS.md
├── .github/                    # GitHub Actions CI/CD
│   └── workflows/
├── public/                     # Static assets
├── src/
│   ├── app/                    # Next.js 14 app directory
│   │   ├── api/               # API routes
│   │   │   ├── auth/
│   │   │   ├── books/
│   │   │   ├── search/
│   │   │   └── stream/
│   │   ├── browse/            # Browse pages
│   │   │   ├── authors/
│   │   │   ├── series/
│   │   │   ├── narrators/
│   │   │   └── categories/
│   │   ├── book/              # Book detail page
│   │   ├── search/            # Search page
│   │   ├── login/             # Auth pages
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── components/            # React components
│   │   ├── AudioPlayer/
│   │   ├── BookCard/
│   │   ├── BookGrid/
│   │   ├── SearchBar/
│   │   └── Navigation/
│   ├── lib/                   # Core business logic
│   │   ├── db/               # Database utilities
│   │   ├── auth/             # Authentication
│   │   ├── import/           # Libation import logic
│   │   └── search/           # Search utilities
│   ├── types/                 # TypeScript types
│   └── utils/                 # Helper functions
├── scripts/                   # Utility scripts
│   └── import-books.ts       # Import script
├── tests/                     # Test files
├── .env.example
├── .gitignore
├── docker-compose.yml         # Local development
├── Dockerfile
├── next.config.js
├── package.json
├── tsconfig.json
├── README.md
└── ARCHITECTURE.md
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
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" }
      },
      async authorize(credentials) {
        // Verify against database
        const user = await verifyUser(credentials);
        return user || null;
      }
    })
  ],
  session: {
    strategy: "jwt", // JWT for mobile compatibility
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  jwt: {
    secret: process.env.NEXTAUTH_SECRET,
  },
  // ... additional config
};
```

### 5. API Endpoints (Mobile-Ready)

**Core API routes that serve both web and mobile:**

```typescript
// API structure
/api/
  auth/
    [...nextauth]          # Authentication (web + mobile)
    token/refresh          # JWT refresh endpoint
  books/
    GET    /               # List books with pagination
    GET    /:id            # Get single book
    GET    /:id/stream     # Stream audio file (range requests)
  search/
    GET    /               # Search books
  browse/
    authors/               # List authors
    series/                # List series  
    narrators/             # List narrators
    categories/            # List categories
  user/
    lists/                 # User's custom lists (for iOS)
      GET    /             # Get all lists
      POST   /             # Create new list
      GET    /:id          # Get list with books
      PUT    /:id          # Update list
      DELETE /:id          # Delete list
      POST   /:id/books    # Add book to list
      DELETE /:id/books/:bookId  # Remove book from list
    progress/              # Playback progress
      GET    /             # Get user's progress
      PUT    /:bookId      # Update progress for book
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
   - Playwright for E2E tests
   - Database migrations tested

3. **CI/CD**
   - GitHub Actions
   - Automated tests on PR
   - Deploy on merge to main

## Mobile App Considerations (Future iOS App)

### API-First Design

The architecture is designed with a future iOS app in mind:

1. **RESTful JSON API**: All endpoints return JSON, consumable by any client
2. **JWT Authentication**: Mobile-friendly token-based auth
3. **Range Request Support**: Audio streaming works on iOS
4. **CORS Configuration**: Allow mobile app origins
5. **Versioned API**: `/api/v1/` for future compatibility

### iOS App Features (Planned)

**Browsing**
- Browse books by author, series, narrator, category
- Search functionality
- View book details with cover art

**User Lists**
- Create custom lists ("Want to Listen", "Favorites", etc.)
- Add/remove books from lists
- Reorder books within lists

**Audio Playback**
- Stream audio from server
- Playback controls (play, pause, seek, speed)
- Remember playback position
- Background audio support
- AirPlay support

### iOS Implementation Notes

**Technology Options:**
- **Native Swift + SwiftUI**: Best performance and iOS integration
- **React Native**: Reuse TypeScript knowledge, faster development

**Audio Streaming:**
- Use AVPlayer with remote URL
- Implement range request support
- Handle background audio properly
- Support interruptions (calls, etc.)

**Offline Support (Future):**
- Download books for offline listening
- Sync playback position when online
- Cache cover images

**API Client:**
- Generate TypeScript types from backend
- Use OpenAPI/Swagger for API documentation
- Shared type definitions ensure consistency

### Backend Requirements for Mobile

1. **API Endpoints**: All functionality exposed via REST API
2. **Authentication**: JWT tokens with refresh mechanism
3. **File Streaming**: Support HTTP range requests for seeking
4. **User Lists**: Database schema and endpoints for custom lists
5. **Progress Sync**: Track and sync playback position
6. **Pagination**: Efficient data loading for large collections
7. **CORS**: Properly configured for mobile requests

## Next Steps

1. Set up Next.js project with API-first architecture
2. Configure TypeScript and ESLint
3. Set up PostgreSQL locally
4. Create database schema (including user lists tables)
5. Build import script
6. Develop core API endpoints (mobile-ready)
7. Build frontend components
8. Implement JWT-based authentication
9. Deploy to AWS
10. (Future) Develop iOS app

---

**Last Updated**: December 21, 2025  
**Status**: Initial Architecture  
**Version**: 1.0
