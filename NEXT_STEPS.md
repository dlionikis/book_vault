# Next Steps - Enhancement & Features Phase

This document outlines the next steps now that core functionality is complete.

## Current Status ✅

### Completed (Phases 1-3)
- [x] Git repository initialized
- [x] Project documentation complete
- [x] Architecture designed
- [x] Next.js 14 application running
- [x] PostgreSQL database in Docker (port 5433)
- [x] Prisma schema with 14 models
- [x] Database migrations applied
- [x] Import script written and tested
- [x] **11 audiobooks imported with full metadata**
- [x] **All API endpoints created and working**
- [x] **Series detail pages with proper ordering**
- [x] **Search functionality across all entities**
- [x] **Browse pages for authors, narrators, series, categories**
- [x] **Detail pages for all entity types**
- [x] **BackButton component for navigation**
- [x] **Sort functionality (Title, Author, Narrator, Series)**
- [x] **Customer reviews displayed on book pages**
- [x] **Clickable categories on book pages**

### Current Features Working
- Browse all books with sorting options
- Search across books, authors, narrators, series
- View series with books in sequence order
- Browse by author, narrator, series, or category
- Click through to detail pages for any entity
- Responsive grid layouts
- Clean UI with Tailwind CSS
- Customer reviews with star ratings on book pages
- Clickable category tags for easy navigation

## Immediate Next Steps - Phase 4: Enhancement & Features

### 1. Audio Player Implementation 🎵

**Priority: HIGH** - Core functionality needed for audiobook playback

Create audio player component and streaming endpoint:

**Backend: Audio Streaming API**
```typescript
// app/api/audio/[...path]/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createReadStream, statSync } from 'fs';
import { join } from 'path';

export async function GET(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  const filePath = join(process.env.AUDIO_PATH || 'test-data', ...params.path);
  
  try {
    const stat = statSync(filePath);
    const range = request.headers.get('range');
    
    if (range) {
      // Support range requests for seeking
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : stat.size - 1;
      
      const stream = createReadStream(filePath, { start, end });
      
      return new NextResponse(stream as any, {
        status: 206,
        headers: {
          'Content-Range': `bytes ${start}-${end}/${stat.size}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': (end - start + 1).toString(),
          'Content-Type': 'audio/mpeg',
        },
      });
    }
    
    const stream = createReadStream(filePath);
    return new NextResponse(stream as any, {
      headers: {
        'Content-Type': 'audio/mpeg',
        'Content-Length': stat.size.toString(),
      },
    });
  } catch (error) {
    return NextResponse.json({ error: 'File not found' }, { status: 404 });
  }
}
```

**Frontend: Audio Player Component**
```typescript
// components/AudioPlayer.tsx
'use client';

import { useState, useRef, useEffect } from 'react';

interface AudioPlayerProps {
  audioUrl: string;
  title: string;
  author: string;
  bookId: string;
}

export default function AudioPlayer({ audioUrl, title, author, bookId }: AudioPlayerProps) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const audioRef = useRef<HTMLAudioElement>(null);

  const togglePlay = () => {
    if (audioRef.current) {
      if (isPlaying) {
        audioRef.current.pause();
      } else {
        audioRef.current.play();
      }
      setIsPlaying(!isPlaying);
    }
  };

  const handleTimeUpdate = () => {
    if (audioRef.current) {
      setCurrentTime(audioRef.current.currentTime);
      // TODO: Save progress to API
    }
  };

  const handleLoadedMetadata = () => {
    if (audioRef.current) {
      setDuration(audioRef.current.duration);
    }
  };

  const formatTime = (seconds: number) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  };

  return (
    <div className="fixed bottom-0 left-0 right-0 bg-white border-t shadow-lg p-4">
      <audio
        ref={audioRef}
        src={audioUrl}
        onTimeUpdate={handleTimeUpdate}
        onLoadedMetadata={handleLoadedMetadata}
      />
      
      <div className="max-w-7xl mx-auto">
        <div className="flex items-center gap-4">
          <button
            onClick={togglePlay}
            className="w-12 h-12 flex items-center justify-center bg-blue-600 text-white rounded-full hover:bg-blue-700"
          >
            {isPlaying ? '⏸' : '▶️'}
          </button>
          
          <div className="flex-1">
            <div className="font-medium text-gray-900">{title}</div>
            <div className="text-sm text-gray-600">{author}</div>
          </div>
          
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-600">{formatTime(currentTime)}</span>
            <input
              type="range"
              min="0"
              max={duration || 0}
              value={currentTime}
              onChange={(e) => {
                const time = parseFloat(e.target.value);
                setCurrentTime(time);
                if (audioRef.current) {
                  audioRef.current.currentTime = time;
                }
              }}
              className="w-64"
            />
            <span className="text-sm text-gray-600">{formatTime(duration)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
```

**Usage**: Add to book detail page

### 2. Pagination UI Controls

**Priority: MEDIUM** - API already supports pagination, just needs UI

Add prev/next buttons to home page:

```typescript
// components/Pagination.tsx
'use client';

import { useRouter, useSearchParams } from 'next/navigation';

interface PaginationProps {
  currentPage: number;
  totalPages: number;
  total: number;
}

export default function Pagination({ currentPage, totalPages, total }: PaginationProps) {
  const router = useRouter();
  const searchParams = useSearchParams();

  const goToPage = (page: number) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set('page', page.toString());
    router.push(`/?${params.toString()}`);
  };

  return (
    <div className="flex items-center justify-between mt-8">
      <div className="text-sm text-gray-600">
        Showing page {currentPage} of {totalPages} ({total} books)
      </div>
      
      <div className="flex gap-2">
        <button
          onClick={() => goToPage(currentPage - 1)}
          disabled={currentPage === 1}
          className="px-4 py-2 bg-white border border-gray-300 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50"
        >
          Previous
        </button>
        
        <button
          onClick={() => goToPage(currentPage + 1)}
          disabled={currentPage === totalPages}
          className="px-4 py-2 bg-white border border-gray-300 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50"
        >
          Next
        </button>
      </div>
    </div>
  );
}
```

Update home page to use pagination and pass page parameter to API.

### 3. User Progress Tracking

**Priority: HIGH** - Essential for audiobook app

Create API endpoints and UI for saving/loading playback position:

```typescript
// app/api/progress/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// Save progress
export async function POST(request: NextRequest) {
  const { bookId, userId, position, duration } = await request.json();
  
  const progress = await prisma.userProgress.upsert({
    where: {
      userId_bookId: { userId, bookId },
    },
    update: {
      position,
      duration,
      lastListenedAt: new Date(),
    },
    create: {
      userId,
      bookId,
      position,
      duration,
      completed: false,
    },
  });
  
  return NextResponse.json(progress);
}

// Get progress for a book
export async function GET(request: NextRequest) {
  const userId = request.nextUrl.searchParams.get('userId');
  const bookId = request.nextUrl.searchParams.get('bookId');
  
  if (!userId || !bookId) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }
  
  const progress = await prisma.userProgress.findUnique({
    where: {
      userId_bookId: { userId, bookId },
    },
  });
  
  return NextResponse.json(progress || { position: 0 });
}
```

Update AudioPlayer to save/load progress automatically.

### 4. Authentication with NextAuth.js

**Priority: MEDIUM** - Needed before multi-device sync

Install and configure NextAuth.js:

```bash
npm install next-auth @auth/prisma-adapter
```

Create auth configuration and login pages. For personal use, can start with simple email/password or magic link authentication.

### 5. User Lists Feature

**Priority: LOW** - Nice to have

Create endpoints for managing custom lists:
- "Want to Listen"
- "Favorites"  
- "Currently Listening"
- Custom lists

API endpoints:
- POST /api/lists - Create list
- GET /api/lists - Get user's lists
- POST /api/lists/[id]/books - Add book to list
- DELETE /api/lists/[id]/books/[bookId] - Remove book from list

## Medium Term Goals (Next 2 Weeks)

### 1. Media File Management

Decide on file storage strategy:
- **Option A**: Keep files on external drive, serve locally
- **Option B**: Upload to S3, serve from there
- **Option C**: Hybrid - local dev, S3 for production

Update media utility functions based on decision.

### 2. Performance Optimization

- Add loading states to all pages
- Implement skeleton loaders for book grids
- Add error boundaries
- Optimize image loading (Next.js Image component)
- Add caching headers to API responses

### 3. Enhanced Search

Add filters to search:
- By category
- By narrator
- By series
- Published date range
- Duration range

### 4. Mobile Optimization

- Test on mobile devices
- Improve touch targets
- Add mobile-specific layouts
- Test audio player on iOS/Android

## Long Term Goals (Next Month)

### 1. AWS Deployment

**Infrastructure Setup**:
```
- RDS PostgreSQL (production database)
- S3 buckets (audio files, cover images)
- CloudFront CDN (fast delivery)
- ECS or Lambda (application hosting)
- Route 53 (domain management)
- Certificate Manager (SSL/TLS)
```

**Deployment Steps**:
1. Create S3 upload script for audio files
2. Set up RDS instance
3. Configure environment variables
4. Deploy application to ECS/Lambda
5. Set up CloudFront distribution
6. Configure domain and SSL
7. Test production environment

### 2. iOS App Development

Once API is stable:
- SwiftUI app
- Shared authentication
- Offline download support
- Background audio playback
- CarPlay integration

## Current API Endpoints ✅

All functional and tested:
- `GET /api/books` - List books with pagination and sorting
- `GET /api/books/[id]` - Single book details
- `GET /api/series/[id]` - Series with books in order
- `GET /api/authors/[id]` - Author with all books
- `GET /api/narrators/[id]` - Narrator with all books
- `GET /api/categories/[id]` - Category with all books
- `GET /api/browse/authors` - All authors with counts
- `GET /api/browse/narrators` - All narrators with counts
- `GET /api/browse/series` - All series with counts
- `GET /api/browse/categories` - All categories
- `GET /api/search` - Search across all entities
- `GET /api/images/[...path]` - Serve cover images

## Recommended Next Step 🎯

**Start with Audio Player** - This is the core feature that makes it an audiobook app. Once playback works, everything else is enhancement.

Steps:
1. Create audio streaming endpoint (`/api/audio/[...path]`)
2. Build AudioPlayer component with basic controls
3. Add to book detail page
4. Test with one of the imported audiobooks
5. Add progress tracking API
6. Connect player to progress tracking

Once audio works, move to pagination UI, then authentication, then deployment.

---

## Testing Checklist

Before proceeding to deployment, test these features:

### Core Functionality ✅
- [x] Home page loads with all books
- [x] Sort by title, author, narrator, series
- [x] Search works across entities
- [x] Series pages show books in order
- [x] Browse pages show all authors/narrators/series/categories
- [x] Detail pages work for all entity types
- [x] Book detail page shows full metadata
- [x] BackButton navigates properly
- [x] Images load correctly

### Audio Features ⏳
- [ ] Audio streaming endpoint works
- [ ] Audio player controls work (play/pause)
- [ ] Seeking works in audio
- [ ] Progress saves automatically
- [ ] Progress resumes on page reload
- [ ] Audio works on mobile browsers

### User Features ⏳
- [ ] Authentication works
- [ ] User can create lists
- [ ] User can add/remove books from lists
- [ ] Lists persist across sessions

### Performance ⏳
- [ ] Pages load quickly
- [ ] Images are optimized
- [ ] Audio streams without buffering
- [ ] No memory leaks in player

---

## Environment Variables Reference

Current `.env` file:
```
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/book_vault?schema=public"
AUDIO_PATH="/Users/demetri/projects/book_vault/test-data"
NEXTAUTH_SECRET="your-secret-here"
NEXTAUTH_URL="http://localhost:3000"
```

For production, add:
```
AWS_REGION="us-east-1"
AWS_S3_BUCKET="book-vault-audio"
CDN_URL="https://d123456.cloudfront.net"
DATABASE_URL="postgresql://user:pass@rds-endpoint:5432/book_vault"
```

---

## Common Commands Reference

```bash
# Development
npm run dev              # Start Next.js dev server
npm run import          # Run import script
npm run build           # Build for production
npm start               # Start production server

# Database
docker-compose up -d    # Start PostgreSQL
docker-compose down     # Stop PostgreSQL
npx prisma studio       # Database GUI
npx prisma migrate dev  # Run migrations
npx prisma generate     # Generate Prisma client

# Git
git log --oneline       # View commits
git status              # Check changes
git add .               # Stage all changes
git commit -m "msg"     # Commit with message
```

---

## Project Structure Overview

```
book_vault/
├── .ai/                          # AI agent context files
│   ├── SESSION_2025-12-22.md     # Today's session notes
│   ├── DEVELOPMENT_GOALS.md      # Roadmap and phases
│   └── PROJECT_CONTEXT.md        # Project overview
├── app/                          # Next.js pages
│   ├── page.tsx                  # Home page ✅
│   ├── books/[id]/page.tsx       # Book detail ✅
│   ├── series/[id]/page.tsx      # Series detail ✅
│   ├── authors/[id]/page.tsx     # Author detail ✅
│   ├── narrators/[id]/page.tsx   # Narrator detail ✅
│   ├── categories/[id]/page.tsx  # Category detail ✅
│   ├── search/page.tsx           # Search results ✅
│   ├── browse/                   # Browse pages ✅
│   └── api/                      # API endpoints ✅
│       ├── books/                # Books API ✅
│       ├── series/[id]/          # Series API ✅
│       ├── authors/[id]/         # Authors API ✅
│       ├── narrators/[id]/       # Narrators API ✅
│       ├── categories/[id]/      # Categories API ✅
│       ├── browse/               # Browse APIs ✅
│       ├── search/               # Search API ✅
│       └── images/[...path]/     # Image serving ✅
├── components/                   # React components
│   ├── BookCard.tsx              # Individual book card ✅
│   ├── BookGrid.tsx              # Book grid layout ✅
│   ├── SearchBar.tsx             # Search input ✅
│   ├── SortDropdown.tsx          # Sort selector ✅
│   └── BackButton.tsx            # Navigation button ✅
├── lib/                          # Utilities
│   ├── types.ts                  # TypeScript interfaces ✅
│   └── media.ts                  # Media URL helpers ✅
├── prisma/                       # Database
│   ├── schema.prisma             # Database schema ✅
│   └── migrations/               # Migration history ✅
├── scripts/                      # Utility scripts
│   └── import-libation.ts        # Import script ✅
└── test-data/                    # Sample audiobooks (11) ✅
```

---

## Key Decisions & Rationale

### Technology Choices
- **Next.js 14**: Full-stack framework, great DX, easy deployment
- **TypeScript**: Type safety, better tooling
- **PostgreSQL**: Robust, proven, good for relational data
- **Prisma**: Modern ORM, great TypeScript support
- **Tailwind CSS**: Rapid UI development, consistent styling

### Architecture Patterns
- **API-First**: All data through API for iOS app compatibility
- **Server Components**: Better performance, less client JS
- **Client Components**: Only where interactivity needed (player, forms)
- **Mixed Sorting**: Database where possible, client-side for complex relations

### File Organization
- **test-data/**: Git-ignored sample data for development
- **Separate APIs**: Clean separation of concerns
- **Reusable Components**: DRY principle, consistent UI

---

## Success Metrics

### Current Achievement 🎉
- ✅ 11 books imported with full metadata
- ✅ All API endpoints functional
- ✅ Complete browsing and search experience
- ✅ Clean, responsive UI
- ✅ Sort functionality working
- ✅ Proper navigation with back button
- ✅ Series ordering correct
- ✅ Customer reviews displayed with ratings
- ✅ Clickable categories for navigation

### Next Milestones
- 🎯 Audio playback working
- 🎯 Progress tracking functional
- 🎯 Pagination UI complete
- 🎯 Authentication implemented
- 🎯 Ready for AWS deployment

---

**Last Updated**: December 22, 2025
**Current Phase**: Phase 4 - Enhancement & Features
**Next Priority**: Audio Player Implementation

**Recent Updates**:
- Added customer review display on book detail pages
- Made category tags clickable
- Fixed various navigation bugs

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const page = parseInt(searchParams.get('page') || '1');
  const limit = parseInt(searchParams.get('limit') || '20');
  const skip = (page - 1) * limit;

  const [books, total] = await Promise.all([
    prisma.book.findMany({
      skip,
      take: limit,
      include: {
        authors: { include: { author: true } },
        narrators: { include: { narrator: true } },
        series: { include: { series: true } },
      },
      orderBy: { title: 'asc' },
    }),
    prisma.book.count(),
  ]);

  return NextResponse.json({
    books,
    pagination: {
      page,
      limit,
      total,
      pages: Math.ceil(total / limit),
    },
  });
}
```

**Test it**: `http://localhost:3000/api/books`

### 2. Create Single Book Endpoint

Create `app/api/books/[id]/route.ts` for book details:

```typescript
import { NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const book = await prisma.book.findUnique({
    where: { id: params.id },
    include: {
      authors: { include: { author: true } },
      narrators: { include: { narrator: true } },
      series: { include: { series: true } },
      categories: { include: { category: true } },
    },
  });

  if (!book) {
    return NextResponse.json(
      { error: 'Book not found' },
      { status: 404 }
    );
  }

  return NextResponse.json(book);
}
```

### 3. Create Search Endpoint

### 3. Configure Prisma Schema

Create `prisma/schema.prisma` based on the database schema in `ARCHITECTURE.md`:
- Users table
- Books table
- Authors, Narrators, Series, Categories tables
- Join tables for relationships

### 4. Build the Import Script

Create `scripts/import-libation.ts` to:
- Scan `/Volumes/BeeDrive/Libation/` directory
- Parse JSON metadata files
- Populate database
- Handle errors gracefully

Test with a small subset of books first!

### 5. Create Basic API Routes

Start with:
- `app/api/books/route.ts` - List all books
- `app/api/books/[id]/route.ts` - Get single book
- `app/api/search/route.ts` - Search functionality
- `app/api/auth/[...nextauth]/route.ts` - Authentication

### 6. Build Core UI Components

Create in `components/`:
- `BookCard.tsx` - Display book with cover
- `BookGrid.tsx` - Grid layout of books
- `SearchBar.tsx` - Search input
- `Navigation.tsx` - Site navigation
- `AudioPlayer.tsx` - Audio playback controls

### 7. Create Main Pages

Build pages in `app/`:
- `app/page.tsx` - Home/dashboard
- `app/browse/authors/page.tsx` - Browse by author
- `app/browse/series/page.tsx` - Browse by series
- `app/book/[id]/page.tsx` - Book detail page
- `app/search/page.tsx` - Search results

## Docker Compose for Local Development

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15
    container_name: book_vault_db
    environment:
      POSTGRES_DB: book_vault
      POSTGRES_USER: bookadmin
      POSTGRES_PASSWORD: dev_password_change_in_production
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Sample Import Script Skeleton

```typescript
// scripts/import-libation.ts
import fs from 'fs/promises';
import path from 'path';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const LIBATION_PATH = process.env.LIBATION_PATH || '/Volumes/BeeDrive/Libation';

async function importBooks() {
  const folders = await fs.readdir(LIBATION_PATH);
  
  for (const folder of folders) {
    if (folder.startsWith('.')) continue;
    
    try {
      const folderPath = path.join(LIBATION_PATH, folder);
      const files = await fs.readdir(folderPath);
      
      // Find metadata file
      const metadataFile = files.find(f => f.endsWith('.metadata.json'));
      if (!metadataFile) continue;
      
      // Read and parse metadata
      const metadataPath = path.join(folderPath, metadataFile);
      const metadata = JSON.parse(await fs.readFile(metadataPath, 'utf-8'));
      
      // Import book to database
      await importBook(metadata, folderPath);
      
      console.log(`Imported: ${metadata.title}`);
    } catch (error) {
      console.error(`Error importing ${folder}:`, error);
    }
  }
}

async function importBook(metadata: any, folderPath: string) {
  // Create or find authors
  // Create or find narrators
  // Create or find series
  // Create book record
  // Link relationships
}

importBooks()
  .then(() => console.log('Import complete'))
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

## Testing the Import

1. Start with just 5-10 books
2. Verify data in database
3. Check for proper relationships
4. Fix any issues
5. Run full import

## Development Workflow

1. **Morning**: Review what was done yesterday
2. **Plan**: Check `.ai/DEVELOPMENT_GOALS.md` for current phase
3. **Code**: Implement one feature at a time
4. **Test**: Verify it works
5. **Document**: Update relevant docs
6. **Commit**: Clear commit message
7. **End of day**: Update `.ai/PROJECT_CONTEXT.md`

## Quick Commands Reference

```bash
# Install dependencies
npm install

# Set up environment
cp .env.example .env.local

# Start database
docker-compose up -d

# Create database schema
npx prisma migrate dev

# Import books
npm run import

# Start development server
npm run dev

# Run tests
npm test

# Build for production
npm run build
```

## Helpful Tips

1. **Start Small**: Don't try to build everything at once
2. **Test Frequently**: Run the import on small samples first
3. **Check Data**: Use Prisma Studio (`npx prisma studio`) to inspect database
4. **Read Logs**: Pay attention to error messages
5. **Commit Often**: Small commits are easier to debug

## When You Get Stuck

1. Check `ARCHITECTURE.md` for design decisions
2. Review `.ai/PROJECT_CONTEXT.md` for project context
3. Look at the sample data in Libation directory
4. Test with a single book first
5. Ask AI for help with specific issues

## Success Criteria for Phase 1

You'll know Phase 1 is complete when:
- ✅ Next.js app is running
- ✅ Database is set up and migrations work
- ✅ Import script successfully imports all books
- ✅ API returns book data
- ✅ Basic UI shows list of books
- ✅ Authentication works

## Moving Forward

After Phase 1, proceed to Phase 2 (Backend Core) as outlined in `.ai/DEVELOPMENT_GOALS.md`.

Remember: This is an iterative process. It's okay to refine and adjust as you go!

---

**Ready to start?** Run: `npx create-next-app@latest . --typescript --tailwind --app`

**Questions?** Check the `.ai/` directory documentation.

**Need help?** The architecture and context files have all the details you need!
