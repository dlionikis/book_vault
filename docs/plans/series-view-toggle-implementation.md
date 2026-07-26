# Series View Toggle — Implementation Plan

> **Created**: July 25, 2026
> **Status**: Fully specced (schema, pagination algorithm, component fields, test tasks) — ready to begin Phase 1
> **Requirements**: [series-view-toggle-plan.md](series-view-toggle-plan.md) (read that first — this doc assumes its resolved decisions)
> **Platforms**: Web + iOS

---

## Terminology used in this doc

- **"Catalog"** = the full-library, unfiltered-by-ownership book browse. On iOS this is literally `CatalogView`/tab. On web this is the root `/` page, which keeps its existing **"All Books"** label (per decision — no rename to "Catalog" on web UI copy). This doc uses "Catalog" only as shorthand for "the root/All Books page" when talking about both platforms together.
- **"Library"** = the user's saved-books view. Same term, real UI label, on both platforms already.
- **"Browse"** = the pre-existing, separate Authors/Narrators/Series/Categories metadata browser (`/browse/*` on web, `BrowseView`/`BrowseListView` on iOS). Mostly out of scope, except iOS's `SeriesListView` entry point, which is being retired per the requirements doc.

---

## Pre-implementation findings that change scope from the original requirements doc

A code survey (July 2026) surfaced several facts not known when the requirements doc was drafted. These directly shape the tasks below:

1. **Web has no "Catalog" label** — confirmed keeping "All Books" (decision made).
2. **Web's Library page (`app/library/page.tsx`) does not use `BookGrid`/`BookCard`** — it has fully separate, hand-rolled inline card markup, no pagination (fetches the whole library in one query), and no `sort`/filter params at all. Per decision, **this gets refactored to use `BookGrid`/`BookCard` as a prerequisite** before the toggle is added, to avoid building the toggle twice.
3. **Web's Catalog and Library pages both bypass their own REST APIs** — they query Prisma directly in Server Components (`getBooks()` in `app/page.tsx`, `getLibraryBooks()` in `app/library/page.tsx`). Only iOS and tests actually call `/api/books` and `/api/library`. New combined-feed logic can live as shared `lib/` query functions called from both the page and (if needed for iOS) a route handler — not bolted onto the existing routes in a way that changes their existing response shape for current consumers.
4. **No real author/narrator/text-search filters exist on Catalog or Library today** — only a `sort` query param on web Catalog (`title|author|narrator|series`, though only `title` is DB-driven; the rest sort in-memory post-fetch). The requirements doc's Q5 ("filters apply the same in Series mode") in practice only needs to cover `sort`, which simplifies that work considerably.
5. **No series-tile component exists on either platform.** Needs to be built from scratch on both web (`SeriesTile.tsx`, new) and iOS (`SeriesGridItem`, new — since `BrowseListView`'s row is a list row, not a grid tile).
6. **`Series` has no cover-art field in the schema**, and books' `coverUrl` lives on `Book`, not `Series`. A series tile's cover must be derived — the lowest-`sequence` book in the series that has a non-null `coverUrl` (falling back to the first book found if all sequences are null). This is a computed value, not a stored one — no migration needed for this specifically.
7. **`SeriesWithBookCount` (API schema + generated TS/Swift models) has no owned/total field** — needed for Library's Series-mode partial-ownership indicator. Schema addition required.
8. **iOS Library pagination is fake** (fetches the entire library, then slices client-side) while **iOS Catalog pagination is real server-side infinite scroll**. The two screens' Series-mode data loading will differ in shape as a result — Catalog's Series mode should be real server pagination; Library's Series mode can reasonably follow the existing "fetch all, paginate client-side" pattern already established there, since library sizes are personal-scale, not catalog-scale.
9. **iOS already has a generic, config-driven list component** (`BrowseListView<Item, Response>` + `BrowseListConfiguration`) but it renders an alphabetically-sectioned `List`, not a grid — not directly reusable for a grid-based Series-mode display. The existing `BookGridItem` (used by Catalog/Library/SeriesDetail) is the right pattern to mirror for a new `SeriesGridItem`.
10. **iOS sends a `sortBy` query param to `/api/books`; the server only reads `sort`.** Pre-existing, unrelated latent bug — noted here so it isn't confused with new work, but fixing it is out of scope for this plan unless it blocks the toggle work (it doesn't).

---

## Technical spec: combined feed response shape

Both new endpoints (`GET /api/browse/catalog-series-view` for Catalog, and its Library-scoped
counterpart in Phase 4) return the **same envelope shape** — a single alphabetically-sorted,
paginated array where each item is tagged with a `type` discriminator. This was chosen over a
`{series: [...], standaloneBooks: [...]}` two-array shape specifically so the server does the
interleaving/sorting/pagination math once, and the client only needs to switch on `type` per item
— no client-side merge logic on either platform.

### OpenAPI schema additions (`docs/api/openapi.yaml`)

**Note on shape**: originally speced as a `oneOf`+`discriminator` union. Changed to two plain
optional fields (`series?`/`book?`, exactly one ever present) instead — this codebase has no
existing precedent for `oneOf`/`discriminator` and has hit two prior OpenAPI-to-Swift-codegen
incidents on unusual schema shapes (generator version drift renaming inline schemas; a
free-form-object shape that "generated successfully" but didn't compile in Swift, see
`docs/development-process.md` / prior PR #112, #119 history). Plain optional fields are a shape
every generator handles correctly, at the small cost of the type system not preventing both
`series` and `book` being present at once (a runtime/test-coverage concern, not a codegen risk).

```yaml
SeriesWithBookCount: # existing schema — add coverUrl
  type: object
  required: [id, title, bookCount]
  properties:
    id: { type: string, format: uuid }
    title: { type: string }
    asin: { type: string, nullable: true }
    bookCount: { type: integer, minimum: 0 }
    coverUrl:
      type: string
      nullable: true
      description: >
        Derived, not stored — the coverUrl of the lowest-`sequence` book in
        this series that has a non-null coverUrl. Null if the series has no
        books with cover art at all.
    ownedCount:
      type: integer
      minimum: 0
      description: >
        Number of this series' books present in the requesting user's
        library. Present only in Library-scoped responses (omitted/absent
        on Catalog responses, where "ownership" isn't a meaningful concept).

CatalogSeriesViewItem:
  type: object
  description: >
    Exactly one of `series`/`book` is present per item — never both, never
    neither. Not enforced by the schema itself (see note above); enforced by
    server-side construction and covered by the Phase 2 unit tests.
  properties:
    series:
      $ref: '#/components/schemas/SeriesWithBookCount'
    book:
      $ref: '#/components/schemas/Book' # LibraryBook, for the Library-scoped variant

GetCatalogSeriesView200Response:
  type: object
  required: [results, pagination]
  properties:
    results:
      type: array
      items: { $ref: '#/components/schemas/CatalogSeriesViewItem' }
    pagination:
      $ref: '#/components/schemas/Pagination' # existing shared {page, limit, total, pages} schema
```

The sort key exposed to the client for each item is always the item's own title (`series.title`
for a series item, `book.title` for a book item) — this is what "alphabetically interleaved"
means concretely: one global sort by title across both item kinds. Client-side, an item is a
series item iff `item.series != null` (check `series` first, not `book`, for consistency).

The Library-scoped variant (Phase 4) reuses the same `CatalogSeriesViewItem` shape but: (a) its
`series` values always carry `ownedCount`, (b) its `book` values are `LibraryBook` (has
`addedAt`) not bare `Book`, and (c) only series with `ownedCount >= 1` and only owned standalone
books are included at all. Name the response envelope `GetLibrarySeriesView200Response` in the
spec (reusing `CatalogSeriesViewItem` for `results`, since the item shape itself doesn't need to
differ — only which concrete `Book` vs. `LibraryBook` values get placed into the `book` field at
request time, which OpenAPI's structural typing already allows without a separate schema).

### Pagination algorithm (server-side, both Catalog and Library variants)

The naive approach — fetch every series and every standalone book, sort, slice — is fine at this
app's scale (personal library, hundreds not millions of rows) and is what's specified below.
**If this ever needs to scale further, revisit with a real keyset pagination scheme** (not
speced here — not warranted at current scale, would be premature).

1. Fetch a **lightweight sort-key list** for both kinds in parallel — not full records yet:
   - Series: `prisma.series.findMany({ select: { id: true, title: true }, orderBy: { title: 'asc' } })` (Library variant: add a `where` that keeps only series with a matching `BookSeries`→`UserListBook` join — see note below).
   - Standalone books: `prisma.book.findMany({ where: { series: { none: {} } }, select: { id: true, title: true }, orderBy: { title: 'asc' } })` (Library variant: `where: { series: { none: {} }, library entries matching the user's "My Library" list }`).
2. Merge-sort the two `{id, title, type}` lists by `title` (simple `Array.prototype.sort` on the concatenated list is sufficient at this scale — no need for a true O(n) merge given both inputs are already sorted and the total is small).
3. Slice the merged list to `[skip, skip + limit)` for the requested page — this gives the exact page's ordered `{id, type}` list.
4. Fetch **full records** for only that page's ids — one `prisma.series.findMany({ where: { id: { in: [...] } }, include: { _count: { select: { books: true } } } })` and one `prisma.book.findMany({ where: { id: { in: [...] } }, include: BOOK_INCLUDE })` — then re-assemble in the order determined by step 3 (the `WHERE id IN (...)` queries do not preserve input order, so re-sort the fetched records against the step-3 id order before returning).
5. For each series in the page, derive `coverUrl`: `prisma.bookSeries.findMany({ where: { seriesId: { in: pageSeriesIds } }, orderBy: [{ sequence: 'asc' }], include: { book: { select: { coverUrl: true } } } })`, then per series take the first row with a non-null `book.coverUrl` (still ordered by `sequence asc`, nulls-first per Postgres default — same ordering behavior already relied on by the existing series detail page).
6. Run `transformBook`/`getCoverUrl` (existing helpers in `lib/book-transformer.ts`, `lib/media.ts`) on the book-type items and the derived series covers, so presigned S3 URLs are generated consistently with every other endpoint.
7. Total count for the `pagination` envelope = `mergedList.length` from step 2 (already computed, no extra count query needed).

This algorithm is identical in shape for both the Catalog and Library variants — only step 1's
`where` clauses differ (Library adds ownership filters). Implement as one shared function
parameterized by an optional "scope" (all series/books vs. library-owned only), not two
independent implementations.

### `SeriesCard.tsx` (web) — field-level spec

A container component (`SeriesViewGrid`?) maps over `results` and, for each `CatalogSeriesViewItem`, renders `SeriesTile` when `item.series != null` or the existing `BookCard` unchanged when `item.book != null` (check `series` first). This avoids teaching `BookCard` anything about the new response shape.

`SeriesTile` renders:

- Cover image: `item.series.coverUrl`, same `next/image` treatment as `BookCard`'s cover (same aspect ratio/rounding/dark-mode border), with the same placeholder/fallback `BookCard` uses today when `coverUrl` is null (check `components/BookCard.tsx` for the exact fallback markup and mirror it, don't invent a new one).
- Title: `item.series.title`, same typography treatment as `BookCard`'s title line.
- Book count badge: `"{bookCount} books"` (Catalog), or `"{ownedCount} of {bookCount} in your library"` when `ownedCount < bookCount` (Library) / `"{bookCount} books"` when `ownedCount === bookCount` (fully owned, Library).
- No author/narrator/runtime lines (a series has no single value for these) — this is the visual difference from `BookCard` that justifies a separate component rather than overloading `BookCard` with a "series mode."
- Wrapped in a `Link` to `/series/${item.series.id}`, same as today's inline series links.

### `SeriesGridItem` (iOS) — field-level spec

Mirrors the web spec above, in SwiftUI: a new `View` taking a `SeriesWithBookCount`-conforming model, rendering cover (`AsyncImage` or whatever `BookGridItem` currently uses — match it exactly), title, and the same book-count/ownership badge logic. Standalone book items in the combined feed continue to render via the existing `BookGridItem` unchanged. Both wrapped in `NavigationLink` — `SeriesGridItem` links to `SeriesDetailView(seriesId:)`, `BookGridItem` keeps its existing destination.

### Loading / empty / error states (both platforms, both Catalog and Library Series-mode)

- **Loading**: reuse each platform's existing skeleton/spinner pattern (web: `BookGrid`'s existing skeleton-with-8-placeholders, applied identically while the combined feed loads; iOS: `CatalogView`'s existing `ProgressView` pattern at the end of the grid for infinite-scroll, or a full-screen spinner on first load — match whatever Books mode already does for consistency, don't invent a new loading treatment for Series mode specifically).
- **Empty** (zero series and zero standalone books — realistically only possible on a brand-new/empty Library): show the same "no books" empty-state copy/illustration each page already has for Books mode (web: `BookGrid`'s existing empty state; iOS: `LibraryView`'s existing empty state), not a new Series-specific empty state.
- **Error** (fetch failure): match each existing page's current error handling for its Books-mode fetch — if `CatalogView`/`LibraryView` currently show a retry button or inline error message on `fetchBooks`/`fetchLibrary` failure, Series mode's fetch failures should look identical, just triggered by the new endpoint instead.

### Test coverage tasks (add explicitly to each phase, not deferred to Phase 6)

- **Phase 1**: contract test additions in the existing OpenAPI contract-test suite (`npm run test:contract`) covering the new schemas/endpoints — this is likely auto-covered by the existing contract-test generator once the spec is updated and a corresponding route exists; confirm rather than assume.
- **Phase 2**: unit tests for the merge/pagination algorithm (step 1–4 above) — at minimum: page boundary crossing a series/book alphabetical tie, a series with zero books with cover art (null `coverUrl` derivation), an empty catalog, a single-item catalog. Route-level test for `GET /api/browse/catalog-series-view` (mirroring the existing test pattern for `/api/browse/series`, find and follow it).
- **Phase 3/4**: iOS unit tests for `CatalogViewModel`'s/`LibraryViewModel`'s new mode-branching logic, and for `SeriesGridItem`'s rendering given both full-ownership and partial-ownership inputs.
- **Phase 5**: web component tests (Jest + React Testing Library, per `CLAUDE.md`'s stack) for `SeriesTile`, and for the toggle's `localStorage` persistence behavior (mock `localStorage`, confirm the right feed function is called per stored state).
- All of the above must clear the project's **coverage ratchet** (per `docs/development-process.md` §5) — new files without tests will fail `validate:full`, not just be "nice to have."

---

## Phased plan

Each phase lands as its own PR, in order, with `npm run validate:full` passing before merge (per `CLAUDE.md`). Phases 0–1 are prerequisites; the toggle itself doesn't ship until Phase 4/5.

### Phase 0 — Web: Library page refactor to `BookGrid`/`BookCard` (prerequisite, no user-visible change)

**Goal**: eliminate the duplicated inline card markup in `app/library/page.tsx` so Phase 4 doesn't need two separate toggle implementations. Pure refactor — no behavior change.

- [ ] Extend `BookCard` (or its props) as needed to support whatever Library-specific bits it's missing that the inline markup currently has (check for: remove-from-library action instead of add, `ProgressStatus` display, series-remove option via `AddToLibraryButton`'s `showSeriesOption`). Confirm via diffing `app/library/page.tsx:187-275` against `components/BookCard.tsx` line by line.
- [ ] Replace `app/library/page.tsx`'s inline card block with `BookGrid`/`BookCard`, passing whatever new props were added.
- [ ] Pagination: **no change** — Library keeps rendering the full library in one shot, no pagination UI added (decided: personal libraries are small enough that this isn't worth building). This keeps Phase 0 a pure visual refactor.
- [ ] Visual regression check: confirm Library page looks the same as before (cover, title, series line, authors, narrators, runtime, remove button, progress bar) after the swap — Storybook snapshot or manual comparison.
- [ ] `npm run validate:web`.

### Phase 1 — Schema + API: series cover-art + owned-count support (OpenAPI-first)

**Goal**: give both new "Series mode" feeds what they need — a derivable cover image per series, and an owned/total count for Library mode. No new DB columns required (cover is derived, not stored; owned count is computed at query time).

- [ ] Update `docs/api/openapi.yaml` per the **Technical spec** section above: extend `SeriesWithBookCount` with `coverUrl`/`ownedCount`, add `CatalogSeriesViewItem` (plain optional `series`/`book` fields, not a `oneOf`/`discriminator` — see the spec's note on why), `GetCatalogSeriesView200Response`, and `GetLibrarySeriesView200Response`.
- [ ] Run `npm run api:generate:ts` and `npm run api:generate:swift`, confirm generated types compile on both sides — do a real `xcodebuild`, not just a successful codegen run (per this project's prior OpenAPI-to-Swift-codegen incidents).
- [ ] `npm run test:contract` to confirm the spec itself is well-formed before building against it.

### Phase 2 — Web: combined Catalog Series-mode endpoint + query logic

**Goal**: a data source that returns series (interleaved with standalone books) alphabetically, matching the requirements doc's resolved decisions (Q2, Q4, Q5).

- [ ] Add a shared `lib/` query function (e.g. `lib/catalog-series-view.ts`, parameterized for Catalog-scope vs. Library-scope per the Technical Spec's note that both variants share one implementation) implementing the **7-step pagination algorithm** from the Technical Spec section above.
- [ ] Expose this as a **new, distinct endpoint** — `GET /api/browse/catalog-series-view` — added to `openapi.yaml` in Phase 1, route handler here calling the Phase 2 query function. Sort behavior: always alphabetical by title (Decision B) — no `sort` param accepted; the existing `SortDropdown` is hidden/disabled while Series mode is active (implemented in Phase 5, called out here since it's a consequence of this endpoint having no sort options).
- [ ] Wire `app/page.tsx` to call this new function/endpoint when Series mode is active (toggle state source: `localStorage`, per Decision D — wiring itself lands in Phase 5).
- [ ] Write the unit + route tests specified in the Technical Spec's "Test coverage tasks" for this phase.

### Phase 3 — iOS: Catalog Series-mode data + `SeriesGridItem`

**Goal**: consume the Phase 2 endpoint from `CatalogView`, render series and standalone books as grid tiles.

- [ ] Regenerate/confirm Swift models for the new endpoint (from Phase 1/2's OpenAPI changes) — including the discriminated `CatalogSeriesViewItem` union. **Do a real `xcodebuild` after regenerating, not just a successful codegen run**: this project has previously hit OpenAPI shapes (free-form `additionalProperties: true` objects) that generate "successfully" but fail to actually compile in Swift (missing `AnyCodable` dependency) — the drift-check and codegen passing is not proof the Swift compiles. A `oneOf`+`discriminator` union is a different shape than that prior incident, but warrants the same "verify with a real build" discipline rather than assuming it Just Works.
- [ ] Add an `APIClient` method for the new combined feed (mirroring `fetchBooks`'s pagination pattern, since this needs real server pagination per finding #8).
- [ ] Build `SeriesGridItem` per the Technical Spec's field-level spec above; standalone-book items in the combined feed reuse `BookGridItem` unchanged.
- [ ] Add the Books/Series segmented toggle control to `CatalogView` (SwiftUI `Picker` with `.segmented` style is the idiomatic choice — matches existing iOS conventions, confirm against any existing segmented control elsewhere in the app for consistency).
- [ ] Wire toggle state to `UserDefaults`, keyed separately from Library's toggle state (per requirements Q1/Q6).
- [ ] Update `CatalogViewModel` to branch its fetch/pagination logic on the toggle state (two independent paginated lists — Books mode keeps existing `fetchBooks` path unchanged, Series mode uses the new endpoint). Loading/empty/error states per the Technical Spec — reuse Books mode's existing treatment, no new UI states invented.
- [ ] Confirm `CatalogCache` (existing 10-min TTL in-memory cache) either covers both modes distinctly (separate cache keys per mode) or is bypassed for Series mode — don't let the two modes' cached pages collide.
- [ ] Write the iOS unit tests specified in the Technical Spec's "Test coverage tasks" for this phase.

### Phase 4 — iOS: retire `SeriesListView`, fold into Catalog; add Library Series-mode

**Goal**: complete the iOS side per requirements Q3/Q6.

> **Scope reduced — two items landed early.** The `library-series-view` endpoint was
> pulled into **Phase 2** (PR #125): the endpoint-coverage gate hard-fails when a spec'd
> path has no route handler, and Phase 1 added both paths to the spec together. Its iOS
> `APIClient`/`APIClientProtocol`/`MockAPIClient` plumbing then came along in **Phase 3**
> (PR #126), since both methods were cheap to add at once. What remains here is iOS UI
> only: the Library toggle and retiring `SeriesListView`.

**Status: complete** (PR #128).

- [x] Remove `SeriesListView` as a Browse entry point; remove the now-unused `BrowseListConfiguration.series()` factory. **Scope note**: the plan assumed one entry point, but there were **two** — `BrowseView.swift` _and_ the Search empty-state shortcuts (`SearchView.swift`). Both removed per requirements Q6 (confirmed with the user, since Series sat in a four-item set alongside Authors/Narrators/Categories in both places). Also removed the now-orphaned `seriesCount` state and its `fetchSeries` count query from `BrowseView`.
- [x] ~~Add `GET /api/browse/library-series-view`~~ — **done in Phase 2** (PR #125), same shared query function with `{ scope: 'library', userId }`.
- [x] ~~iOS `fetchLibrarySeriesView` on `APIClient`/`APIClientProtocol`/`MockAPIClient`~~ — **done in Phase 3** (PR #126).
- [x] Fetch the Library Series-mode payload in one large page (`limit: 500`) rather than paginating — matches how Books mode already pulls the whole library, and library sizes are personal-scale.
- [x] Add the Books/Series toggle to `LibraryView`, with `LibraryViewModel.modeDefaultsKey = "libraryViewMode"` — independent of Catalog's `"catalogViewMode"`.
- [x] `SeriesGridItem` (from Phase 3) reused here; its ownership branch now gets real `ownedCount < bookCount` data.
- [x] Series tiles navigate to the existing `SeriesDetailView(seriesId:)` via the reused `CatalogSeriesViewItemCell` — no changes needed there, as expected.
- [x] Write the iOS unit tests for this phase (22 new: mode persistence/independence, mode branching, Series-mode load/refresh/error, and partial-vs-full ownership labels).

**Implementation notes**:

- `SearchManager.fetchSeries` is now **unused by the iOS UI** but deliberately kept — `/api/browse/series` is still live and spec'd (web's Browse Series page uses it), and the method is the parity wrapper for it. Marked with a doc comment explaining why, so it doesn't read as an oversight.
- Both grid branches were extracted into `LibraryBooksGrid`/`LibrarySeriesGrid` **up front**, rather than nesting a mode conditional inside `LazyVGrid` — that's the exact shape that tripped the Swift type-checker in Phase 3.
- The `libraryVersion` observer now calls `reloadCurrentMode()`, which force-refreshes Series mode rather than reusing the "already loaded this session" cache — adding or removing a book changes ownership counts, so stale tiles would otherwise show wrong "N of M" values.
- Library's Series mode has **no offline-cache path** (unlike Books mode, which goes through `LibraryManager`), so the offline-no-cache empty state is gated to Books mode.

### Phase 5 — Web: Catalog + Library Series-mode UI

**Goal**: the web-side toggle, now that Phase 0 (Library refactor) and Phase 2 (combined feed) are done.

**Status: complete** (PR #127).

- [x] Build `SeriesTile.tsx` plus a `SeriesViewGrid.tsx` container that maps a `results` array to `SeriesTile` (items with `series`) or the existing `BookCard` (items with `book`), mirroring `BookGrid`'s grid/skeleton/empty-state wrapper.
- [x] Add a Books/Series toggle control to the root page and Library page. No existing segmented-control convention was found, so a new `ViewModeToggle` was built. `SortDropdown` is hidden while Series mode is active (Decision B).
- [x] Wire toggle state to `localStorage` only — no URL query param (Decision D), separate keys per page (requirements Q1). Implemented as a `SeriesModeSection` client wrapper that renders the server-rendered Books grid as `children` and fetches the series feed client-side.
- [x] `app/page.tsx`: branch between the existing books feed and `catalog-series-view`.
- [x] `app/library/page.tsx`: same toggle, calling `library-series-view`.
- [x] Loading/empty/error states reuse `BookGrid`'s treatment; the error state adds a Retry action.
- [x] Dark-mode variants for `SeriesTile` and the toggle control.
- [x] Update `docs/component-guide.md` with the new components.
- [x] Write the web component tests for this phase (39 new tests).

**Implementation notes** — three things worth carrying forward:

1. **No render props across the server/client boundary.** `SeriesModeSection` first took a
   `renderHeading` function prop. Passing a function from a Server Component to a Client
   Component throws _"Functions cannot be passed directly to Client Components"_ at request
   time and takes down the whole page. Component unit tests render entirely on the client,
   so they passed; only the **E2E smoke test** caught it. The props are now serializable
   (`booksHeading` as a `ReactNode`, `seriesCountTemplate` as a `{count}` string), and
   `__tests__/pages/series-mode-server-boundary.test.ts` guards the call sites at the source
   level so the next person gets a fast unit-test failure instead of a broken page.
2. **`useSyncExternalStore`, not effect-synced state.** The project's ESLint promotes
   `react-hooks/set-state-in-effect` to an error. Reading `localStorage` on mount is exactly
   the external-store case, so `useViewMode` uses `useSyncExternalStore` with a server
   snapshot of `'books'` (no hydration mismatch) and an in-tab subscriber (the `storage`
   event only fires in _other_ tabs). Consequence: `localStorage` is the single source of
   truth, so if a write throws (private browsing) the mode stays put rather than showing a
   preference that would vanish on reload.
3. **The remaining fetch-on-mount effect** uses the project's established
   `// eslint-disable-next-line react-hooks/set-state-in-effect` convention (see
   `HealthTab.tsx`) — the `setState` runs after the `await`, not synchronously. It also
   carries an `AbortController` so a superseded request can't overwrite a newer one.

### Phase 6 — Validation

- [ ] `npm run validate:full` (web + DB suites + iOS unit/integration/contract/E2E + drift + coverage + SwiftLint + iOS build/tests).
- [ ] Manual pass: toggle persists correctly per-device/per-view on both platforms across app restarts.
- [ ] Manual pass: a series with partial library ownership shows correct "N of M" on Library/Series mode, on both platforms.
- [ ] Manual pass: standalone books appear correctly interleaved alphabetically alongside series tiles, on both platforms, in both Catalog and Library.
- [ ] Manual pass: tapping any tile (series or standalone book) in Series mode navigates correctly.
- [ ] Confirm iOS `SeriesListView`/Browse-tab series entry point is fully gone with no dead navigation links left behind.

---

## Decisions (resolved)

**A. Library pagination (Phase 0)**: No change — Library keeps rendering the entire library at once, no pagination added. Phase 0 stays a pure visual refactor onto `BookGrid`/`BookCard`.

**B. Sort behavior in Series mode (Phase 2)**: Series mode is always alphabetical by title; the existing `author`/`narrator` sort options do not apply and the `SortDropdown` should be hidden or neutralized while Series mode is active.

**C. Endpoint shape/naming for the combined Catalog feed (Phase 2)**: A new, distinct endpoint — `GET /api/browse/catalog-series-view` — rather than overloading `/api/browse/series`, which keeps its current contract unchanged for its existing consumer.

**D. Toggle state representation on web (Phase 5)**: Pure `localStorage`, no URL query param. Note the consequence this creates (called out in Phase 5 directly): `app/page.tsx` and `app/library/page.tsx` are currently pure Server Components with no client-side data branching, and `localStorage` is only readable client-side — so Phase 5 necessarily introduces a client-side boundary to read the toggle state and drive which feed is fetched, rather than being a same-pattern swap.

---

## Dependency / sequencing notes

- Phase 0 (web Library refactor) and Phase 1 (schema/API) can proceed in parallel — no dependency between them.
- Phase 2 (web combined feed) depends on Phase 1 (schema must exist first, per OpenAPI-first rule).
- Phase 3 (iOS Catalog) depends on Phase 1 and Phase 2's `catalog-series-view` endpoint (iOS consumes the same endpoint web's Catalog page calls, per Decision C).
- Phase 4 (iOS Library + retire SeriesListView) depends on Phase 1 and introduces its own `library-series-view` endpoint (mirrors Phase 2's shared query function, just with library-scope parameters).
- Phase 5 (web UI) depends on Phase 0 (Library refactor) and Phase 2 (combined feed logic).
- Phase 6 (validation) is last, always.

Suggested landing order: **Phase 1 → Phase 0 & Phase 2 (parallel) → Phase 3 & Phase 5 (parallel) → Phase 4 → Phase 6.** Phase 4 is placed after Phase 3 since it reuses `SeriesGridItem` built there.
