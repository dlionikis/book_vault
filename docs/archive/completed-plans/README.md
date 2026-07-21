# Archived Implementation Plans

Historical planning documents from Book Vault development (December 2025 – July 2026).

**Status**: Completed (or superseded) plans, preserved for historical reference only.

## What Was Completed

| Area                              | Summary                                                                                                                                                                             |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **iOS App**                       | 8 phases (Auth → Offline Mode), 568 tests, background downloads                                                                                                                     |
| **Backend API**                   | OpenAPI spec, contract tests (100%), dual auth, S3 streaming                                                                                                                        |
| **Infrastructure**                | AWS ECS/RDS/S3, 40% cost optimization                                                                                                                                               |
| **Quality**                       | SwiftLint, lint-staged, Storybook                                                                                                                                                   |
| **Hardening (Jul 2026)**          | Pre-restore P0+P1 security fixes + test-infra (PRs #75–#79); coverage ratchet                                                                                                       |
| **S3 Archive Restore (Jul 2026)** | Full workflow Phases 0–8: stream endpoint, archive detection + restore, web + iOS UI, EventBridge poller/sync, SNS→APNs push, series-level restore, admin Health/Restores dashboard |

## When to Read These Files

Only if investigating historical decisions or debugging edge cases.

For current development, use active docs in `docs/`.

## Files in This Directory

- `ios-*.md` — iOS implementation plans
- `openapi-*.md` — API contract and drift prevention
- `storybook-plan.md` — Component documentation setup
- `*-implementation-plan.md` — Feature implementations
- `s3-archive-restore-workflow-v2.md` — S3 cold-storage restore feature (✅ Phases 0–8)
- `pre-restore-hardening-plan.md` — security/test hardening before the restore feature (✅ #75–#79)
- `testing-hardening-implementation.md` — test-coverage hardening (mostly done; one Phase-5 device smoke pending)
- `testing-coverage-review.md` — point-in-time coverage review (superseded by the hardening plan)
- `app-store-submission-review-guide.md` — one-off App Store pre-submission checklist
