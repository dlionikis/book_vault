# Book Vault

A personal audiobook library web application for hosting and managing audiobooks from Audible, processed through Libation.

## Overview

Book Vault is a web-based application designed to organize, search, and stream personal audiobook collections. The application provides a rich browsing experience with support for viewing books by author, series, narrator, title, and category, with full-text search capabilities across book descriptions.

## Features

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
- Responsive design with Tailwind CSS
- API routes for all entities
- Code quality tools (ESLint, Prettier, Husky)

### 🚧 In Progress

- Audio player implementation
- Pagination controls
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
   docker run --name book-vault-db -e POSTGRES_PASSWORD=yourpassword \
     -e POSTGRES_DB=book_vault -p 5433:5432 -d postgres:15
   ```

4. **Configure environment**

   ```bash
   cp .env.example .env.local
   # Edit .env.local with your database connection and Libation path
   ```

5. **Set up database**

   ```bash
   npm run db:migrate
   npm run db:generate
   ```

6. **Import audiobooks**

   ```bash
   npm run import
   ```

7. **Start development server**

   ```bash
   npm run dev
   ```

8. **Open application**
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
npm run import       # Import audiobooks from Libation
```

## License

Personal Use Only

## Contact

Demetri - Personal Project
