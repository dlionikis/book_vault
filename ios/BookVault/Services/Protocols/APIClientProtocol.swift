//
//  APIClientProtocol.swift
//  BookVault
//
//  Created for testing support.
//

import Foundation

/// Protocol for API client to enable testing with mocks
protocol APIClientProtocol: Sendable {
    var accessToken: String? { get set }
    var baseURL: URL { get }

    // Authentication
    func login(username: String, password: String) async throws -> LoginMobile200Response
    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response
    func logout(refreshToken: UUID) async throws

    // Books
    func fetchBooks(page: Int, limit: Int, sortBy: String?) async throws -> ListBooks200Response
    func fetchBook(id: UUID) async throws -> Book
    func fetchBookChapters(bookId: UUID) async throws -> [Chapter]

    // Series view (Books/Series toggle)
    func fetchCatalogSeriesView(page: Int, limit: Int) async throws -> GetCatalogSeriesView200Response
    func fetchLibrarySeriesView(page: Int, limit: Int) async throws -> GetLibrarySeriesView200Response

    // Progress
    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response
    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response
    func setProgressStatus(bookId: UUID, status: SetProgressStatusRequest.Status) async throws
        -> GetProgress200Response

    // Library
    func fetchLibrary() async throws -> GetLibrary200Response
    func addToLibrary(bookId: UUID) async throws -> LogoutMobile200Response
    func removeFromLibrary(bookId: UUID) async throws

    // Downloads
    func checkDownloadEligibility(bookId: UUID) async throws -> CheckDownloadEligibility200Response
    func generateDownloadUrl(bookId: UUID, deviceId: String?) async throws -> DownloadUrlResult

    // Streaming
    func getBookStream(bookId: UUID) async throws -> BookStreamResponse

    // Restore / archive
    func restoreBook(bookId: UUID) async throws -> BookStreamResponse
    func getBookRestoreStatus(bookId: UUID) async throws -> RestoreStatus
    func listRestores() async throws -> RestoresListResponse
    func restoreSeries(seriesId: UUID) async throws -> RestoreSeries200Response

    // Notifications
    @discardableResult
    func registerDeviceToken(deviceToken: String) async throws -> RegisterDeviceToken200Response
}
