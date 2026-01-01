# Project Status

**Last Updated**: December 31, 2025

## Current State

Book Vault is a **production-ready** personal audiobook library application, now **live in production**.

| Platform        | Status                                                               |
| --------------- | -------------------------------------------------------------------- |
| **Production**  | ✅ Live at https://bookvault.lionikis.com                            |
| **Web App**     | ✅ Complete - Browse, search, playback, progress tracking, dark mode |
| **iOS App**     | ✅ Complete - All 8 phases implemented (offline mode included)       |
| **iOS Tests**   | ✅ Complete - 568 tests passing, real service coverage               |
| **Backend API** | ✅ Complete - OpenAPI spec, contract tests, dual auth (web + mobile) |

**AWS Infrastructure**:

- ECS Fargate (container hosting)
- RDS PostgreSQL (database)
- S3 (media storage: 514 GB, 691 books)
- Application Load Balancer + SSL

---

## Known Issues

None currently blocking. All tests passing.

---

## Recent Merges

| PR  | Description                                              | Date   |
| --- | -------------------------------------------------------- | ------ |
| #51 | Presigned URLs - S3 media access, IAM task role support  | Dec 31 |
| #50 | AWS Deployment - ECS Fargate, RDS, S3, Domain/SSL        | Dec 31 |
| #49 | Code Quality - lint-staged, SwiftLint, dead code removal | Dec 30 |
| #48 | iOS Testing - 568 tests, real service coverage           | Dec 30 |
| #47 | iOS Phase 8 - Offline Mode Support                       | Dec 29 |
| #46 | iOS Phase 7 - Offline Downloads                          | Dec 29 |
| #45 | iOS Library UX Alignment                                 | Dec 29 |

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
| **AWS Deployment**       | [aws-deployment-plan.md](aws-deployment-plan.md)       |
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
