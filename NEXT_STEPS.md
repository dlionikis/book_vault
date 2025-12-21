# Next Steps - Getting Started with Development

This document outlines the immediate next steps to begin building the Book Vault application.

## Current Status ✅

- [x] Git repository initialized
- [x] Project documentation complete
- [x] Architecture designed
- [x] Tech stack recommended (Next.js + TypeScript + PostgreSQL)
- [x] Data structure analyzed

## Immediate Next Steps

### 1. Initialize Next.js Project

```bash
# Create Next.js app with TypeScript
npx create-next-app@latest . --typescript --tailwind --app --no-src

# Install additional dependencies
npm install @prisma/client
npm install -D prisma
npm install next-auth
npm install pg
```

### 2. Set Up Database

**Option A: Local PostgreSQL with Docker**
```bash
# Create docker-compose.yml (see below)
docker-compose up -d

# Initialize Prisma
npx prisma init
```

**Option B: Local PostgreSQL Installation**
```bash
# macOS with Homebrew
brew install postgresql@15
brew services start postgresql@15

# Create database
createdb book_vault
```

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
