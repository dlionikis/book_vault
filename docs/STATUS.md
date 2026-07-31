# Project Status & Roadmap

**Last Updated**: July 31, 2026 _(Recent Merges table reflects PRs through #147; update when new PRs land)_

---

## Current State

**Production**: https://bookvault.lionikis.com

| Platform    | Status                                                        |
| ----------- | ------------------------------------------------------------- |
| Web App     | ✅ Complete - Browse, search, playback, progress, dark mode   |
| iOS App     | ✅ Complete - All 8 phases + background downloads             |
| Backend API | ✅ Complete - OpenAPI spec, contract tests, dual auth         |
| AWS         | ✅ Live - ECS Fargate, RDS PostgreSQL, S3 (514 GB, 691 books) |

**Known Issues**: See [analysis/architecture-review-2026-07.md](analysis/architecture-review-2026-07.md) — **refreshed July 19, 2026** (every finding re-verified against current code). All P0 security holes and all test-infrastructure defects from the original review are **resolved** (hardening PRs #75–#79 + the dependency-upgrade ladder PRs #88–#101). Remaining, lower-severity backlog: **SEC-2** (mobile bearer path doesn't re-check the DB for deleted users), **SEC-4** (ffprobe still `exec` + no timeout), the `api-helpers.ts` limit cap and the POST /chapters leak (both fixed in #103), and a few low-value component tests. **D-5 resolved** (error/loading/not-found boundaries + AudioPlayer `dark:` variants shipped with the restore UI in #106). Dependency state: Node 24 LTS, Next 16 / React 19 / Prisma 6, `npm audit` 0 high/critical; only **Prisma 6 → 7** remains on the upgrade ladder. Current product notable: **~91% of the S3 library is in the Intelligent-Tiering Archive Access tier** (695 of 764 audio files, per the July 20 sync). The restore workflow is now **fully live across web + iOS** (Phases 0–8): archived books show a badge and auto-initiate a restore on play; a 5-min poller + nightly sync keep state current; SNS→APNs push notifies when a restore completes (validated on-device); series-level "Restore All Archived"; and an admin Health/Restores dashboard for infra observability ([archive/completed-plans/s3-archive-restore-workflow-v2.md](archive/completed-plans/s3-archive-restore-workflow-v2.md) → "Deployed Infrastructure").

---

## Recent Merges

| PR       | Description                                                                                         | Date   |
| -------- | --------------------------------------------------------------------------------------------------- | ------ |
| #145–148 | **CarPlay**: chapter loading in the player, scene + templates, Now Playing (blocked on entitlement) | Jul 31 |
| #144     | iOS Swift 6 language mode + strict concurrency; next/next-auth patches                              | Jul 31 |
| #141–143 | iOS audio-interruption resume; audio-session category fix (iOS 26)                                  | Jul 30 |
| #140     | iOS mini player moved to a full-width bottom bar                                                    | Jul 30 |
| #137–139 | iOS XCUITest target, login + critical-path smoke flows, hit-test fix                                | Jul 30 |
| #133–136 | iOS modernization: singleton observation, Sendable, NavigationStack, #Preview                       | Jul 30 |
| #131–132 | Shared token-refresh coordinator (~2h logout fix); offline login mode                               | Jul 28 |
| #123–130 | Series View Toggle: Books/Series toggle on Catalog + Library (web + iOS)                            | Jul 26 |
| #119–122 | Admin infra health checks, Restores tab, ECS running tasks                                          | Jul 25 |
| #87      | iOS Phase 6: Playwright web smoke (E2E)                                                             | Jul 17 |
| #86      | iOS Phase 5: AuthenticatedResourceLoader + tests                                                    | Jul 17 |
| #83–85   | iOS test coverage: SystemKeychain, `/api/audio`, CoverCacheManager                                  | Jul 16 |
| #79      | Pre-restore hardening P0+P1 (PRs #76–#78 landed)                                                    | Jul 14 |
| #75      | Security P0: auth on images route, admin-gate chapters                                              | Jul 12 |
| #72      | Admin dashboard with AWS monitoring                                                                 | Jul 8  |

---

## Roadmap

### Next Up

- [x] **Pre-restore hardening (P0+P1)** - Security fixes + test infrastructure ([archive/completed-plans/pre-restore-hardening-plan.md](archive/completed-plans/pre-restore-hardening-plan.md)) — ✅ complete (PRs #75–#79)
- [x] **S3 archive restore workflow** - Restore pipeline + push notifications ([archive/completed-plans/s3-archive-restore-workflow-v2.md](archive/completed-plans/s3-archive-restore-workflow-v2.md)) — ✅ **complete (Phases 0–8, July 2026)**: backend + web + iOS, SNS→APNs push (validated on-device), series-level restore, and the admin Health/Restores dashboard tabs (PRs #88, #98–#121)
- [x] **Series view toggle (web + iOS)** - Books/Series toggle on Catalog and Library, with series tiles, derived covers, and "N of M in your library" ownership ([archive/completed-plans/series-view-toggle-implementation.md](archive/completed-plans/series-view-toggle-implementation.md)) — ✅ **complete (all phases, July 26, 2026)**, PRs #123–#129. iOS `SeriesListView` retired in favor of the Catalog toggle.
- [x] **iOS ~2-hour logout + audio stop** - Shared token-refresh coordinator across the API and AVPlayer streaming paths ([plans/ios-audio-session-persistence-plan.md](archive/completed-plans/ios-audio-session-persistence-plan.md)) — ✅ **complete (July 30, 2026)**, PR #131, verified on device
- [x] **Mini player → bottom bar (iOS)** - Full-width persistent bar above the tab bar, with XCUITest occlusion coverage ([plans/ios-mini-player-bottom-bar-plan.md](archive/completed-plans/ios-mini-player-bottom-bar-plan.md)) — ✅ **complete (July 30, 2026)**, PR #140
- [x] **iOS Swift 6 language mode** - `SWIFT_VERSION: 6.0` + `SWIFT_STRICT_CONCURRENCY: complete` on all three targets ([archive/completed-plans/ios-modernization-sequencing.md](archive/completed-plans/ios-modernization-sequencing.md)) — ✅ **complete (July 31, 2026)**, PR #144. Completes Plan A (A0–A6).
- [⏸️] **CarPlay (v1: browse + play)** - Scene, browse templates, Now Playing with chapter navigation ([plans/carplay-implementation-plan.md](plans/carplay-implementation-plan.md)) — **all buildable work done** (PRs #145–#148); **BLOCKED on the Apple CarPlay audio entitlement**. See below.
- [ ] **Remove volume slider (iOS)** - Remove the volume slider from the iOS audio playback view
- [ ] **Duration remaining (iOS)** - Add remaining time display to the audio playback view
- [ ] **Dismiss mini-player** - Add ability to close the recent playback mini-player
- [ ] **Add sleep functionality** - Add ability to select a duration for listening where the app will fade-out and pause the audio.
- [x] **Cold storage retrieval warning** - Warn users when audiobooks are in S3 cold storage and will take time to become available — ✅ shipped as part of the restore workflow ([archive/completed-plans/s3-archive-restore-workflow-v2.md](archive/completed-plans/s3-archive-restore-workflow-v2.md))
- [ ] **Dependency major upgrades** - Phased Next 16 / React 19 / Prisma 7 / Storybook / ESLint bumps; clears residual advisories ([docs/plans/dependency-major-upgrades.md](plans/dependency-major-upgrades.md)) — safe in-semver updates already done

### ⏸️ Blocked

**CarPlay — waiting on Apple.** Every task that can be done from the codebase is
done: the CarPlay scene, Library/Series/Downloaded browse templates, auth-state
switching, offline/error states, the Now Playing template with chapter
navigation, and 29 unit tests. Shipped across PRs #145–#148.

Three things remain, none of them code:

| Blocker                                  | What it needs                                                                                                                                 |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Apple CarPlay audio entitlement** (A0) | A request to Apple for `com.apple.developer.carplay-audio`. **Not yet submitted.** Weeks of lead time. This is the critical path to shipping. |
| **Entitlement wiring** (A4)              | Add the entitlement + update provisioning, once Apple approves.                                                                               |
| **Device verification** (C4, C5)         | A CarPlay Simulator pass, then one real head-unit pass. **C4 needs no entitlement and can be done today.**                                    |

⚠️ **Nothing in the CarPlay feature has run against a live CarPlay connection.**
The templates compile and the logic is unit-tested, but only the Simulator pass
(C4) can confirm the scene connects, rows and artwork render at a real trait
collection, and phone↔CarPlay playback stays in sync.

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
