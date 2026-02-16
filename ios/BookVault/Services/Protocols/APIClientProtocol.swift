//
//  APIClientProtocol.swift
//  BookVault
//
//  Created for testing support.
//

import Foundation

/// Protocol for API client to enable testing with mocks
protocol APIClientProtocol {
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

    // Progress
    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response
    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response
    func setProgressStatus(bookId: UUID, status: SetProgressStatusRequest.Status) async throws
        -> SetProgressStatus200Response

    // Library
    func fetchLibrary() async throws -> GetLibrary200Response
    func addToLibrary(bookId: UUID) async throws -> AddToLibrary201Response
    func removeFromLibrary(bookId: UUID) async throws
}
