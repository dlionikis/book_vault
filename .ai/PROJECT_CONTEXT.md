# Book Vault - Project Context

## Purpose
This document provides comprehensive context for AI agents working on the Book Vault project. It serves as persistent memory across sessions to maintain continuity and understanding.

## Project Genesis

**Date Started**: December 21, 2025  
**Owner**: Demetri  
**Project Type**: Personal Web Application  
**Development Approach**: AI-First Development

## Problem Statement

The owner has a large personal audiobook collection purchased from Audible, which has been processed through the open-source tool [Libation](https://github.com/rmcrackan/Libation) for format conversion and backup. These audiobooks need a dedicated web interface for:

1. Organization and discovery
2. Streaming playback
3. Search and filtering
4. Series management
5. Multi-faceted browsing (author, narrator, category, etc.)

The current state is a directory of folders on an external drive (`/Volumes/BeeDrive/Libation/`) with no organized interface.

## Core Requirements

### Functional Requirements

1. **Authentication & Security**
   - User login with password
   - Secure session management
   - Personal/private access only (single user initially)

2. **Content Management**
   - Read and index all books from Libation directory
   - Parse JSON metadata files
   - Extract cover images
   - Identify series relationships and sequencing

3. **Browsing & Navigation**
   - Browse by Author
   - Browse by Series (with proper book ordering)
   - Browse by Narrator
   - Browse by Title (A-Z)
   - Browse by Category (using category_ladders from metadata)

4. **Search Functionality**
   - Search across authors
   - Search across narrators
   - Search across titles
   - Search across categories
   - Full-text search in book descriptions (publisher_summary)

5. **Media Display**
   - Display cover images for all books
   - Show comprehensive book details
   - Display series information and order

6. **Audio Playback**
   - Stream audio files
   - Maintain playback position
   - Support basic controls (play, pause, seek, speed)

### Non-Functional Requirements

1. **Deployment**: AWS-hosted
2. **Performance**: Fast loading and responsive UI
3. **Scalability**: Support 500-1000+ books
4. **Maintainability**: Clean, documented code
5. **Reliability**: Stable playback and navigation

## Data Structure

### Source Data Location
- **Primary Path**: `/Volumes/BeeDrive/Libation/`
- **Structure**: One folder per book
- **Folder Naming**: `{Book Title} [{ASIN}]`

### Files per Book
Each book folder contains:
- `{BookTitle}.metadata.json` - Complete metadata
- `{BookTitle}.mp3` - Audio file (single file, processed by Libation)
- `{BookTitle}.jpg` - Cover image
- `{BookTitle}.cue` - Cue sheet for chapters
- `Icon?` - macOS metadata file (can be ignored)

### Metadata JSON Structure

Key fields used from `.metadata.json`:

```json
{
  "asin": "string",
  "title": "string",
  "authors": [
    {
      "name": "string",
      "asin": "string"
    }
  ],
  "narrators": [
    {
      "name": "string",
      "asin": "string"
    }
  ],
  "series": [
    {
      "title": "string",
      "sequence": "string",
      "asin": "string",
      "url": "string"
    }
  ],
  "publisher_summary": "string (HTML content)",
  "category_ladders": [
    {
      "root": "string",
      "ladder": [
        {
          "id": "string",
          "name": "string"
        }
      ]
    }
  ],
  "runtime_length_min": number,
  "release_date": "string",
  "publisher": "string"
}
```

## Technical Considerations

### Data Access Patterns
1. Initial scan and index of all books (one-time or periodic)
2. Quick filtering and sorting operations
3. Full-text search across descriptions
4. Series grouping and sequencing
5. Author/narrator aggregation

### Key Challenges
1. **Data Volume**: Potentially large number of books (500-1000+)
2. **Media Streaming**: Efficient audio file delivery
3. **Search Performance**: Fast full-text search
4. **Series Detection**: Accurate grouping of related books
5. **Category Hierarchy**: Handling nested category structures

### AWS Deployment Considerations
- Storage for audio files (likely S3)
- Database for metadata indexing
- Compute for application logic
- CDN for static assets and cover images
- Authentication mechanism

## Current State

### Completed
- ✅ Git repository initialized
- ✅ Project scaffolding begun
- ✅ Data structure analyzed
- ✅ Requirements documented

### In Progress
- 🔄 AI context documentation

### To Do
- ⏳ Technology stack selection
- ⏳ Architecture design
- ⏳ Backend implementation
- ⏳ Frontend implementation
- ⏳ AWS deployment configuration

## Important Notes for AI Agents

1. **Data Source is External**: The audiobook files live on `/Volumes/BeeDrive/Libation/` which is an external drive. The application will need to either:
   - Access this path directly (development)
   - Copy/sync data to AWS (production)

2. **Series Relationships**: The `series` array in metadata contains sequence numbers. Books in the same series share the same series title but have different sequence numbers.

3. **HTML Content**: The `publisher_summary` field contains HTML tags and should be rendered appropriately in the UI.

4. **Categories are Hierarchical**: Each book can belong to multiple category paths (ladders), creating a complex taxonomy.

5. **Single User Initially**: While the system should have authentication, it's designed for personal use, so multi-user features are not required initially.

## Questions to Resolve

1. Should the application sync data to AWS or access the external drive directly?
2. What's the preferred technology stack?
3. Should we support user bookmarks/progress tracking?
4. Should we implement a rating/favorite system?
5. What level of audio player sophistication is needed?

---

**Last Updated**: December 21, 2025  
**Document Version**: 1.0
