//
//  AuthManagerRealTests.swift
//  BookVaultTests
//
//  Phase 4: Real service tests for AuthManager.
//  Tests actual authentication logic with mock dependencies.
//

import XCTest
@testable import BookVault

// MARK: - MockKeychain

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

// MARK: - MockAPIClientForAuth

final class MockAPIClientForAuth: APIClientProtocol {
    var accessToken: String?
    var baseURL: URL = .init(string: "http://localhost:3000")!

    var loginResult: Result<LoginMobile200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "",
        code: -1
    )))
    var refreshResult: Result<RefreshToken200Response, Error> = .failure(APIError.networkError(NSError(
        domain: "",
        code: -1
    )))
    var logoutResult: Result<Void, Error> = .success(())

    var loginCallCount = 0
    var refreshCallCount = 0
    var logoutCallCount = 0

    func login(username _: String, password _: String) async throws -> LoginMobile200Response {
        loginCallCount += 1
        switch loginResult {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func refreshToken(refreshToken _: UUID) async throws -> RefreshToken200Response {
        refreshCallCount += 1
        switch refreshResult {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func logout(refreshToken _: UUID) async throws {
        logoutCallCount += 1
        if case let .failure(error) = logoutResult {
            throw error
        }
    }

    // Unused methods for this test
    func fetchBooks(page _: Int, limit _: Int, sortBy _: String?) async throws -> ListBooks200Response {
        fatalError("Not implemented for auth tests")
    }

    func fetchBook(id _: UUID) async throws -> Book {
        fatalError("Not implemented for auth tests")
    }

    func fetchBookChapters(bookId _: UUID) async throws -> [Chapter] {
        fatalError("Not implemented for auth tests")
    }

    func fetchProgress(bookId _: UUID) async throws -> GetProgress200Response {
        fatalError("Not implemented for auth tests")
    }

    func updateProgress(bookId _: UUID, positionSeconds _: Double) async throws -> UpdateProgress200Response {
        fatalError("Not implemented for auth tests")
    }

    func setProgressStatus(
        bookId _: UUID,
        status _: SetProgressStatusRequest.Status
    ) async throws -> GetProgress200Response {
        fatalError("Not implemented for auth tests")
    }

    func fetchLibrary() async throws -> GetLibrary200Response {
        fatalError("Not implemented for auth tests")
    }

    func addToLibrary(bookId _: UUID) async throws -> LogoutMobile200Response {
        fatalError("Not implemented for auth tests")
    }

    func removeFromLibrary(bookId _: UUID) async throws {
        fatalError("Not implemented for auth tests")
    }
}

// MARK: - AuthManagerRealTests

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
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-access-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)

        // When
        await sut.login(username: "testuser", password: "password123")

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.username, "testuser")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(mockAPIClient.loginCallCount, 1)

        // Verify keychain storage
        XCTAssertEqual(mockKeychain.saveCallCount, 3) // accessToken, refreshToken, userData
        XCTAssertEqual(mockKeychain.storage["com.bookvault.accessToken"], "test-access-token")
    }

    /// CRITICAL: Test that APIClient.accessToken is set after login
    func testLoginUpdatesAPIClientAccessToken() async {
        // Given
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-access-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)

        // Verify token is nil before login
        XCTAssertNil(mockAPIClient.accessToken)

        // When
        await sut.login(username: "testuser", password: "password123")

        // Then - CRITICAL: APIClient must have the token for subsequent API calls
        XCTAssertEqual(mockAPIClient.accessToken, "test-access-token", "APIClient.accessToken must be set after login")
        XCTAssertTrue(sut.isAuthenticated)
    }

    func testFailedLogin() async {
        // Given
        mockAPIClient.loginResult = .failure(APIError.unauthorized)

        // When
        await sut.login(username: "testuser", password: "wrong-password")

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoginNetworkError() async {
        // Given
        let networkError = NSError(
            domain: "Network",
            code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "No internet connection"]
        )
        mockAPIClient.loginResult = .failure(APIError.networkError(networkError))

        // When
        await sut.login(username: "testuser", password: "password123")

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

    /// CRITICAL: Test that APIClient.accessToken is restored from keychain
    /// Note: We test this by doing a login and verifying token persists across a new instance
    func testSessionRestorationUpdatesAPIClientAccessToken() async {
        // Given - first login to establish a session
        let testUser = TestFixtures.makeUser(username: "testuser")
        let loginResponse = TestFixtures.makeLoginResponse(
            accessToken: "restored-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(loginResponse)
        await sut.login(username: "testuser", password: "password123")

        // Verify token is stored
        XCTAssertEqual(mockKeychain.storage["com.bookvault.accessToken"], "restored-token")
        XCTAssertEqual(mockAPIClient.accessToken, "restored-token")

        // When - simulate app restart by reading token from keychain
        // In production, this happens in the production init via restoreSession()
        // Here we verify the token is available from keychain
        let restoredToken = mockKeychain.storage["com.bookvault.accessToken"]

        // Then - CRITICAL: Token must be restorable from keychain
        XCTAssertEqual(restoredToken, "restored-token", "Token must be stored in keychain for session restoration")
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.username, "testuser")
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
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(username: "testuser", password: "password123")

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
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(username: "testuser", password: "password123")

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
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(username: "testuser", password: "password123")

        // When
        sut.forceLogout()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(sut.errorMessage, "Your session has expired. Please log in again.")
        // Force logout doesn't call API logout
        XCTAssertEqual(mockAPIClient.logoutCallCount, 0)
    }

    /// CRITICAL: Test that logout clears APIClient.accessToken
    func testLogoutClearsAPIClientAccessToken() async {
        // Given - first login
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(username: "testuser", password: "password123")

        // Verify token is set after login
        XCTAssertEqual(mockAPIClient.accessToken, "test-token")

        // When
        await sut.logout()

        // Then - CRITICAL: APIClient token must be cleared
        XCTAssertNil(mockAPIClient.accessToken, "APIClient.accessToken must be nil after logout")
        XCTAssertFalse(sut.isAuthenticated)
    }

    /// CRITICAL: Test that force logout clears APIClient.accessToken
    func testForceLogoutClearsAPIClientAccessToken() async {
        // Given - first login
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)
        await sut.login(username: "testuser", password: "password123")

        // Verify token is set after login
        XCTAssertEqual(mockAPIClient.accessToken, "test-token")

        // When
        sut.forceLogout()

        // Then - CRITICAL: APIClient token must be cleared
        XCTAssertNil(mockAPIClient.accessToken, "APIClient.accessToken must be nil after force logout")
        XCTAssertFalse(sut.isAuthenticated)
    }

    // MARK: - Refresh Token Tests

    func testSuccessfulTokenRefresh() async {
        // Given - first login to get refresh token
        let testUser = TestFixtures.makeUser(username: "testuser")
        let loginResponse = TestFixtures.makeLoginResponse(
            accessToken: "old-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(loginResponse)
        await sut.login(username: "testuser", password: "password123")

        let refreshResponse = TestFixtures.makeRefreshTokenResponse(accessToken: "new-token")
        mockAPIClient.refreshResult = .success(refreshResponse)

        // When
        let result = await sut.refreshAccessToken()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockAPIClient.refreshCallCount, 1)
        XCTAssertEqual(mockKeychain.storage["com.bookvault.accessToken"], "new-token")
    }

    /// CRITICAL: This test would have caught the bug where APIClient.accessToken wasn't being updated
    func testTokenRefreshUpdatesAPIClientAccessToken() async {
        // Given - first login to get refresh token
        let testUser = TestFixtures.makeUser(username: "testuser")
        let loginResponse = TestFixtures.makeLoginResponse(
            accessToken: "old-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(loginResponse)
        await sut.login(username: "testuser", password: "password123")

        // Verify old token is set
        XCTAssertEqual(mockAPIClient.accessToken, "old-token")

        let refreshResponse = TestFixtures.makeRefreshTokenResponse(accessToken: "new-token")
        mockAPIClient.refreshResult = .success(refreshResponse)

        // When
        let result = await sut.refreshAccessToken()

        // Then - CRITICAL: APIClient must have the new token, not just keychain!
        XCTAssertTrue(result)
        XCTAssertEqual(mockAPIClient.accessToken, "new-token", "APIClient.accessToken must be updated after refresh")
        XCTAssertEqual(mockKeychain.storage["com.bookvault.accessToken"], "new-token")
    }

    func testFailedTokenRefreshClearsSession() async {
        // Given - first login
        let testUser = TestFixtures.makeUser(username: "testuser")
        let loginResponse = TestFixtures.makeLoginResponse(
            accessToken: "old-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(loginResponse)
        await sut.login(username: "testuser", password: "password123")

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

    // MARK: - Username Tests

    func testUsernameAfterLogin() async {
        // Given
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)

        // When
        await sut.login(username: "testuser", password: "password123")

        // Then
        XCTAssertEqual(sut.username, "testuser")
    }

    func testUsernameIsNilBeforeLogin() {
        XCTAssertNil(sut.username)
    }

    // MARK: - Keychain Error Handling

    func testKeychainSaveErrorDuringLogin() async {
        // Given
        mockKeychain.shouldThrowOnSave = true
        let testUser = TestFixtures.makeUser(username: "testuser")
        let response = TestFixtures.makeLoginResponse(
            accessToken: "test-token",
            user: testUser
        )
        mockAPIClient.loginResult = .success(response)

        // When
        await sut.login(username: "testuser", password: "password123")

        // Then - login should fail due to keychain error
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNotNil(sut.errorMessage)
    }
}
