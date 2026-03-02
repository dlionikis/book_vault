book_vault/
├── .certs/ # SSL certificates for HTTPS development mode
├── .github/
│ └── workflows/ # GitHub Actions CI/CD pipelines (API validation, type checking, tests)
├── .husky/ # Git hooks (pre-commit: format, lint, type-check)
├── .storybook/ # Storybook configuration for component development
│ ├── docs/ # Storybook documentation assets
│ └── mocks/ # Mock data for Storybook stories
├── .vscode/ # VS Code settings and launch configurations
├── **mocks**/ # Jest mocks for testing (@/lib aliases)
├── **tests**/ # Jest test suite (283 tests)
│ ├── api/ # API endpoint tests (23 OpenAPI contract tests)
│ │ ├── auth/ # Authentication endpoint tests
│ │ ├── books/ # Book endpoint tests
│ │ ├── downloads/ # Download endpoint tests
│ │ └── progress/ # Progress tracking endpoint tests
│ ├── components/ # React component tests
│ ├── lib/ # Library/utility function tests
│ ├── pages/ # Next.js page tests
│ └── scripts/ # Script tests (import, seed)
├── app/ # Next.js 14 App Router (pages and API routes)
│ ├── api/ # RESTful JSON API endpoints
│ │ ├── audio/[...path]/ # Audio file streaming with S3 support
│ │ ├── auth/ # Authentication (login, register, refresh)
│ │ ├── authors/[id]/ # Author detail endpoint
│ │ ├── books/ # Book CRUD and list endpoints
│ │ │ └── [id]/chapters/ # Chapter metadata endpoint
│ │ ├── browse/ # Browse endpoints (authors, series, narrators, categories)
│ │ ├── categories/[id]/ # Category detail endpoint
│ │ ├── downloads/ # Download management (generate URLs, check eligibility, history)
│ │ ├── health/ # Health check endpoint
│ │ ├── images/[...path]/ # Image streaming with S3 support
│ │ ├── library/ # User library management (add/remove books)
│ │ ├── narrators/[id]/ # Narrator detail endpoint
│ │ ├── progress/ # Progress tracking (save/load playback position)
│ │ ├── search/ # Search endpoints (search all, suggestions)
│ │ ├── series/[id]/ # Series detail endpoint
│ │ └── user/ # User management endpoints
│ ├── auth/ # Auth pages (Server Components)
│ │ ├── login/ # Login page
│ │ └── register/ # Registration page
│ ├── authors/[id]/ # Author detail page with books
│ ├── books/ # Book pages
│ │ └── [id]/ # Book detail and playback pages
│ ├── browse/ # Browse pages
│ │ ├── authors/ # Authors browse page
│ │ ├── categories/ # Categories browse page
│ │ ├── narrators/ # Narrators browse page
│ │ └── series/ # Series browse page
│ ├── categories/[id]/ # Category detail page with books
│ ├── library/ # User library page (books added to personal collection)
│ ├── narrators/[id]/ # Narrator detail page with books
│ ├── search/ # Search page with results
│ ├── series/[id]/ # Series detail page with books in order
│ ├── settings/ # User settings page
│ ├── layout.tsx # Root layout with auth and theme providers
│ └── page.tsx # Home page with Continue Listening carousel
├── components/ # React components (Server and Client)
│ ├── AudioPlayer.tsx # Audio playback component with controls, speed, volume
│ ├── BookCard.tsx # Book display card with cover, progress indicator
│ ├── BookGrid.tsx # Responsive grid layout for book cards
│ ├── CategoryBreadcrumb.tsx # Hierarchical category navigation breadcrumb
│ ├── ChapterList.tsx # Chapter navigation list with current chapter highlighting
│ ├── ContinueListening.tsx # Horizontal scrolling carousel of in-progress books
│ ├── DeleteButton.tsx # Confirmation dialog for delete actions
│ ├── ErrorBoundary.tsx # Error boundary for graceful error handling
│ ├── LoginForm.tsx # Login form with validation
│ ├── Navbar.tsx # Top navigation with search, auth, theme toggle
│ ├── Pagination.tsx # Page navigation controls
│ ├── PlaybackClient.tsx # Client wrapper for audio playback with progress sync
│ ├── ProgressBar.tsx # Visual progress indicator for books
│ ├── RegisterForm.tsx # Registration form with validation
│ ├── SearchBar.tsx # Search input with autocomplete
│ ├── SeriesCard.tsx # Series display card with book count
│ ├── ThemeProvider.tsx # Dark mode theme context provider
│ └── UserMenu.tsx # User dropdown menu with logout
├── coverage/ # Jest test coverage reports (HTML)
├── docs/ # Project documentation (AI-first development)
│ ├── INDEX.md # Documentation index with token estimates (START HERE)
│ ├── CLAUDE.md # Project memory anchor for Claude Code sessions
│ ├── STATUS.md # Current status, recent accomplishments, PR history
│ ├── api/ # API documentation
│ │ ├── openapi.yaml # OpenAPI 3.0 specification (single source of truth)
│ │ └── api-reference.html # Generated HTML API documentation
│ ├── api-mobile.md # Mobile API quick reference guide
│ ├── api-quick-ref.md # API endpoints copy-paste reference
│ ├── architecture/ # Architecture documentation
│ │ ├── api-architecture.md # API design patterns and conventions
│ │ ├── component-architecture.md # Component patterns and guidelines
│ │ └── archived/ # Historical architecture docs
│ ├── architecture.md # High-level architecture overview
│ ├── archive/ # Archived documentation
│ │ └── completed-plans/ # Completed feature/refactoring plans
│ ├── component-guide.md # Component decision tree (which component to use)
│ ├── data-flows.md # How data flows through the application
│ ├── data-validation-layers.md # OpenAPI, TypeScript, Zod, Prisma, Swift type integration
│ ├── development-roadmap.md # Current priorities and future plans
│ ├── mobile/ # iOS mobile app documentation
│ │ ├── api-integration.md # API integration patterns for iOS
│ │ ├── architecture.md # iOS app architecture (SwiftUI, AVPlayer, Services)
│ │ ├── implementation-phases/ # Detailed phase implementation plans
│ │ │ ├── phase-5-chapter-navigation.md
│ │ │ └── phase-7-offline-downloads.md
│ │ ├── implementation-phases.md # Overview of all 7 iOS development phases
│ │ ├── ios-development-setup.md # iOS development environment setup
│ │ ├── ios-features.md # iOS-specific features (background audio, lock screen)
│ │ ├── vscode-ios-setup.md # VS Code + Sweetpad setup for iOS development
│ │ └── xcodegen-guide.md # XcodeGen project file management
│ ├── mobile-ios-plan.md # Complete iOS implementation plan (7 phases)
│ ├── refactoring/ # Refactoring plans and completion logs
│ ├── roadmap/ # Feature roadmaps (user-lists, aws-deployment, etc.)
│ ├── storybook.md # Storybook usage guide
│ ├── testing-guide.md # Testing patterns and strategies
│ └── workflows.md # Development workflows and processes
├── ios/ # Native iOS app (Swift + SwiftUI)
│ ├── BookVault/ # iOS app source code
│ │ ├── Assets.xcassets/ # App icons, images, colors
│ │ ├── Components/ # Reusable SwiftUI components
│ │ │ └── MiniPlayerView.swift # Mini player bar UI
│ │ ├── Generated/ # Auto-generated from OpenAPI spec (DO NOT EDIT)
│ │ │ └── Models/ # Swift models generated from openapi.yaml
│ │ ├── Models/ # Custom Swift models
│ │ │ └── UserProgress.swift # Progress tracking data models
│ │ ├── Services/ # Business logic and API clients
│ │ │ ├── APIClient.swift # Base HTTP client with JWT auth
│ │ │ ├── AudioPlayerManager.swift # AVPlayer wrapper with background audio
│ │ │ ├── AuthManager.swift # Authentication service (login, JWT storage)
│ │ │ ├── AuthenticatedAVAssetResourceLoaderDelegate.swift # JWT for audio URLs
│ │ │ ├── ChapterManager.swift # Chapter fetching and caching
│ │ │ ├── DebugLogger.swift # Centralized logging utility
│ │ │ ├── ProgressManager.swift # Progress sync with backend
│ │ │ └── SearchManager.swift # Search and browse with caching
│ │ ├── Views/ # SwiftUI views
│ │ │ ├── Auth/ # Authentication screens
│ │ │ │ └── LoginView.swift
│ │ │ ├── Books/ # Book browsing screens
│ │ │ │ ├── BookDetailLoader.swift # Helper for loading books by ID
│ │ │ │ ├── BookDetailView.swift # Book detail with metadata
│ │ │ │ └── BooksListView.swift # Grid of books with Continue Listening
│ │ │ ├── Browse/ # Browse screens
│ │ │ │ ├── AuthorDetailView.swift
│ │ │ │ ├── AuthorListView.swift
│ │ │ │ ├── BrowseView.swift # Browse hub with category tiles
│ │ │ │ ├── CategoryDetailView.swift
│ │ │ │ ├── CategoryListView.swift
│ │ │ │ ├── NarratorDetailView.swift
│ │ │ │ ├── NarratorListView.swift
│ │ │ │ ├── SeriesDetailView.swift
│ │ │ │ └── SeriesListView.swift
│ │ │ ├── NowPlaying/ # Playback screens
│ │ │ │ └── ChapterListView.swift # Chapter list with skip functionality
│ │ │ ├── Player/
│ │ │ │ └── NowPlayingView.swift # Full player with controls, chapters button
│ │ │ └── Search/
│ │ │ └── SearchView.swift # Search with autocomplete
│ │ ├── BookVaultApp.swift # App entry point
│ │ ├── ContentView.swift # Main TabView (Library, Browse, Search, Downloads)
│ │ └── MockData.swift # Sample data for SwiftUI previews
│ ├── BookVault.xcodeproj/ # Xcode project (managed by XcodeGen)
│ ├── project.yml # XcodeGen configuration (auto-discovers Swift files)
│ ├── PHASE1_IMPLEMENTATION.md # Phase 1 completion log
│ ├── PHASE_2_TEST_CHECKLIST.md # Phase 2 testing checklist
│ ├── PHASE3_TESTING.md # Phase 3 completion log
│ ├── PHASE4_COMPLETE.md # Phase 4 completion log
│ └── PHASE5_COMPLETE.md # Phase 5 completion log
├── lib/ # Shared TypeScript utilities and types
│ ├── api-helpers.ts # Generic API route helpers (DRY refactor)
│ ├── api-types.ts # Auto-generated TypeScript types from OpenAPI (DO NOT EDIT)
│ ├── api-utils.ts # API utilities (UUID normalization)
│ ├── auth.ts # NextAuth.js configuration
│ ├── chapters.ts # Chapter extraction from audio files (ffprobe)
│ ├── db.ts # Prisma Client singleton (prevents connection leaks)
│ ├── media.ts # Media URL helpers (S3 or filesystem)
│ ├── prisma.ts # Prisma client export
│ ├── s3.ts # S3 streaming helpers (audio/image with range requests)
│ ├── types.ts # Shared TypeScript types (Book, Author, etc.)
│ └── utils/ # Utility functions
│ └── sanitize.ts # HTML sanitization for user content
├── prisma/ # Database schema and migrations
│ ├── schema.prisma # Prisma schema (14 models: Book, Author, User, etc.)
│ ├── migrations/ # Database migration history
│ └── seed.ts # Database seeding script (test user)
├── scripts/ # Utility scripts
│ ├── create-admin.ts # Interactive admin user creation
│ ├── import.ts # Import audiobooks from Libation directory
│ └── seed.ts # Seed database with test user
├── stories/ # Storybook stories (component examples)
│ ├── AudioPlayer.stories.tsx
│ ├── BookCard.stories.tsx
│ ├── ChapterList.stories.tsx
│ ├── ContinueListening.stories.tsx
│ ├── LoginForm.stories.tsx
│ ├── Navbar.stories.tsx
│ ├── Pagination.stories.tsx
│ ├── ProgressBar.stories.tsx
│ ├── SearchBar.stories.tsx
│ ├── SeriesCard.stories.tsx
│ └── assets/ # Assets for Storybook
├── test-data/ # Sample audiobook data for development
│ └── [Book Name]/ # Each book has: .metadata.json, .mp3, .jpg, .cue
├── test-fixtures/ # Shared JSON test fixtures for backend and iOS
│ ├── books-list.json
│ ├── book-detail.json
│ └── user-progress.json
├── types/ # TypeScript type declarations
├── .env # Environment variables (DATABASE_URL, AWS keys, etc.)
├── .eslintrc.json # ESLint configuration
├── .gitignore # Git ignore rules
├── .prettierrc # Prettier code formatting rules
├── docker-compose.yml # PostgreSQL container (port 5433)
├── jest.config.js # Jest testing configuration
├── middleware.ts # Next.js middleware (auth protection)
├── next.config.mjs # Next.js configuration
├── package.json # NPM dependencies and scripts
├── tailwind.config.ts # Tailwind CSS configuration
└── tsconfig.json # TypeScript compiler configuration
