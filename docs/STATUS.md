# Project Status & Roadmap

**Last Updated**: July 17, 2026 _(Recent Merges table reflects PRs through #87; update when new PRs land)_

---

## Current State

**Production**: https://bookvault.lionikis.com

| Platform    | Status                                                        |
| ----------- | ------------------------------------------------------------- |
| Web App     | ✅ Complete - Browse, search, playback, progress, dark mode   |
| iOS App     | ✅ Complete - All 8 phases + background downloads             |
| Backend API | ✅ Complete - OpenAPI spec, contract tests, dual auth         |
| AWS         | ✅ Live - ECS Fargate, RDS PostgreSQL, S3 (514 GB, 691 books) |

**Known Issues**: See [analysis/architecture-review-2026-07.md](analysis/architecture-review-2026-07.md) — **refreshed July 19, 2026** (every finding re-verified against current code). All P0 security holes and all test-infrastructure defects from the original review are **resolved** (hardening PRs #75–#79 + the dependency-upgrade ladder PRs #88–#101). Remaining, lower-severity backlog: **SEC-2** (mobile bearer path doesn't re-check the DB for deleted users), **SEC-4** (ffprobe still `exec` + no timeout), **D-5** (no error/loading boundaries; AudioPlayer has no `dark:` variants — fold into the restore UI), an uncapped `limit` in `lib/api-helpers.ts` entity-detail routes, and a few low-value component tests. Dependency state: Node 24 LTS, Next 16 / React 19 / Prisma 6, `npm audit` 0 high/critical; only **Prisma 6 → 7** remains on the upgrade ladder. Current product notable: a large portion of the S3 library is in the Intelligent-Tiering Archive Access tier and unstreamable until the restore workflow ships (a July 12 HeadObject sample found 5 of 8 audio files archived — [plans/s3-archive-restore-workflow-v2.md](plans/s3-archive-restore-workflow-v2.md)).

---

## Recent Merges

| PR     | Description                                                        | Date   |
| ------ | ------------------------------------------------------------------ | ------ |
| #87    | iOS Phase 6: Playwright web smoke (E2E)                            | Jul 17 |
| #86    | iOS Phase 5: AuthenticatedResourceLoader + tests                   | Jul 17 |
| #83–85 | iOS test coverage: SystemKeychain, `/api/audio`, CoverCacheManager | Jul 16 |
| #79    | Pre-restore hardening P0+P1 (PRs #76–#78 landed)                   | Jul 14 |
| #75    | Security P0: auth on images route, admin-gate chapters             | Jul 12 |
| #72    | Admin dashboard with AWS monitoring                                | Jul 8  |

---

## Roadmap

### Next Up

- [x] **Pre-restore hardening (P0+P1)** - Security fixes + test infrastructure ([docs/plans/pre-restore-hardening-plan.md](plans/pre-restore-hardening-plan.md)) — ✅ complete (PRs #75–#79)
- [ ] **S3 archive restore workflow** - Restore pipeline + push notifications ([docs/plans/s3-archive-restore-workflow-v2.md](plans/s3-archive-restore-workflow-v2.md)) — **in progress** (Phase 0 ✅ shipped in #88; plan accuracy re-verified July 19; Phases 1–8 next)
- [ ] **Remove volume slider (iOS)** - Remove the volume slider from the iOS audio playback view
- [ ] **Duration remaining (iOS)** - Add remaining time display to the audio playback view
- [ ] **Dismiss mini-player** - Add ability to close the recent playback mini-player
- [ ] **Add sleep functionality** - Add ability to select a duration for listening where the app will fade-out and pause the audio.
- [ ] **Cold storage retrieval warning** - Warn users when audiobooks are in S3 cold storage and will take time to become available ([docs/plans/s3-archive-restore-workflow-v2.md](plans/s3-archive-restore-workflow-v2.md))
- [ ] **Dependency major upgrades** - Phased Next 16 / React 19 / Prisma 7 / Storybook / ESLint bumps; clears residual advisories ([docs/plans/dependency-major-upgrades.md](plans/dependency-major-upgrades.md)) — safe in-semver updates already done

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

**Default credentials**: testuser / password123

---

## Links

| What            | Where                                                      |
| --------------- | ---------------------------------------------------------- |
| AWS Deployment  | [aws-deployment-reference.md](aws-deployment-reference.md) |
| iOS Maintenance | [mobile/architecture.md](mobile/architecture.md)           |
| API Reference   | [api/openapi.yaml](api/openapi.yaml)                       |
| Architecture    | [architecture.md](architecture.md)                         |
