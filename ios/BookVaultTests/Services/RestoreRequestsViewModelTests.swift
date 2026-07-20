//
//  RestoreRequestsViewModelTests.swift
//  BookVaultTests
//
//  Grouping + labeling for the Settings → Restore Requests list (device-free).
//

import XCTest
@testable import BookVault

@MainActor
final class RestoreRequestsViewModelTests: XCTestCase {
    private var mockAPIClient: MockAPIClient!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
    }

    override func tearDown() async throws {
        mockAPIClient = nil
    }

    private func makeSummary(
        status: RestoreRequestSummary.Status,
        title: String = "Book",
        eta: Date? = nil,
        completedAt: Date? = nil
    ) -> RestoreRequestSummary {
        RestoreRequestSummary(
            id: UUID(),
            bookId: UUID(),
            status: status,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: completedAt,
            estimatedCompletion: eta,
            book: RestoreRequestSummaryBook(id: UUID(), title: title)
        )
    }

    // MARK: - Grouping

    func testGroupsInProgressAndFailedIntoActive_completedIntoRecent() async {
        mockAPIClient.listRestoresResult = .success(RestoresListResponse(restores: [
            makeSummary(status: .inProgress, title: "Restoring One"),
            makeSummary(status: .completed, title: "Done One"),
            makeSummary(status: .failed, title: "Failed One"),
            makeSummary(status: .inProgress, title: "Restoring Two")
        ]))
        let sut = RestoreRequestsViewModel(apiClient: mockAPIClient)

        await sut.load()

        XCTAssertEqual(sut.active.count, 3) // 2 in-progress + 1 failed
        XCTAssertEqual(sut.recent.count, 1) // 1 completed
        XCTAssertTrue(sut.hasActive)
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.loadFailed)
    }

    func testEmptyResponseMarksEmptyAfterLoad() async {
        mockAPIClient.listRestoresResult = .success(RestoresListResponse(restores: []))
        let sut = RestoreRequestsViewModel(apiClient: mockAPIClient)

        await sut.load()

        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.hasActive)
    }

    func testNotEmptyBeforeFirstLoad() {
        let sut = RestoreRequestsViewModel(apiClient: mockAPIClient)
        // isEmpty must be false until a load has actually completed, so the view
        // shows a spinner rather than the empty state on first render.
        XCTAssertFalse(sut.isEmpty)
    }

    func testLoadFailureSetsFlagAndNotEmpty() async {
        mockAPIClient.listRestoresResult = .failure(APIError.serverError(500, nil))
        let sut = RestoreRequestsViewModel(apiClient: mockAPIClient)

        await sut.load()

        XCTAssertTrue(sut.loadFailed)
        XCTAssertFalse(sut.isEmpty) // don't show "no restores" on an error
    }

    func testCompletedOnlyHasNoActive() async {
        mockAPIClient.listRestoresResult = .success(RestoresListResponse(restores: [
            makeSummary(status: .completed)
        ]))
        let sut = RestoreRequestsViewModel(apiClient: mockAPIClient)

        await sut.load()

        XCTAssertFalse(sut.hasActive)
        XCTAssertEqual(sut.recent.count, 1)
    }

    // MARK: - Subtitles

    func testSubtitleForCompleted() {
        let summary = makeSummary(status: .completed)
        XCTAssertEqual(RestoreRequestsViewModel.subtitle(for: summary), "Ready to play")
    }

    func testSubtitleForFailed() {
        let summary = makeSummary(status: .failed)
        XCTAssertEqual(
            RestoreRequestsViewModel.subtitle(for: summary),
            "Restore failed — tap to try again"
        )
    }

    func testSubtitleForInProgressUsesFormatter() {
        // Far-future ETA → the formatter's hour-based phrasing.
        let eta = Date().addingTimeInterval(4 * 3600)
        let summary = makeSummary(status: .inProgress, eta: eta)
        let subtitle = RestoreRequestsViewModel.subtitle(for: summary)
        XCTAssertTrue(subtitle.lowercased().contains("hour"), "got: \(subtitle)")
    }

    func testSubtitleForInProgressNoEtaFallback() {
        let summary = makeSummary(status: .inProgress, eta: nil)
        let subtitle = RestoreRequestsViewModel.subtitle(for: summary)
        XCTAssertFalse(subtitle.isEmpty)
    }
}
