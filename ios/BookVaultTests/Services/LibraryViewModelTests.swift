//
//  LibraryViewModelTests.swift
//  BookVaultTests
//
//  Library Books/Series toggle: mode persistence, mode-branching, and
//  Series-mode loading with ownership data
//  (docs/archive/completed-plans/series-view-toggle-implementation.md, Phase 4).
//

import XCTest
@testable import BookVault

@MainActor
final class LibraryViewModelTests: XCTestCase {
    private var mockAPIClient: MockAPIClient!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        UserDefaults.standard.removeObject(forKey: LibraryViewModel.modeDefaultsKey)
    }

    override func tearDown() async throws {
        mockAPIClient = nil
        UserDefaults.standard.removeObject(forKey: LibraryViewModel.modeDefaultsKey)
    }

    private func makeSeriesItem(
        title: String,
        bookCount: Int = 1,
        ownedCount: Int? = nil
    ) -> CatalogSeriesViewItem {
        CatalogSeriesViewItem(series: SeriesWithBookCount(
            id: UUID(),
            title: title,
            asin: nil,
            bookCount: bookCount,
            ownedCount: ownedCount
        ))
    }

    private func makeBookItem(title: String) -> CatalogSeriesViewItem {
        CatalogSeriesViewItem(book: Book(
            id: UUID(),
            asin: "ASIN",
            title: title,
            authors: [],
            narrators: [],
            series: [],
            categories: []
        ))
    }

    private func seriesResponse(
        _ results: [CatalogSeriesViewItem],
        page: Int = 1,
        pages: Int = 1,
        total: Int? = nil
    ) -> GetLibrarySeriesView200Response {
        GetLibrarySeriesView200Response(
            results: results,
            pagination: Pagination(page: page, limit: 100, total: total ?? results.count, pages: pages)
        )
    }

    // MARK: - Mode default + persistence

    func testDefaultsToBooksModeWithNoStoredPreference() {
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        XCTAssertEqual(sut.mode, .books)
    }

    func testRestoresPersistedModeFromUserDefaults() {
        UserDefaults.standard.set(CatalogMode.series.rawValue, forKey: LibraryViewModel.modeDefaultsKey)
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        XCTAssertEqual(sut.mode, .series)
    }

    func testChangingModePersistsToUserDefaults() {
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        sut.mode = .series
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: LibraryViewModel.modeDefaultsKey),
            "Series"
        )
    }

    /// The Library toggle must not read or write the Catalog's key, and vice
    /// versa — each screen remembers its own mode (requirements Q1).
    func testLibraryModeIsIndependentOfCatalogMode() {
        UserDefaults.standard.removeObject(forKey: CatalogViewModel.modeDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: CatalogViewModel.modeDefaultsKey) }

        let sut = LibraryViewModel(apiClient: mockAPIClient)
        sut.mode = .series

        XCTAssertNotEqual(LibraryViewModel.modeDefaultsKey, CatalogViewModel.modeDefaultsKey)
        XCTAssertNil(UserDefaults.standard.string(forKey: CatalogViewModel.modeDefaultsKey))
    }

    func testCatalogModeDoesNotLeakIntoLibrary() {
        UserDefaults.standard.set(CatalogMode.series.rawValue, forKey: CatalogViewModel.modeDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: CatalogViewModel.modeDefaultsKey) }

        let sut = LibraryViewModel(apiClient: mockAPIClient)
        XCTAssertEqual(sut.mode, .books)
    }

    // MARK: - loadCurrentMode branching

    func testLoadCurrentModeDoesNotFetchSeriesInBooksMode() async {
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        sut.mode = .books

        await sut.loadCurrentMode()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.count, 0)
    }

    func testLoadCurrentModeFetchesSeriesInSeriesMode() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        sut.mode = .series

        await sut.loadCurrentMode()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.count, 1)
    }

    func testSeriesViewUsesTheLibraryEndpointNotTheCatalogOne() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.count, 1)
        XCTAssertEqual(mockAPIClient.fetchCatalogSeriesViewCalls.count, 0)
    }

    // MARK: - Series-mode data loading

    func testLoadSeriesViewPopulatesItems() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Alpha Series", bookCount: 3, ownedCount: 1),
            makeBookItem(title: "Standalone Book")
        ]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(sut.seriesViewItems.count, 2)
        XCTAssertFalse(sut.isLoadingSeriesView)
        XCTAssertNil(sut.seriesViewErrorMessage)
    }

    /// The server clamps `limit` to 100 (`parsePagination`), so requesting more
    /// would silently return 100 and — with no load-more UI in Series mode —
    /// make the remainder unreachable.
    func testLoadSeriesViewNeverRequestsMoreThanTheServerCap() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.first?.page, 1)
        XCTAssertLessThanOrEqual(mockAPIClient.fetchLibrarySeriesViewCalls.first?.limit ?? .max, 100)
    }

    /// Series mode shows the whole feed with no load-more control, so a library
    /// spanning multiple server pages must be fetched in full up front.
    func testLoadSeriesViewFollowsPaginationAcrossMultiplePages() async {
        mockAPIClient.fetchLibrarySeriesViewResultsByPage = [
            1: .success(seriesResponse([makeSeriesItem(title: "Page 1")], page: 1, pages: 3, total: 3)),
            2: .success(seriesResponse([makeSeriesItem(title: "Page 2")], page: 2, pages: 3, total: 3)),
            3: .success(seriesResponse([makeSeriesItem(title: "Page 3")], page: 3, pages: 3, total: 3))
        ]
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.map(\.page), [1, 2, 3])
        XCTAssertEqual(sut.seriesViewItems.count, 3)
        XCTAssertEqual(sut.seriesViewItems.compactMap(\.series?.title), ["Page 1", "Page 2", "Page 3"])
    }

    func testLoadSeriesViewStopsAfterASinglePageWhenThereIsOnlyOne() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(
            seriesResponse([makeSeriesItem(title: "Only")], page: 1, pages: 1)
        )
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.count, 1)
    }

    /// A server that over-reports `pages` shouldn't cause endless requests.
    func testLoadSeriesViewStopsOnAnEmptyPageEvenIfMorePagesAreClaimed() async {
        mockAPIClient.fetchLibrarySeriesViewResultsByPage = [
            1: .success(seriesResponse([makeSeriesItem(title: "Page 1")], page: 1, pages: 99, total: 99)),
            2: .success(seriesResponse([], page: 2, pages: 99, total: 99))
        ]
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.map(\.page), [1, 2])
        XCTAssertEqual(sut.seriesViewItems.count, 1)
    }

    func testRefreshSeriesViewAlsoFollowsPagination() async {
        mockAPIClient.fetchLibrarySeriesViewResultsByPage = [
            1: .success(seriesResponse([makeSeriesItem(title: "A")], page: 1, pages: 2, total: 2)),
            2: .success(seriesResponse([makeSeriesItem(title: "B")], page: 2, pages: 2, total: 2))
        ]
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.refreshSeriesView()

        XCTAssertEqual(sut.seriesViewItems.count, 2)
        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.map(\.page), [1, 2])
    }

    /// A failure partway through paging must surface as an error, not as a
    /// silently-truncated feed presented as complete.
    func testLoadSeriesViewSurfacesAFailureOnALaterPage() async {
        mockAPIClient.fetchLibrarySeriesViewResultsByPage = [
            1: .success(seriesResponse([makeSeriesItem(title: "Page 1")], page: 1, pages: 2, total: 2)),
            2: .failure(APIError.serverError(500, nil))
        ]
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertNotNil(sut.seriesViewErrorMessage)
        XCTAssertTrue(sut.seriesViewItems.isEmpty, "a partial feed must not be shown as if complete")
    }

    func testLoadSeriesViewDoesNotRefetchIfAlreadyLoaded() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Alpha Series")
        ]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()
        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.count, 1)
    }

    func testLoadSeriesViewSetsErrorMessageOnFailure() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .failure(APIError.serverError(500, nil))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertNotNil(sut.seriesViewErrorMessage)
        XCTAssertTrue(sut.seriesViewItems.isEmpty)
    }

    func testRefreshSeriesViewReplacesItems() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Old Series")
        ]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        await sut.loadSeriesView()

        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "New Series 1"),
            makeSeriesItem(title: "New Series 2")
        ]))
        await sut.refreshSeriesView()

        XCTAssertEqual(sut.seriesViewItems.count, 2)
        XCTAssertEqual(sut.seriesViewItems.first?.series?.title, "New Series 1")
    }

    /// Unlike loadSeriesView, refresh must re-fetch even when items are already
    /// present — that's the whole point of pull-to-refresh.
    func testRefreshSeriesViewRefetchesEvenWhenAlreadyLoaded() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Series")
        ]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        await sut.loadSeriesView()

        await sut.refreshSeriesView()

        XCTAssertEqual(mockAPIClient.fetchLibrarySeriesViewCalls.count, 2)
    }

    func testRefreshSeriesViewClearsAPreviousError() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .failure(APIError.serverError(500, nil))
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        await sut.loadSeriesView()
        XCTAssertNotNil(sut.seriesViewErrorMessage)

        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Recovered")
        ]))
        await sut.refreshSeriesView()

        XCTAssertNil(sut.seriesViewErrorMessage)
        XCTAssertEqual(sut.seriesViewItems.count, 1)
    }

    /// Series mode has no offline cache (it doesn't go through LibraryManager),
    /// so a network failure surfaces as an ordinary retryable error rather than
    /// the Books-mode "no cached library" state.
    func testOfflineSeriesFetchSurfacesAsAPlainError() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .failure(
            APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        )
        let sut = LibraryViewModel(apiClient: mockAPIClient)
        sut.mode = .series

        await sut.loadCurrentMode()

        XCTAssertNotNil(sut.seriesViewErrorMessage)
        XCTAssertFalse(sut.isOfflineNoCache, "isOfflineNoCache is a Books-mode concept")
    }

    // MARK: - Ownership data (Library-specific)

    func testPartiallyOwnedSeriesCarriesOwnedCountBelowBookCount() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Partly Owned", bookCount: 5, ownedCount: 2)
        ]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        let series = try? XCTUnwrap(sut.seriesViewItems.first?.series)
        XCTAssertEqual(series?.ownedCount, 2)
        XCTAssertEqual(series?.bookCount, 5)
    }

    func testFullyOwnedSeriesHasMatchingOwnedAndBookCounts() async {
        mockAPIClient.fetchLibrarySeriesViewResult = .success(seriesResponse([
            makeSeriesItem(title: "Fully Owned", bookCount: 3, ownedCount: 3)
        ]))
        let sut = LibraryViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        let series = try? XCTUnwrap(sut.seriesViewItems.first?.series)
        XCTAssertEqual(series?.ownedCount, series?.bookCount)
    }
}

// MARK: - SeriesGridItem ownership label

/// `SeriesGridItem` renders the "N of M in your library" indicator that only
/// Library scope produces, so its label logic is covered here alongside the
/// Library view model.
@MainActor
final class SeriesGridItemOwnershipTests: XCTestCase {
    private func label(bookCount: Int, ownedCount: Int?) -> String {
        let item = SeriesGridItem(series: SeriesWithBookCount(
            id: UUID(),
            title: "Series",
            asin: nil,
            bookCount: bookCount,
            ownedCount: ownedCount
        ))
        return item.bookCountLabel
    }

    func testPartialOwnershipShowsOwnedOfTotal() {
        XCTAssertEqual(label(bookCount: 5, ownedCount: 2), "2 of 5 in your library")
    }

    func testZeroOwnedStillReadsAsPartial() {
        XCTAssertEqual(label(bookCount: 5, ownedCount: 0), "0 of 5 in your library")
    }

    func testFullOwnershipShowsPlainCount() {
        XCTAssertEqual(label(bookCount: 5, ownedCount: 5), "5 books")
    }

    /// Catalog scope omits ownedCount entirely — no ownership phrasing there.
    func testMissingOwnedCountShowsPlainCount() {
        XCTAssertEqual(label(bookCount: 5, ownedCount: nil), "5 books")
    }

    func testSingleBookSeriesIsSingularized() {
        XCTAssertEqual(label(bookCount: 1, ownedCount: nil), "1 book")
    }
}
