# Project Status & Roadmap

**Last Updated**: January 4, 2026

---

## Current State

**Production**: https://bookvault.lionikis.com

| Platform    | Status                                                        |
| ----------- | ------------------------------------------------------------- |
| Web App     | ✅ Complete - Browse, search, playback, progress, dark mode   |
| iOS App     | ✅ Complete - All 8 phases + background downloads             |
| Backend API | ✅ Complete - OpenAPI spec, contract tests, dual auth         |
| AWS         | ✅ Live - ECS Fargate, RDS PostgreSQL, S3 (514 GB, 691 books) |

**Known Issues**: None blocking. All tests passing.

---

## Recent Merges

| PR  | Description                           | Date   |
| --- | ------------------------------------- | ------ |
| #63 | iOS: Remove xcpretty dependency       | Jan 4  |
| #62 | iOS Background Downloads              | Jan 4  |
| #61 | OpenAPI Contract Test Coverage - 100% | Jan 4  |
| #51 | Presigned URLs - S3 media access      | Dec 31 |
| #50 | AWS Deployment - ECS, RDS, S3, SSL    | Dec 31 |

---

## Roadmap

### Next Up

- [ ] **Remove volume slider (iOS)** - Remove the volume slider from the iOS audio playback view
- [ ] **Duration remaining (iOS)** - Add remaining time display to the audio playback view
- [ ] **Dismiss mini-player** - Add ability to close the recent playback mini-player
- [ ] **Add sleep functionality** - Add ability to select a duration for listening where the app will fade-out and pause the audio.
- [ ] **Cold storage retrieval warning** - Warn users when audiobooks are in S3 cold storage and will take time to become available (docs/s3-archive-restore-workflow.md)

### Future Ideas

- **User Lists** - Custom collections ("Favorites", "Want to Listen", etc.)
- **Enhanced Search** - Filters, advanced syntax, saved searches
- **Analytics** - Listening stats, most played, streaks
- **Face ID** - Biometric login for iOS

---

## Completed Milestones

### December 2025 - January 2026

- ✅ AWS deployment (ECS, RDS, S3, SSL, custom domain)
- ✅ iOS app (all 8 phases + background downloads)
- ✅ OpenAPI contract tests (100% coverage)
- ✅ Presigned S3 URLs
- ✅ Code quality (SwiftLint, lint-staged)

### Earlier (December 2025)

- ✅ Web app (browse, search, playback, auth, dark mode)
- ✅ Storybook integration
- ✅ Mobile API backend (S3 streaming, range requests)

---

## Quick Commands

```bash
# Development
docker-compose up -d && npm run dev

# Testing
npm test                    # All tests
npm run test:contract       # API contract tests
npm run validate            # Full validation

# iOS
npm run api:generate:swift  # Regenerate Swift models
cd ios && xcodegen generate # Rebuild Xcode project
```

**Default credentials**: test@example.com / password123

---

## Links

| What            | Where                                                      |
| --------------- | ---------------------------------------------------------- |
| AWS Deployment  | [aws-deployment-reference.md](aws-deployment-reference.md) |
| iOS Maintenance | [mobile-ios-plan.md](mobile-ios-plan.md)                   |
| API Reference   | [api/openapi.yaml](api/openapi.yaml)                       |
| Architecture    | [architecture.md](architecture.md)                         |
