# Project Status

**Last Updated**: December 29, 2025

## Current State

Book Vault is a **production-ready** personal audiobook library application.

| Platform        | Status                                                               |
| --------------- | -------------------------------------------------------------------- |
| **Web App**     | ✅ Complete - Browse, search, playback, progress tracking, dark mode |
| **iOS App**     | ✅ Complete - All 8 phases implemented (offline mode included)       |
| **Backend API** | ✅ Complete - OpenAPI spec, contract tests, dual auth (web + mobile) |

**Next Priority**: AWS Deployment (see [development-roadmap.md](development-roadmap.md))

---

## Known Issues

None currently blocking. All tests passing.

---

## Recent Merges

| PR  | Description                                | Date   |
| --- | ------------------------------------------ | ------ |
| #47 | iOS Phase 8 - Offline Mode Support         | Dec 29 |
| #46 | iOS Phase 7 - Offline Downloads            | Dec 29 |
| #45 | iOS Library UX Alignment                   | Dec 29 |
| #44 | API DRY Refactor - Entity Detail Endpoints | Dec 28 |
| #43 | iOS Phase 6 - Search & Browse              | Dec 28 |
| #42 | iOS Phase 5 - Chapter Navigation           | Dec 28 |

---

## Quick Reference

### Web App Features

- Browse books by title, author, narrator, series, category
- Full-text search with pagination
- Audio playback with seek, speed control, chapters
- Progress tracking with auto-save
- Dark mode with theme toggle
- Storybook for component development

### iOS App Features

All phases complete:

1. ✅ Auth & Browsing
2. ✅ Audio Playback
3. ✅ Background Audio & Lock Screen
4. ✅ Progress Sync
5. ✅ Chapter Navigation
6. ✅ Search & Browse
7. ✅ Offline Downloads
8. ✅ Offline Mode

**Deferred**: User Lists (requires backend API)

### Technical Stack

- Next.js 14 + TypeScript + Tailwind CSS
- PostgreSQL + Prisma ORM
- OpenAPI 3.0 spec with contract tests
- Jest + React Testing Library (all tests passing)
- GitHub Actions CI/CD

---

## Links

| What                     | Where                                                  |
| ------------------------ | ------------------------------------------------------ |
| **Priorities & Roadmap** | [development-roadmap.md](development-roadmap.md)       |
| **iOS Maintenance**      | [mobile-ios-plan.md](mobile-ios-plan.md)               |
| **API Reference**        | [api/openapi.yaml](api/openapi.yaml)                   |
| **Architecture**         | [architecture.md](architecture.md)                     |
| **Historical Details**   | [archive/status-history.md](archive/status-history.md) |

---

## Development Commands

```bash
# Start development
docker-compose up -d && npm run dev

# Run tests
npm test                    # All tests
npm run test:contract       # API contract tests
npm run validate            # Full validation

# iOS development
npm run api:generate:swift  # Regenerate Swift models
cd ios && xcodegen generate # Rebuild Xcode project
```

**Default credentials**: test@example.com / password123
