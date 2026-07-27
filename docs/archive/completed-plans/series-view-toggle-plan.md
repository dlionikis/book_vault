# Series View Toggle — Requirements

> **Created**: July 25, 2026
> **Status**: ✅ **Shipped** — every requirement below was implemented and verified (PRs #123–#129, July 26, 2026). Archived for historical reference.
> **Implementation**: [series-view-toggle-implementation.md](series-view-toggle-implementation.md) (phased plan, technical spec, and Phase 6 validation results)
> **Platforms**: Web + iOS

---

## Background

> **Reading this after the fact**: the survey below describes the codebase as it was _before_ this work. Most notably, `SeriesListView.swift` no longer exists — it was retired per Decision 6.

A prior investigation (July 2026) confirmed the "series" concept is **already fully built** in Book Vault — this is not a greenfield feature:

- **Schema**: `Series` model + `BookSeries` join table with a nullable `sequence: Int?`, indexed on `[seriesId, sequence]`.
- **Web**: `app/series/[id]/page.tsx` — full series detail page (header, book count, restore button, sequence-ordered book grid).
- **iOS**: `SeriesListView.swift` (alphabetical list of all series) + `SeriesDetailView.swift` (detail screen, series-level add/remove/restore, sequence-ordered book grid).
- **API**: `GET /api/browse/series` (paginated series list), `GET /api/series/{id}` (detail + books, `orderBy: sequence asc`), `POST /api/series/{id}/restore`, `POST`/`DELETE /api/library/series/{seriesId}`.
- Book cards (web `components/BookCard.tsx`) already show "Series Name, #N" inline.

**What's actually missing**, per the stated need below: there is no way to switch how the **Catalog** and **Library** views are organized — today they always render a flat list/grid of books. There's a separate series list (`SeriesListView` / `/api/browse/series`), but it's not integrated as a display mode of Catalog/Library.

## Problem / Motivation

Browsing a large audiobook collection as a flat list of individual books is harder to scan than grouping by series. The user wants the option to view **Catalog** and **Library** either the current way (flat book list) or grouped by series, without leaving the page/screen.

## Proposed Scope

Add a **view toggle** (Books / Series) to both:

1. **Catalog view** (the full library-wide browse, unfiltered by user's personal library) — web + iOS.
2. **Library view** (the user's saved/added books) — web + iOS.

When toggled to "Series":

- Show series as the grouping unit (series title, cover/art, book count), **interspersed with standalone books** (books not part of any series) as individual tiles in the same alphabetically-sorted grid — no separate section, no hiding.
- Tapping/clicking a series navigates to the existing series detail page (`app/series/[id]` / `SeriesDetailView`) — no new detail UI needed, reuse what exists. Tapping a standalone book tile goes straight to that book's detail page, same as Books mode.
- Existing filters (author, narrator, search text) apply the same as in Books mode: a series shows up if at least one of its books matches the active filter/search; a standalone book shows up under the same match rule it uses today.

When toggled to "Books": current behavior, unchanged.

## Resolved Decisions

1. **Toggle persistence**: Remembered per-view (Catalog and Library tracked independently), per-device only — `localStorage` on web, `UserDefaults` on iOS. No account-wide sync, no backend preference field.
2. **Standalone books**: Shown as "series of one" tiles, interspersed alphabetically alongside real series tiles in the same grid.
3. **Series-in-library semantics**: A series appears in Library's Series mode if the user has added _at least one_ book from it. Show a partial-ownership indicator (e.g., "2 of 5 in your library") on that series' tile.
4. **Sort order**: Alphabetical by series title, matching current `SeriesListView` / `/api/browse/series` behavior. Standalone book tiles (per Q2) are interleaved into the same alphabetical ordering by their own title.
5. **Filtering/search interaction**: Existing filters apply in Series mode exactly as in Books mode — a series matches if any of its books matches the active filter/search.
6. **iOS navigation model**: `SeriesListView` as a standalone Browse entry point is retired. Catalog's Series-mode toggle becomes the single way to browse all series on iOS. (Web has no equivalent standalone series-list page today, so nothing to retire there.)

## Implementation Note: API Surface Likely Needs Real Changes, Not Just Reuse

The original assumption was that Series mode could reuse `/api/browse/series` as-is. Given the resolved decisions above, that's no longer accurate:

- **Catalog Series mode** needs a combined, alphabetically-interleaved feed of series _and_ standalone books together — `/api/browse/series` today only returns series. Either a new combined endpoint, or the client merges two existing calls (`/api/browse/series` + a "standalone books" query) and interleaves client-side. Given filters must apply to both series and standalone books consistently (Q5), and pagination needs to work across the merged, interleaved set, a single combined endpoint is likely cleaner than client-side merging.
- **Library Series mode** needs a library-scoped variant that: (a) only includes series with ≥1 owned book, (b) returns an owned/total count per series for the partial-ownership indicator, and (c) includes standalone owned books interleaved the same way. This does not exist today — `POST`/`DELETE /api/library/series/{seriesId}` are write endpoints, not this read shape.
- Both of the above are new or modified endpoints and must be added to `docs/api/openapi.yaml` **before** implementation, per the project's OpenAPI-first rule, with corresponding TS + Swift model regeneration (`npm run api:generate:ts`, `npm run api:generate:swift`).

## Explicitly Out of Scope (per this request)

- Changes to the series detail page itself (already works, sequence-ordered).
- Changes to how series metadata is imported/assigned (Libation/ASIN import is out of scope — read-only per project rules).
- Book ordering within a series (confirmed working correctly, not part of this work).
- Account-wide/cross-device sync of the toggle preference (per-device only, resolved above).

## Acceptance Criteria

- [x] Catalog view has a visible, discoverable toggle between "Books" and "Series" display modes, on web and iOS.
- [x] Library view has the same toggle, tracked independently of Catalog's toggle state, both persisted per-device (`localStorage` / `UserDefaults`).
- [x] Series mode shows series and standalone books interleaved in one alphabetically-sorted grid, on both Catalog and Library.
- [x] Library's Series mode shows an owned/total count per partially-owned series (e.g., "2 of 5").
- [x] Active filters (author, narrator, search) apply consistently in both Books and Series modes. — _Narrower in practice than written: implementation found **no** author/narrator/search filters exist on Catalog or Library (only a `sort` param on web Catalog). Resolved per Decision B by hiding `SortDropdown` in Series mode, since Series mode is always alphabetical. If real filters are added later, they must be applied to the series-view endpoints too._
- [x] Tapping a series tile navigates to the existing series detail page/screen; tapping a standalone book tile navigates to that book's existing detail page.
- [x] iOS: `SeriesListView` standalone entry point removed from Browse; Catalog's Series-mode toggle is the sole path to browsing all series.
- [x] Dark mode variants included (web) per project convention.
- [x] `docs/api/openapi.yaml` updated first for any new/modified endpoint (combined Catalog series+standalone feed; library-scoped series+ownership feed), followed by `npm run api:generate:ts` and `npm run api:generate:swift`, per the project's OpenAPI-first rule.
