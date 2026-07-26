//
//  MockAPIClient.swift
//  BookVaultTests
//
//  Mock API client for testing - allows configuring responses and tracking calls.
//

import Foundation
@testable import BookVault

/// Mock API client for testing - allows configuring responses and tracking calls
class MockAPIClient: APIClientProtocol {
    var accessToken: String?
    var baseURL: URL = .init(string: "http://localhost:3000")!

    // MARK: - Call Tracking

    var loginCalls: [(username: String, password: String)] = []
    var refreshTokenCalls: [UUID] = []
    var logoutCalls: [UUID] = []
    var fetchBooksCalls: [(page: Int, limit: Int, sortBy: String?)] = []
    var fetchCatalogSeriesViewCalls: [(page: Int, limit: Int)] = []
    var fetchLibrarySeriesViewCalls: [(page: Int, limit: Int)] = []
    var fetchBookCalls: [UUID] = []
    var fetchBookChaptersCalls: [UUID] = []
    var fetchProgressCalls: [UUID] = []
    var updateProgressCalls: [(bookId: UUID, positionSeconds: Double)] = []
    var setProgressStatusCalls: [(bookId: UUID, status: SetProgressStatusRequest.Status)] = []
    var fetchLibraryCalls: Int = 0
    var addToLibraryCalls: [UUID] = []
    var removeFromLibraryCalls: [UUID] = []
    var checkDownloadEligibilityCalls: [UUID] = []
    var generateDownloadUrlCalls: [(bookId: UUID, deviceId: String?)] = []
    var getBookStreamCalls: [UUID] = []
    var restoreBookCalls: [UUID] = []
    var getBookRestoreStatusCalls: [UUID] = []
    var listRestoresCalls: Int = 0
    var registerDeviceTokenCalls: [String] = []
    var restoreSeriesCalls: [UUID] = []

    // MARK: - Configurable Results

    var loginResult: Result<LoginMobile200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var refreshTokenResult: Result<RefreshToken200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var logoutResult: Result<Void, Error> = .success(())
    var fetchBooksResult: Result<ListBooks200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var fetchCatalogSeriesViewResult: Result<GetCatalogSeriesView200Response, Error> = .failure(
        APIError.networkError(NSError(domain: "Test", code: -1))
    )
    var fetchLibrarySeriesViewResult: Result<GetLibrarySeriesView200Response, Error> = .failure(
        APIError.networkError(NSError(domain: "Test", code: -1))
    )
    var fetchBookResult: Result<Book, Error> = .failure(APIError.networkError(NSError(domain: "Test", code: -1)))
    var fetchBookChaptersResult: Result<[Chapter], Error> = .success([])
    var fetchProgressResult: Result<GetProgress200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var updateProgressResult: Result<UpdateProgress200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var setProgressStatusResult: Result<GetProgress200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var fetchLibraryResult: Result<GetLibrary200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var addToLibraryResult: Result<LogoutMobile200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "Test",
        code: -1
    )))
    var removeFromLibraryResult: Result<Void, Error> = .success(())
    var checkDownloadEligibilityResult: Result<CheckDownloadEligibility200Response, Error> = .failure(
        APIError.networkError(NSError(domain: "Test", code: -1))
    )
    var generateDownloadUrlResult: Result<DownloadUrlResult, Error> = .failure(
        APIError.networkError(NSError(domain: "Test", code: -1))
    )
    var getBookStreamResult: Result<BookStreamResponse, Error> = .success(
        BookStreamResponse(status: .available, streamUrl: "http://localhost:3000/api/audio/test.m4b")
    )
    var restoreBookResult: Result<BookStreamResponse, Error> = .success(
        BookStreamResponse(status: .restoring, message: "Restore in progress")
    )
    var getBookRestoreStatusResult: Result<RestoreStatus, Error> = .success(
        RestoreStatus(status: .available)
    )
    var listRestoresResult: Result<RestoresListResponse, Error> = .success(
        RestoresListResponse(restores: [])
    )
    var registerDeviceTokenResult: Result<RegisterDeviceToken200Response, Error> = .success(
        RegisterDeviceToken200Response(success: true)
    )
    var restoreSeriesResult: Result<RestoreSeries200Response, Error> = .success(
        RestoreSeries200Response(message: "Restore initiated for 0 books", total: 0, results: [])
    )

    // MARK: - Reset

    func reset() {
        loginCalls = []
        refreshTokenCalls = []
        logoutCalls = []
        fetchBooksCalls = []
        fetchCatalogSeriesViewCalls = []
        fetchLibrarySeriesViewCalls = []
        fetchBookCalls = []
        fetchBookChaptersCalls = []
        fetchProgressCalls = []
        updateProgressCalls = []
        setProgressStatusCalls = []
        fetchLibraryCalls = 0
        addToLibraryCalls = []
        removeFromLibraryCalls = []
        checkDownloadEligibilityCalls = []
        generateDownloadUrlCalls = []
        getBookStreamCalls = []
        restoreBookCalls = []
        getBookRestoreStatusCalls = []
        listRestoresCalls = 0
        registerDeviceTokenCalls = []
        restoreSeriesCalls = []
        accessToken = nil
    }

    // MARK: - APIClientProtocol Implementation

    func login(username: String, password: String) async throws -> LoginMobile200Response {
        loginCalls.append((username, password))
        return try loginResult.get()
    }

    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response {
        refreshTokenCalls.append(refreshToken)
        return try refreshTokenResult.get()
    }

    func logout(refreshToken: UUID) async throws {
        logoutCalls.append(refreshToken)
        try logoutResult.get()
    }

    func fetchBooks(page: Int, limit: Int, sortBy: String?) async throws -> ListBooks200Response {
        fetchBooksCalls.append((page, limit, sortBy))
        return try fetchBooksResult.get()
    }

    func fetchCatalogSeriesView(page: Int, limit: Int) async throws -> GetCatalogSeriesView200Response {
        fetchCatalogSeriesViewCalls.append((page, limit))
        return try fetchCatalogSeriesViewResult.get()
    }

    func fetchLibrarySeriesView(page: Int, limit: Int) async throws -> GetLibrarySeriesView200Response {
        fetchLibrarySeriesViewCalls.append((page, limit))
        return try fetchLibrarySeriesViewResult.get()
    }

    func fetchBook(id: UUID) async throws -> Book {
        fetchBookCalls.append(id)
        return try fetchBookResult.get()
    }

    func fetchBookChapters(bookId: UUID) async throws -> [Chapter] {
        fetchBookChaptersCalls.append(bookId)
        return try fetchBookChaptersResult.get()
    }

    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response {
        fetchProgressCalls.append(bookId)
        return try fetchProgressResult.get()
    }

    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response {
        updateProgressCalls.append((bookId, positionSeconds))
        return try updateProgressResult.get()
    }

    func setProgressStatus(
        bookId: UUID,
        status: SetProgressStatusRequest.Status
    ) async throws -> GetProgress200Response {
        setProgressStatusCalls.append((bookId, status))
        return try setProgressStatusResult.get()
    }

    func fetchLibrary() async throws -> GetLibrary200Response {
        fetchLibraryCalls += 1
        return try fetchLibraryResult.get()
    }

    func addToLibrary(bookId: UUID) async throws -> LogoutMobile200Response {
        addToLibraryCalls.append(bookId)
        return try addToLibraryResult.get()
    }

    func removeFromLibrary(bookId: UUID) async throws {
        removeFromLibraryCalls.append(bookId)
        try removeFromLibraryResult.get()
    }

    func checkDownloadEligibility(bookId: UUID) async throws -> CheckDownloadEligibility200Response {
        checkDownloadEligibilityCalls.append(bookId)
        return try checkDownloadEligibilityResult.get()
    }

    func generateDownloadUrl(bookId: UUID, deviceId: String?) async throws -> DownloadUrlResult {
        generateDownloadUrlCalls.append((bookId, deviceId))
        return try generateDownloadUrlResult.get()
    }

    func getBookStream(bookId: UUID) async throws -> BookStreamResponse {
        getBookStreamCalls.append(bookId)
        return try getBookStreamResult.get()
    }

    func restoreBook(bookId: UUID) async throws -> BookStreamResponse {
        restoreBookCalls.append(bookId)
        return try restoreBookResult.get()
    }

    func getBookRestoreStatus(bookId: UUID) async throws -> RestoreStatus {
        getBookRestoreStatusCalls.append(bookId)
        return try getBookRestoreStatusResult.get()
    }

    func listRestores() async throws -> RestoresListResponse {
        listRestoresCalls += 1
        return try listRestoresResult.get()
    }

    @discardableResult
    func registerDeviceToken(deviceToken: String) async throws -> RegisterDeviceToken200Response {
        registerDeviceTokenCalls.append(deviceToken)
        return try registerDeviceTokenResult.get()
    }

    func restoreSeries(seriesId: UUID) async throws -> RestoreSeries200Response {
        restoreSeriesCalls.append(seriesId)
        return try restoreSeriesResult.get()
    }
}
