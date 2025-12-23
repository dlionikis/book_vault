# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Chapter Metadata Extraction**
  - Database schema for storing chapter information (Chapter model)
  - Audio metadata extraction utility using ffprobe
  - Automatic chapter parsing from MP3 files with cuesheet support
  - API endpoint `/api/books/[id]/chapters` to retrieve chapters
  - Caches extracted chapters in database for performance
  - 6 comprehensive tests for audio metadata extraction
- **Audio Player** with full playback controls
  - Play/pause controls with visual feedback
  - Seek bar for jumping to specific positions
  - Skip backward (15s) and forward (30s) buttons
  - Playback speed controls (0.75x, 1x, 1.25x, 1.5x, 2x)
  - Volume control with mute button
  - Time display showing current time and duration
  - Mobile-responsive design with adaptive controls
  - Fixed position at bottom of page for persistent access
- Audio streaming API endpoint (`/api/audio/[...path]`) with range request support for seeking
- 22 comprehensive AudioPlayer tests covering all controls and interactions
- Pagination component with smart page number display and ellipsis
- Pagination support across all list/detail pages (home, search, authors, narrators, series, categories)
- 21 comprehensive pagination tests covering navigation, accessibility, and edge cases
- Configurable media data path via `MEDIA_DATA_PATH` environment variable
- Media path utility functions (`lib/media.ts`)
- Path validation for secure file access
- Comprehensive media configuration documentation (`docs/MEDIA_CONFIGURATION.md`)
- Security verification documentation (`docs/MEDIA_SECURITY_VERIFICATION.md`)
- Import script test suite with 21 tests covering edge cases
- Automatic environment variable loading with dotenv

### Changed

- Audio URLs now use `/api/audio/` endpoint instead of `/api/images/` for streaming support
- Book detail pages now display AudioPlayer component when audioUrl is available
- All API endpoints now support pagination via `page` and `limit` query parameters (default: 20 items per page)
- Home page, search page, and all detail pages now accept page parameter
- Import script now uses ASIN-first lookup for authors/narrators to handle name variations
- Import script deduplicates category IDs to prevent constraint violations
- Import script properly handles authors with multiple ASINs or null ASINs
- Image API routes now use configurable media path
- Jest configuration updated to include scripts directory in coverage

### Fixed

- Author import conflicts when same person has different name spellings (e.g., "Michael Manning" vs "Michael G. Manning")
- Author import conflicts when same person has multiple ASINs
- Narrator import issues with null ASINs
- Category constraint violations from duplicate category assignments
- Import script now loads environment variables from .env.local automatically

### Security

- Verified all file operations are read-only (no write/modify/delete)
- Added path validation to prevent directory traversal attacks
- Documented security measures for production deployment

## [0.1.0] - 2025-12-21

### Added

- Project inception
- Basic project structure
- Core documentation:
  - README.md
  - ARCHITECTURE.md
  - CONTRIBUTING.md
  - .ai/PROJECT_CONTEXT.md
  - .ai/DEVELOPMENT_GOALS.md
- Environment configuration template
- Git repository with proper .gitignore

### Context

- Analyzed Libation audiobook directory structure
- Identified key metadata fields and relationships
- Documented series detection requirements
- Outlined search and browsing requirements

[Unreleased]: https://github.com/yourusername/book_vault/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/book_vault/releases/tag/v0.1.0
