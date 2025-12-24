# Book Vault

A personal audiobook library web application for hosting and managing audiobooks from Audible, processed through Libation.

## Overview

Book Vault is a web-based application designed to organize, search, and stream personal audiobook collections. The application provides a rich browsing experience with support for viewing books by author, series, narrator, title, and category, with full-text search capabilities across book descriptions.

## Features

- **Audio Playback**: Stream audiobooks directly in the browser with:
  - Play/pause controls
  - Seek bar for jumping to any position
  - Skip backward (15s) and forward (30s)
  - Adjustable playback speed (0.75x to 2x)
  - Volume control with mute
  - Time display
  - Automatic position saving and resume
- **Progress Tracking**: Track listening progress across all books
  - Automatic position saving during playback
  - Three states: not started, in progress, finished
  - Manual controls to mark books as finished or reset progress
  - Continue listening carousel on home page
  - Visual progress indicators with percentages
- **User Authentication**: Secure login with password protection
- **Multi-faceted Browsing**: View books by:
  - Author
  - Series (with proper sequencing)
  - Narrator
  - Title
  - Category
- **Advanced Search**: Full-text search across:
  - Authors
  - Narrators
  - Titles
  - Categories
  - Book descriptions
- **Pagination**: Navigate large collections with smart pagination controls
- **Rich Media**: Cover photo display for all books
- **Series Detection**: Automatically detect and group related books in a series
- **User Lists**: Create custom lists to organize books ("Want to Listen", "Favorites", etc.)
- **AWS Deployment**: Designed for cloud deployment on AWS infrastructure
- **Mobile Ready**: API-first design supports future iOS app development

## Data Source

The application reads audiobook data from a Libation export directory structure:

- **Structure**: Each folder represents one book and contains:
  - Audio file(s) (`.mp3`)
  - Metadata file (`.metadata.json`)
  - Cover image (`.jpg`)
  - Cue file (`.cue`)

### Metadata Structure

Each book's `.metadata.json` file contains:

- `title`: Book title
- `asin`: Amazon Standard Identification Number
- `authors`: Array of author objects with name and ASIN
- `narrators`: Array of narrator objects with name and ASIN
- `series`: Array of series information including sequence numbers
- `publisher_summary`: HTML-formatted book description
- `category_ladders`: Hierarchical category information
- `runtime_length_min`: Duration in minutes

## Technology Stack

### Current Implementation

- **Framework**: Next.js 14.2.35 (App Router)
- **Language**: TypeScript 5.7.2
- **Database**: PostgreSQL 15 (Docker)
- **ORM**: Prisma 5.22.0
- **Styling**: Tailwind CSS 3.4.15
- **Authentication**: NextAuth.js 4.24.10 (configured, not yet implemented)
- **Deployment**: Local development (AWS deployment planned)

### Development Tools

- **Linting**: ESLint 8.57.1 with Next.js config
- **Formatting**: Prettier 3.4.2
- **Git Hooks**: Husky + lint-staged
- **Type Safety**: TypeScript with strict mode
- **Security**: npm audit, pre-commit hooks

## Documentation

Comprehensive documentation is available in the [`docs/`](docs/) directory:

### Core Documentation

- **[Architecture](docs/architecture.md)** - System design, data models, and technical architecture
- **[Development Roadmap](docs/development-roadmap.md)** - Feature roadmap, TODO items, and next steps
- **[Testing Guide](docs/testing.md)** - Testing strategy, running tests, and coverage reports
- **[Contributing](CONTRIBUTING.md)** - Guidelines for contributing to the project

### Setup & Configuration

- **[Project Setup](docs/project-setup.md)** - Initial setup steps and configuration
- **[Media Configuration](docs/media-configuration.md)** - Configuring media data paths and file locations
- **[Security](docs/security.md)** - Code quality tools, linting, and git hooks

### Technical Details

- **[API Security](docs/API_SECURITY.md)** - Authentication, endpoint protection, and security audit
- **[Media Security Verification](docs/media-security.md)** - Analysis of file access patterns and security measures
- **[Changelog](CHANGELOG.md)** - Version history and release notes

## Development Approach

This is an **AI-first development project**, meaning:

1. AI agents will assist with all development phases
2. Context and goals are documented for AI reference
3. Architecture decisions are made collaboratively
4. Code quality and best practices are maintained

## Project Status

🚀 **Status**: Active Development

### ✅ Completed (Phase 1-3)

- Database schema and data import from Libation
- Full-featured web UI with browse and search
- Book detail pages with metadata and customer reviews
- Author, narrator, series, and category pages
- Sort functionality (by title, author, narrator, series)
- Pagination with smart page number display (20 items per page)
- Responsive design with Tailwind CSS
- API routes for all entities with pagination support
- Code quality tools (ESLint, Prettier, Husky)
- Comprehensive test suite (70 tests)

### 🚧 In Progress

- Audio player implementation
- User authentication

### 📋 Planned

- User progress tracking
- Custom book lists
- AWS deployment
- iOS mobile app

## Getting Started

### Prerequisites

- Node.js 18+
- Docker (for PostgreSQL)
- Libation audiobook directory

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/dlionikis/book_vault.git
   cd book_vault
   ```

2. **Install dependencies**

   ```bash
   npm install
   ```

3. **Start PostgreSQL**

   ```bash
   docker-compose up -d
   ```

   This starts PostgreSQL on port 5433 (avoiding conflicts with local postgres on 5432).

   To stop the database: `docker-compose down`

4. **Configure environment**

   ```bash
   cp .env.example .env.local
   # Edit .env.local with your settings:
   # - DATABASE_URL: Database connection string
   # - MEDIA_DATA_PATH: Path to your audiobook files (default: test-data)
   # - LIBATION_PATH: Source directory for import (optional)
   ```

   **Media Path Options:**

   ```bash
   # Option 1: Use small test dataset (default)
   MEDIA_DATA_PATH="test-data"

   # Option 2: Point to your full Libation library
   MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"

   # Option 3: Use custom directory
   MEDIA_DATA_PATH="/path/to/audiobooks"
   ```

   See [docs/media-configuration.md](docs/media-configuration.md) for details.

5. **Set up database**

   ```bash
   npm run db:migrate
   npm run db:generate
   ```

6. **Seed test user (optional but recommended for development)**

   ```bash
   npm run db:seed
   ```

   This creates a test user with:
   - Email: `test@example.com`
   - Password: `password123`

7. **Import audiobooks**

   ```bash
   npm run import
   ```

   Note: The import script automatically creates the test user if it doesn't exist.

8. **Start development server**

   ```bash
   npm run dev
   ```

9. **Open application**
   Navigate to [http://localhost:3000](http://localhost:3000)

### Available Commands

```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run start        # Start production server
npm run lint         # Run ESLint
npm run format       # Format code with Prettier
npm run type-check   # Check TypeScript types
npm run validate     # Run all checks (format, lint, types)
npm run test         # Run test suite
npm run import       # Import audiobooks from Libation
npm run db:migrate   # Run database migrations
npm run db:generate  # Generate Prisma client
```

### Database Management

**Reset database and reimport:**

```bash
# Reset the database (clears all data)
npx prisma migrate reset --skip-seed --force

# Reimport all books
npm run import
```

**Note:** The import script automatically uses the path configured in your `.env.local` file (`LIBATION_PATH` or `MEDIA_DATA_PATH`).

## License

Personal Use Only

## Contact

Demetri - Personal Project
