# AI Agent Instructions

This file provides guidance for AI agents working on the Book Vault project.

## First Steps When Joining This Project

1. **Read** `.ai/PROJECT_CONTEXT.md` - Understand the project's purpose and current state
2. **Read** `.ai/DEVELOPMENT_GOALS.md` - Understand the roadmap and priorities
3. **Read** `ARCHITECTURE.md` - Understand the technical decisions and design
4. **Review** `README.md` - Get familiar with the project overview

## Core Principles

### 1. Context Preservation

- Always update `.ai/PROJECT_CONTEXT.md` when making significant changes
- Update `.ai/DEVELOPMENT_GOALS.md` when completing phases or tasks
- Keep `CHANGELOG.md` updated with notable changes

### 2. Documentation-First

- Document decisions before implementing
- Update architecture docs when changing patterns
- Keep README in sync with actual capabilities

### 3. Incremental Development

- Make small, testable changes
- Commit frequently with clear messages
- Don't try to implement everything at once

### 4. Testing Matters

- Write tests for core functionality
- Ensure existing tests pass before committing
- Test imports with real data samples

## File Organization Reference

### Documentation Files

- `README.md` - Project overview and getting started
- `ARCHITECTURE.md` - Technical design and decisions
- `CONTRIBUTING.md` - Development workflow
- `CHANGELOG.md` - Version history
- `.ai/PROJECT_CONTEXT.md` - Persistent project context for AI
- `.ai/DEVELOPMENT_GOALS.md` - Roadmap and goals

### Configuration Files

- `.env.example` - Environment variable template
- `.gitignore` - Git exclusions
- `package.json` - Dependencies and scripts (when created)
- `tsconfig.json` - TypeScript configuration (when created)

## Common Tasks

### Starting Development

```bash
# Install dependencies
npm install

# Set up environment
cp .env.example .env.local
# Edit .env.local with your values

# Start database (Docker)
docker-compose up -d

# Run migrations
npm run db:migrate

# Start dev server
npm run dev
```

### Creating a New Feature

1. Check if it aligns with `.ai/DEVELOPMENT_GOALS.md`
2. Create a feature branch: `git checkout -b feat/feature-name`
3. Implement the feature
4. Write/update tests
5. Update relevant documentation
6. Commit with clear message
7. Test thoroughly

### Adding a Database Migration

1. Create migration file in appropriate directory
2. Test migration up and down
3. Document schema changes in `ARCHITECTURE.md`
4. Commit migration file

### Updating Dependencies

1. Review changes in dependency updates
2. Test thoroughly after updating
3. Update documentation if APIs changed
4. Note breaking changes in `CHANGELOG.md`

## Key Technical Decisions

### Technology Stack

- **Frontend**: Next.js 14+ with TypeScript
- **Backend**: Next.js API Routes
- **Database**: PostgreSQL
- **Storage**: AWS S3 (production) or local (development)
- **Authentication**: NextAuth.js

### Data Source

- **Path**: `/Volumes/BeeDrive/Libation/`
- **Structure**: One folder per book
- **Files**: `.metadata.json`, `.mp3`, `.jpg`, `.cue`

### Important Constraints

1. **Never modify source files** in Libation directory
2. **Read-only access** to audiobook files
3. **Single user initially**, but design for multi-user future
4. **AWS deployment target**, but local dev friendly

## Metadata Structure Reference

Quick reference for Libation JSON structure:

```json
{
  "asin": "string",
  "title": "string",
  "authors": [{"name": "string", "asin": "string"}],
  "narrators": [{"name": "string", "asin": "string"}],
  "series": [{"title": "string", "sequence": "string", "asin": "string"}],
  "publisher_summary": "HTML string",
  "category_ladders": [{"root": "string", "ladder": [{"name": "string"}]}],
  "runtime_length_min": number
}
```

## Search Requirements

Users should be able to search by:

- Author name
- Narrator name
- Book title
- Series name
- Category
- Book description content

Full-text search must work across all these fields.

## Series Handling

- Books in the same series have the same `series.title`
- Books have different `series.sequence` values
- Sequence can be numeric ("1", "2") or descriptive ("1.5", "Prequel")
- Display series books in sequence order

## Common Pitfalls to Avoid

1. **Don't hard-code paths** - Use environment variables
2. **Don't commit secrets** - Use .env files (gitignored)
3. **Don't skip migrations** - Always use migration system
4. **Don't modify Libation files** - Read-only!
5. **Don't forget indexes** - Database performance matters

## When Making Architecture Changes

1. Discuss in comments or PR description
2. Update `ARCHITECTURE.md` with rationale
3. Consider impact on existing code
4. Update `.ai/PROJECT_CONTEXT.md` if it affects project direction

## Testing Guidelines

### Unit Tests

- Test core business logic
- Test data parsing
- Test utility functions

### Integration Tests

- Test API endpoints
- Test database operations
- Test import process

### E2E Tests

- Test critical user flows
- Test authentication
- Test search functionality
- Test audio playback

## Debugging Tips

### Import Issues

- Check file permissions on Libation directory
- Validate JSON format of metadata files
- Check for special characters in filenames

### Database Issues

- Verify connection string
- Check migration status
- Review indexes

### Authentication Issues

- Verify NEXTAUTH_SECRET is set
- Check session configuration
- Review cookie settings

## Communication Style

When explaining changes or decisions:

- Be clear and concise
- Explain the "why" not just the "what"
- Link to relevant documentation
- Provide examples when helpful

## Version Control

### Commit Messages

Follow conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Branch Naming

- `feat/feature-name` - New features
- `fix/bug-description` - Bug fixes
- `docs/what-changed` - Documentation
- `refactor/what-improved` - Code improvements
- `test/what-tested` - Test additions

## Questions to Ask

Before implementing, consider:

- Does this align with the project goals?
- Is this the simplest solution?
- Will this scale?
- Is this maintainable?
- Are there security implications?
- Does this need documentation?

## Resources

### External Documentation

- [Next.js Docs](https://nextjs.org/docs)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [AWS Documentation](https://docs.aws.amazon.com/)

### Project Documentation

- Start with `README.md`
- Technical details in `ARCHITECTURE.md`
- Context in `.ai/PROJECT_CONTEXT.md`
- Goals in `.ai/DEVELOPMENT_GOALS.md`

## Getting Help

For clarification on:

- **Project goals**: Check `.ai/DEVELOPMENT_GOALS.md`
- **Technical architecture**: Check `ARCHITECTURE.md`
- **Current state**: Check `.ai/PROJECT_CONTEXT.md`
- **Data structure**: Check `ARCHITECTURE.md` database schema section

## Maintaining Context

At the end of a work session:

1. Update `.ai/PROJECT_CONTEXT.md` "Current State" section
2. Mark completed tasks in `.ai/DEVELOPMENT_GOALS.md`
3. Add entries to `CHANGELOG.md` for significant changes
4. Commit all documentation updates

This ensures the next AI agent (or human) can pick up where you left off!

---

**Remember**: This is an AI-first project. Clear documentation is not just nice to have—it's essential for continuity and success.

**Last Updated**: December 21, 2025
