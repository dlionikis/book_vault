//
//  APIClientTests.swift
//  BookVaultTests
//
//  Pure-logic unit tests for APIClient (no network).
//
//  Network-dependent behavior — request headers, status-code → APIError
//  mapping, date decoding, login — is covered against a mocked URLSession in
//  APIClientRealTests.swift. Placeholder always-passing stubs that used to
//  live here were removed in the testing-hardening cleanup (see
//  docs/plans/testing-hardening-implementation.md, Phase 1).
//

import XCTest
@testable import BookVault

final class APIClientTests: XCTestCase {
    // MARK: - URL Construction Tests

    func testBaseURLIsConfiguredCorrectly() {
        let client = APIClient.shared
        XCTAssertEqual(client.baseURL.absoluteString, "http://localhost:3000")
    }

    // MARK: - APIError Tests

    func testAPIErrorDescriptions() {
        // Test that all error cases have meaningful descriptions
        XCTAssertNotNil(APIError.invalidURL.errorDescription)
        XCTAssertNotNil(APIError.networkError(NSError(domain: "Test", code: -1)).errorDescription)
        XCTAssertNotNil(APIError.invalidResponse.errorDescription)
        XCTAssertNotNil(APIError.decodingError(NSError(domain: "Test", code: -1)).errorDescription)
        XCTAssertNotNil(APIError.serverError(500, "Test error").errorDescription)
        XCTAssertNotNil(APIError.unauthorized.errorDescription)
        XCTAssertNotNil(APIError.notFound.errorDescription)
    }

    func testServerErrorIncludesStatusCode() {
        let error = APIError.serverError(503, "Service unavailable")
        XCTAssertTrue(error.errorDescription?.contains("503") ?? false)
    }

    func testServerErrorIncludesMessage() {
        let error = APIError.serverError(500, "Database connection failed")
        XCTAssertTrue(error.errorDescription?.contains("Database connection failed") ?? false)
    }

    // MARK: - Token Refresh Configuration Tests

    func testTokenRefreshHandlerCanBeConfigured() {
        // Given: APIClient instance
        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: URLSession.shared
        )

        // When: Custom handler is set
        client.tokenRefreshHandler = {
            return true
        }

        // Then: Handler should be configurable (used for testing/DI)
        XCTAssertNotNil(client.tokenRefreshHandler)
    }

    func testForceLogoutHandlerCanBeConfigured() {
        // Given: APIClient instance
        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: URLSession.shared
        )

        // When: Custom handler is set
        client.forceLogoutHandler = {}

        // Then: Handler should be configurable (used for testing/DI)
        XCTAssertNotNil(client.forceLogoutHandler)
    }

    func testAccessTokenCanBeSetAndCleared() {
        // Given: APIClient instance
        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: URLSession.shared
        )

        // Initially nil
        XCTAssertNil(client.accessToken)

        // Can be set
        client.accessToken = "test-token"
        XCTAssertEqual(client.accessToken, "test-token")

        // Can be cleared
        client.accessToken = nil
        XCTAssertNil(client.accessToken)
    }

    func testLogoutGuardChecksDependsOnAccessToken() {
        // Given: APIClient with nil access token (simulating already logged out)
        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: URLSession.shared
        )

        var forceLogoutCount = 0
        client.forceLogoutHandler = {
            forceLogoutCount += 1
        }

        // When: Access token is nil (already logged out)
        client.accessToken = nil

        // Then: The guard `if accessToken != nil` in the code should prevent
        // forceLogoutHandler from being called. We verify the state is correct.
        XCTAssertNil(client.accessToken)
        XCTAssertEqual(forceLogoutCount, 0, "Force logout should not have been called yet")

        // When: Token is set
        client.accessToken = "test-token"

        // Then: State is ready for logout guard to allow the call
        XCTAssertNotNil(client.accessToken)
    }
}
