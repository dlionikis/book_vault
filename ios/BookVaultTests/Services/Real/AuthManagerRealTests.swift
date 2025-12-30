//
//  AuthManagerRealTests.swift
//  BookVaultTests
//
//  Phase 4: Real service tests for AuthManager.
//  Tests actual authentication logic with mock dependencies.
//

import XCTest
@testable import BookVault

// MARK: - Mock Keychain for Testing

final class MockKeychain: KeychainStoring {
    var storage: [String: String] = [:]
    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    var shouldThrowOnSave = false

    func save(key: String, value: String) throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw KeychainError.saveFailed(status: -1)
        }
        storage[key] = value
    }

    func load(key: String) -> String? {
        loadCallCount += 1
        return storage[key]
    }

    func delete(key: String) {
        deleteCallCount += 1
        storage.removeValue(forKey: key)
    }
}

// MARK: - Mock API Client for AuthManager Tests

final class MockAPIClientForAuth: APIClientProtocol {
    var accessToken: String?
    var baseURL: URL = URL(string: "http://localhost:3000")!

    var loginResult: Result<LoginMobile200Response, Error> = .failure(APIError.networkError(NSError(domain: "", code: -1)))
    var refreshResult: Result<RefreshToken200Response, Error> = .failure(APIError.networkError(NSError(domain: "", code: -1)))
    var logoutResult: Result<Void, Error> = .success(())

    var loginCallCount = 0
    var refreshCallCount = 0
    var logoutCallCount = 0

    func login(email: String, password: String) async throws -> LoginMobile200Response {
        loginCallCount += 1
        switch loginResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response {
        refreshCallCount += 1
        switch refreshResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func logout(refreshToken: UUID) async throws {
        logoutCallCount += 1
        if case .failure(let error) = logoutResult {
            throw error
        }
    }

    // Unused methods for this test
    func fetchBooks(page: Int, limit: Int, sortBy: String?) async throws -> ListBooks200Response {
        fatalError("Not implemented for auth tests")
    }

    func fetchBook(id: UUID) async throws -> Book {
        fatalError("Not implemented for auth tests")
    }

    func fetchBookChapters(bookId: UUID) async throws -> [Chapter] {
        fatalError("Not implemented for auth tests")
    }

    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response {
        fatalError("Not implemented for auth tests")
    }

    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response {
        fatalError("Not implemented for auth tests")
    }

    func setProgressStatus(bookId: UUID, status: SetProgressStatusRequest.Status) async throws -> SetProgressStatus200Response {
        fatalError("Not implemented for auth tests")
    }

    func fetchLibrary() async throws -> GetLibrary200Response {
        fatalError("Not implemented for auth tests")
    }

    func addToLibrary(bookId: UUID) async throws -> AddToLibrary201Response {
        fatalError("Not implemented for auth tests")
    }

    func removeFromLibrary(bookId: UUID) async throws {
        fatalError("Not implemented for auth tests")
    }
}

// MARK: - AuthManager Real Tests

@MainActor
final class AuthManagerRealTests: XCTestCase {

    var sut: AuthManager!
    var mockAPIClient: MockAPIClientForAuth!
    var mockKeychain: MockKeychain!

    override func setUp() async throws {
        mockAPIClient = MockAPIClientForAuth()
        mockKeychain = MockKeychain()
        sut = AuthManager(apiClient: mockAPIClient, keychain: mockKeychain)
        // Disable cache clearing for tests
        sut.clearCachesOnLogout = {}
    }

    override func tearDown() async throws {
        sut = nil
        mockAPIClient = nil
        mockKeychain = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Login Tests

    func testSuccessfulLogin() async {
        // Given
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let response = LoginMobile200Response(
            user: testUser,
            accessToken: "test-access-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(response)

        // When
        await sut.login(email: "test@example.com", password: "password123")

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.email, "test@example.com")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(mockAPIClient.loginCallCount, 1)

        // Verify keychain storage
        XCTAssertEqual(mockKeychain.saveCallCount, 3) // accessToken, refreshToken, userData
        XCTAssertEqual(mockKeychain.storage["com.bookvault.accessToken"], "test-access-token")
    }

    func testFailedLogin() async {
        // Given
        mockAPIClient.loginResult = .failure(APIError.unauthorized)

        // When
        await sut.login(email: "test@example.com", password: "wrong-password")

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoginNetworkError() async {
        // Given
        let networkError = NSError(domain: "Network", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection"])
        mockAPIClient.loginResult = .failure(APIError.networkError(networkError))

        // When
        await sut.login(email: "test@example.com", password: "password123")

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Token Tests

    func testTokenRetrievalFromKeychain() {
        // Given
        mockKeychain.storage["com.bookvault.accessToken"] = "stored-token"

        // When
        let token = sut.token

        // Then
        XCTAssertEqual(token, "stored-token")
        XCTAssertEqual(mockKeychain.loadCallCount, 1)
    }

    func testTokenIsNilWhenNotStored() {
        // When
        let token = sut.token

        // Then
        XCTAssertNil(token)
    }

    // MARK: - Logout Tests

    func testSuccessfulLogout() async {
        // Given - first login
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let response = LoginMobile200Response(
            user: testUser,
            accessToken: "test-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(email: "test@example.com", password: "password123")

        // When
        await sut.logout()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockAPIClient.logoutCallCount, 1)
        XCTAssertGreaterThan(mockKeychain.deleteCallCount, 0)
    }

    func testLogoutClearsKeychainEvenIfServerFails() async {
        // Given - first login
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let response = LoginMobile200Response(
            user: testUser,
            accessToken: "test-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(email: "test@example.com", password: "password123")

        mockAPIClient.logoutResult = .failure(APIError.networkError(NSError(domain: "", code: -1)))

        // When
        await sut.logout()

        // Then - should still clear local state
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
    }

    // MARK: - Force Logout Tests

    func testForceLogout() async {
        // Given - first login
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let response = LoginMobile200Response(
            user: testUser,
            accessToken: "test-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(email: "test@example.com", password: "password123")

        // When
        sut.forceLogout()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(sut.errorMessage, "Your session has expired. Please log in again.")
        // Force logout doesn't call API logout
        XCTAssertEqual(mockAPIClient.logoutCallCount, 0)
    }

    // MARK: - Refresh Token Tests

    func testSuccessfulTokenRefresh() async {
        // Given - first login to get refresh token
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let loginResponse = LoginMobile200Response(
            user: testUser,
            accessToken: "old-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(loginResponse)
        await sut.login(email: "test@example.com", password: "password123")

        let refreshResponse = RefreshToken200Response(accessToken: "new-token")
        mockAPIClient.refreshResult = .success(refreshResponse)

        // When
        let result = await sut.refreshAccessToken()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockAPIClient.refreshCallCount, 1)
        XCTAssertEqual(mockKeychain.storage["com.bookvault.accessToken"], "new-token")
    }

    func testFailedTokenRefreshClearsSession() async {
        // Given - first login
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let loginResponse = LoginMobile200Response(
            user: testUser,
            accessToken: "old-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(loginResponse)
        await sut.login(email: "test@example.com", password: "password123")

        mockAPIClient.refreshResult = .failure(APIError.unauthorized)

        // When
        let result = await sut.refreshAccessToken()

        // Then
        XCTAssertFalse(result)
        XCTAssertFalse(sut.isAuthenticated)
    }

    func testRefreshWithoutRefreshTokenReturnsFalse() async {
        // Given - no login (no refresh token)

        // When
        let result = await sut.refreshAccessToken()

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(mockAPIClient.refreshCallCount, 0)
    }

    // MARK: - User Email Tests

    func testUserEmailAfterLogin() async {
        // Given
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let response = LoginMobile200Response(
            user: testUser,
            accessToken: "test-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(response)

        // When
        await sut.login(email: "test@example.com", password: "password123")

        // Then
        XCTAssertEqual(sut.userEmail, "test@example.com")
    }

    func testUserEmailIsNilBeforeLogin() {
        XCTAssertNil(sut.userEmail)
    }

    // MARK: - Keychain Error Handling

    func testKeychainSaveErrorDuringLogin() async {
        // Given
        mockKeychain.shouldThrowOnSave = true
        let testUser = User(
            id: UUID(),
            email: "test@example.com",
            createdAt: Date(),
            updatedAt: Date()
        )
        let response = LoginMobile200Response(
            user: testUser,
            accessToken: "test-token",
            refreshToken: UUID()
        )
        mockAPIClient.loginResult = .success(response)

        // When
        await sut.login(email: "test@example.com", password: "password123")

        // Then - login should fail due to keychain error
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNotNil(sut.errorMessage)
    }
}
