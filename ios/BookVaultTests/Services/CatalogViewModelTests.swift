//
//  CatalogViewModelTests.swift
//  BookVaultTests
//
//  Books/Series toggle mode-branching + Series-mode data loading
//  (docs/archive/completed-plans/series-view-toggle-implementation.md, Phase 3).
//

import XCTest
@testable import BookVault

@MainActor
final class CatalogViewModelTests: XCTestCase {
    private var mockAPIClient: MockAPIClient!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        UserDefaults.standard.removeObject(forKey: CatalogViewModel.modeDefaultsKey)
    }

    override func tearDown() async throws {
        mockAPIClient = nil
        UserDefaults.standard.removeObject(forKey: CatalogViewModel.modeDefaultsKey)
    }

    private func makeSeriesItem(title: String, bookCount: Int = 1, ownedCount: Int? = nil) -> CatalogSeriesViewItem {
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

    // MARK: - Mode default + persistence

    func testDefaultsToBooksModeWithNoStoredPreference() {
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        XCTAssertEqual(sut.mode, .books)
    }

    func testRestoresPersistedModeFromUserDefaults() {
        UserDefaults.standard.set(CatalogMode.series.rawValue, forKey: CatalogViewModel.modeDefaultsKey)
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        XCTAssertEqual(sut.mode, .series)
    }

    func testChangingModePersistsToUserDefaults() {
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        sut.mode = .series
        XCTAssertEqual(UserDefaults.standard.string(forKey: CatalogViewModel.modeDefaultsKey), "Series")
    }

    // MARK: - loadCurrentMode branching

    func testLoadCurrentModeCallsFetchBooksInBooksMode() async {
        mockAPIClient.fetchBooksResult = .success(ListBooks200Response(
            books: [], pagination: ListBooks200ResponsePagination(page: 1, limit: 20, total: 0, pages: 0)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        sut.mode = .books

        await sut.loadCurrentMode()

        XCTAssertEqual(mockAPIClient.fetchBooksCalls.count, 1)
        XCTAssertEqual(mockAPIClient.fetchCatalogSeriesViewCalls.count, 0)
    }

    func testLoadCurrentModeCallsFetchCatalogSeriesViewInSeriesMode() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [], pagination: Pagination(page: 1, limit: 20, total: 0, pages: 0)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        sut.mode = .series

        await sut.loadCurrentMode()

        XCTAssertEqual(mockAPIClient.fetchCatalogSeriesViewCalls.count, 1)
        XCTAssertEqual(mockAPIClient.fetchBooksCalls.count, 0)
    }

    // MARK: - Series-mode data loading

    func testLoadSeriesViewPopulatesItemsAndPagination() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeSeriesItem(title: "Alpha Series"), makeBookItem(title: "Standalone Book")],
            pagination: Pagination(page: 1, limit: 20, total: 2, pages: 1)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertEqual(sut.seriesViewItems.count, 2)
        XCTAssertFalse(sut.hasMoreSeriesViewPages)
        XCTAssertFalse(sut.isLoadingSeriesView)
        XCTAssertNil(sut.seriesViewErrorMessage)
    }

    func testLoadSeriesViewDoesNotRefetchIfAlreadyLoaded() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeSeriesItem(title: "Alpha Series")],
            pagination: Pagination(page: 1, limit: 20, total: 1, pages: 1)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()
        await sut.loadSeriesView()

        XCTAssertEqual(mockAPIClient.fetchCatalogSeriesViewCalls.count, 1)
    }

    func testLoadSeriesViewSetsErrorMessageOnFailure() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .failure(APIError.serverError(500, nil))
        let sut = CatalogViewModel(apiClient: mockAPIClient)

        await sut.loadSeriesView()

        XCTAssertNotNil(sut.seriesViewErrorMessage)
        XCTAssertTrue(sut.seriesViewItems.isEmpty)
    }

    func testLoadMoreSeriesViewAppendsAndAdvancesPage() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeSeriesItem(title: "Page One Series")],
            pagination: Pagination(page: 1, limit: 1, total: 2, pages: 2)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        await sut.loadSeriesView()
        XCTAssertTrue(sut.hasMoreSeriesViewPages)

        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeBookItem(title: "Page Two Book")],
            pagination: Pagination(page: 2, limit: 1, total: 2, pages: 2)
        ))
        await sut.loadMoreSeriesView()

        XCTAssertEqual(sut.seriesViewItems.count, 2)
        XCTAssertEqual(mockAPIClient.fetchCatalogSeriesViewCalls.map(\.page), [1, 2])
        XCTAssertFalse(sut.hasMoreSeriesViewPages)
    }

    func testLoadMoreSeriesViewSkippedWhenNoMorePages() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeSeriesItem(title: "Only Series")],
            pagination: Pagination(page: 1, limit: 20, total: 1, pages: 1)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        await sut.loadSeriesView()

        await sut.loadMoreSeriesView()

        XCTAssertEqual(mockAPIClient.fetchCatalogSeriesViewCalls.count, 1) // no second call
    }

    func testRefreshSeriesViewReplacesItemsAndResetsPage() async {
        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeSeriesItem(title: "Old Series")],
            pagination: Pagination(page: 1, limit: 20, total: 1, pages: 1)
        ))
        let sut = CatalogViewModel(apiClient: mockAPIClient)
        await sut.loadSeriesView()

        mockAPIClient.fetchCatalogSeriesViewResult = .success(GetCatalogSeriesView200Response(
            results: [makeSeriesItem(title: "New Series 1"), makeSeriesItem(title: "New Series 2")],
            pagination: Pagination(page: 1, limit: 20, total: 2, pages: 1)
        ))
        await sut.refreshSeriesView()

        XCTAssertEqual(sut.seriesViewItems.count, 2)
        XCTAssertEqual(sut.seriesViewItems.first?.series?.title, "New Series 1")
    }
}
