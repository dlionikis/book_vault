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

- **Location**: `/Volumes/BeeDrive/Libation/`
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

**To Be Determined**: This project will be developed using an AI-first approach. Technology stack decisions will be made collaboratively with AI assistance based on:

- Scalability requirements
- AWS integration capabilities
- Development velocity
- Maintainability

Likely candidates include:

- **Backend**: Node.js/Express, Python/FastAPI, or Go
- **Frontend**: React, Vue, or Next.js
- **Database**: PostgreSQL or DynamoDB
- **Storage**: S3 for media files
- **Authentication**: AWS Cognito or custom JWT
- **Deployment**: ECS, Lambda, or EC2

## Development Approach

This is an **AI-first development project**, meaning:

1. AI agents will assist with all development phases
2. Context and goals are documented for AI reference
3. Architecture decisions are made collaboratively
4. Code quality and best practices are maintained

## Project Status

🚀 **Status**: Initial Setup Phase

Current focus: Project scaffolding and requirements documentation

## Getting Started

_(To be added as development progresses)_

## License

Personal Use Only

## Contact

Demetri - Personal Project
