# Archived Implementation Plans

Historical planning documents from Book Vault development (December 2025 – July 2026).

**Status**: Completed (or superseded) plans, preserved for historical reference only.

## What Was Completed

| Area                                  | Summary                                                                                                                                                                                                              |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **iOS App**                           | 8 phases (Auth → Offline Mode), 568 tests, background downloads                                                                                                                                                      |
| **Backend API**                       | OpenAPI spec, contract tests (100%), dual auth, S3 streaming                                                                                                                                                         |
| **Infrastructure**                    | AWS ECS/RDS/S3, 40% cost optimization                                                                                                                                                                                |
| **Quality**                           | SwiftLint, lint-staged, Storybook                                                                                                                                                                                    |
| **Hardening (Jul 2026)**              | Pre-restore P0+P1 security fixes + test-infra (PRs #75–#79); coverage ratchet                                                                                                                                        |
| **S3 Archive Restore (Jul 2026)**     | Full workflow Phases 0–8: stream endpoint, archive detection + restore, web + iOS UI, EventBridge poller/sync, SNS→APNs push, series-level restore, admin Health/Restores dashboard                                  |
| **Series View Toggle (Jul 2026)**     | Books/Series toggle on Catalog + Library across web and iOS: combined interleaved feed endpoints, series tiles with derived covers, "N of M in your library" ownership; retired iOS `SeriesListView` (PRs #123–#129) |
| **iOS Session + Playback (Jul 2026)** | The ~2h forced-logout/audio-stop fix (one shared token-refresh coordinator across the API and AVPlayer paths, #131) and offline login mode (#132)                                                                    |
| **iOS UI Layer (Jul 2026)**           | First XCUITest target and 15 critical-path smoke flows (#137–#139), plus the mini player moved to a full-width bottom bar (#140)                                                                                     |

## When to Read These Files

Only if investigating historical decisions or debugging edge cases.

For current development, use active docs in `docs/`.

## Files in This Directory

- `ios-*.md` — iOS implementation plans
- `openapi-*.md` — API contract and drift prevention
- `storybook-plan.md` — Component documentation setup
- `*-implementation-plan.md` — Feature implementations
- `s3-archive-restore-workflow-v2.md` — S3 cold-storage restore feature (✅ Phases 0–8)
- `series-view-toggle-plan.md` — Books/Series toggle requirements + resolved decisions (✅ shipped)
- `series-view-toggle-implementation.md` — its phased implementation plan, technical spec, and Phase 6 validation results (✅ #123–#129)
- `pre-restore-hardening-plan.md` — security/test hardening before the restore feature (✅ #75–#79)
- `ios-audio-session-persistence-plan.md` — the ~2h logout + audio-stop investigation and fix (✅ #131, verified on device). Records a corrected diagnosis: the tests disproved the initial code-inspection theory.
- `ios-offline-login-mode-plan.md` — reaching a cached library when the network is down (✅ #132)
- `ios-ui-testing-plan.md` — XCUITest target + critical-path flows (✅ #137–#139). §6b is the point-in-time record of the hit-test blocker, later diagnosed as a "Save Password?" sheet.
- `ios-mini-player-bottom-bar-plan.md` — mini player → full-width bottom bar (✅ #140). Open questions 2–4 remain deliberate follow-ups; "dismiss mini-player" is on the STATUS roadmap.
- `testing-hardening-implementation.md` — test-coverage hardening (mostly done; one Phase-5 device smoke pending)
- `testing-coverage-review.md` — point-in-time coverage review (superseded by the hardening plan)
- `app-store-submission-review-guide.md` — one-off App Store pre-submission checklist
