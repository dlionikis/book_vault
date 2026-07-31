//
//  CarPlayLibraryProviderTests.swift
//  BookVaultTests
//
//  CarPlay task C3 — provider mapping, empty, error and offline states.
//

import XCTest
@testable import BookVault

@MainActor
final class CarPlayLibraryProviderTests: XCTestCase {
    private var mockLibrary: MockLibraryManager!
    private var mockAPI: MockAPIClient!
    private var mockStorage: MockStorageManager!
    private var mockNetwork: MockNetworkMonitor!
    private var sut: CarPlayLibraryProvider!

    override func setUp() async throws {
        mockLibrary = MockLibraryManager()
        mockAPI = MockAPIClient()
        mockStorage = MockStorageManager()
        mockNetwork = MockNetworkMonitor()

        sut = CarPlayLibraryProvider(
            libraryManager: mockLibrary,
            apiClient: mockAPI,
            storageManager: mockStorage,
            networkMonitor: mockNetwork
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockLibrary = nil
        mockAPI = nil
        mockStorage = nil
        mockNetwork = nil
    }

    // MARK: - Helpers

    private func libraryBook(
        id: UUID = UUID(),
        title: String,
        author: String = "An Author",
        addedAt: Date = Date(),
        series: [SeriesInfo]? = nil
    ) -> LibraryBook {
        LibraryBook(
            id: id,
            asin: "ASIN-\(title)",
            title: title,
            authors: [Author(id: UUID(), name: author)],
            series: series,
            addedAt: addedAt
        )
    }

    private func rows(from state: CarPlayListState) -> [CarPlayRow] {
        guard case let .loaded(rows) = state else { return [] }
        return rows
    }

    // MARK: - Library

    func testLibraryRowsMapTitleAndAuthor() async {
        mockLibrary.libraryBooks = [libraryBook(title: "Dune", author: "Frank Herbert")]

        let state = await sut.libraryRows()

        XCTAssertEqual(rows(from: state).map(\.title), ["Dune"])
        XCTAssertEqual(rows(from: state).first?.detail, "Frank Herbert")
    }

    /// Most-recently-added first: in a car, the book you just added is the one
    /// you most likely want.
    func testLibraryRowsAreSortedByRecentlyAdded() async {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        mockLibrary.libraryBooks = [
            libraryBook(title: "Older", addedAt: old),
            libraryBook(title: "Newer", addedAt: new)
        ]

        let state = await sut.libraryRows()

        XCTAssertEqual(rows(from: state).map(\.title), ["Newer", "Older"])
    }

    /// An empty library must explain itself rather than render a blank list.
    func testEmptyLibraryReturnsExplainedEmptyState() async {
        mockLibrary.libraryBooks = []

        let state = await sut.libraryRows()

        guard case let .empty(message) = state else {
            return XCTFail("Expected .empty, got \(state)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /// Failures never surface a raw error string — unreadable while driving.
    func testLibraryFetchFailureReturnsDriverReadableMessage() async {
        mockLibrary.fetchShouldFail = true
        mockLibrary.fetchError = NSError(
            domain: "Test",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "NSURLErrorDomain -1004 could not connect to https://…"]
        )

        let state = await sut.libraryRows()

        guard case let .failed(message) = state else {
            return XCTFail("Expected .failed, got \(state)")
        }
        XCTAssertFalse(message.contains("NSURLError"), "Raw error text must not reach the driver")
        XCTAssertFalse(message.contains("http"), "URLs must not reach the driver")
    }

    /// Offline gets its own message pointing at downloads, which still work.
    func testOfflineFailureMentionsDownloads() async {
        mockNetwork.isConnected = false
        mockLibrary.fetchShouldFail = true

        let state = await sut.libraryRows()

        guard case let .failed(message) = state else {
            return XCTFail("Expected .failed, got \(state)")
        }
        XCTAssertTrue(message.lowercased().contains("offline"))
        XCTAssertTrue(message.lowercased().contains("download"))
    }

    // MARK: - Downloaded

    func testDownloadedRowsIncludeOnlyDownloadedBooks() async {
        let downloadedId = UUID()
        mockLibrary.libraryBooks = [
            libraryBook(id: downloadedId, title: "On Device"),
            libraryBook(title: "Streaming Only")
        ]
        mockStorage.downloadedBooks = [downloadedId.uuidString.uppercased()]

        let state = await sut.downloadedRows()

        XCTAssertEqual(rows(from: state).map(\.title), ["On Device"])
    }

    /// The offline-with-nothing-downloaded case, which is the worst UX to get
    /// wrong: a blank screen in a car with no signal.
    func testNoDownloadsReturnsExplainedEmptyState() async {
        mockLibrary.libraryBooks = [libraryBook(title: "Streaming Only")]
        mockStorage.downloadedBooks = []

        let state = await sut.downloadedRows()

        guard case let .empty(message) = state else {
            return XCTFail("Expected .empty, got \(state)")
        }
        XCTAssertTrue(message.lowercased().contains("download"))
    }

    // MARK: - Series

    func testBooksInSeriesAreFilteredAndOrderedBySequence() async {
        let seriesId = UUID()
        func inSeries(_ sequence: Int) -> [SeriesInfo] {
            [SeriesInfo(id: seriesId, title: "The Series", sequence: sequence)]
        }
        mockLibrary.libraryBooks = [
            libraryBook(title: "Third", series: inSeries(3)),
            libraryBook(title: "First", series: inSeries(1)),
            libraryBook(title: "Second", series: inSeries(2)),
            libraryBook(title: "Unrelated", series: nil)
        ]

        let state = await sut.booksInSeries(id: seriesId)

        XCTAssertEqual(rows(from: state).map(\.title), ["First", "Second", "Third"],
                       "Books should be in series order, and non-series books excluded")
    }

    /// `sequence` is `Int?` on the wire, so ordering is numeric by construction.
    /// This pins that books without a sequence sort last rather than jumbling in
    /// among the numbered ones.
    func testBooksWithoutASequenceSortLast() async {
        let seriesId = UUID()
        mockLibrary.libraryBooks = [
            libraryBook(title: "Unnumbered", series: [SeriesInfo(id: seriesId, title: "S")]),
            libraryBook(title: "Two", series: [SeriesInfo(id: seriesId, title: "S", sequence: 2)]),
            libraryBook(title: "One", series: [SeriesInfo(id: seriesId, title: "S", sequence: 1)])
        ]

        let state = await sut.booksInSeries(id: seriesId)

        XCTAssertEqual(rows(from: state).map(\.title), ["One", "Two", "Unnumbered"])
    }

    func testSeriesWithNoOwnedBooksIsExplained() async {
        mockLibrary.libraryBooks = [libraryBook(title: "Unrelated", series: nil)]

        let state = await sut.booksInSeries(id: UUID())

        guard case .empty = state else {
            return XCTFail("Expected .empty, got \(state)")
        }
    }

    // MARK: - Row kinds

    /// Book rows carry the `Book` so selection can hand it straight to
    /// `AudioPlayerManager.play(book:)` without a second lookup.
    func testBookRowCarriesThePlayableBook() async {
        let id = UUID()
        mockLibrary.libraryBooks = [libraryBook(id: id, title: "Dune")]

        let state = await sut.libraryRows()

        guard case let .book(book)? = rows(from: state).first?.kind else {
            return XCTFail("Expected a .book row")
        }
        XCTAssertEqual(book.id, id)
        XCTAssertEqual(rows(from: state).first?.bookId, id)
    }
}
